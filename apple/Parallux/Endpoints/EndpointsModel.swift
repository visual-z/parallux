import Foundation
import Libbox
import Observation
import ParalluxKit

/// Tailscale, OpenVPN and OpenConnect endpoint states while the diagnostics page is open.
@MainActor @Observable
final class EndpointsModel {
    struct TailscalePeer: Identifiable, Equatable {
        var id: String
        var name: String
        var online: Bool
        var exitNodeOption: Bool
        var isExitNode: Bool
    }

    struct FormField: Identifiable, Equatable {
        var id: String { key }
        var key: String
        var label: String
        var secret: Bool
    }

    private(set) var statuses: [EndpointStatus] = []
    /// OpenConnect challenge forms by endpoint tag (fields come from the server).
    private(set) var forms: [String: [FormField]] = [:]
    private(set) var peers: [String: [TailscalePeer]] = [:]
    private(set) var waitingFiles: [String: Int32] = [:]
    @ObservationIgnored private var subscriptions: [AnyObject] = []
    @ObservationIgnored private var client: LibboxCommandClient?

    func start() {
        guard client == nil, let client = try? CommandTarget.standalone() else { return }
        self.client = client
        let box = Box(client)
        let tailscale = TailscaleHandler { [weak self] in self?.merge(.tailscale, $0, $1, $2) }
        let openVPN = VPNHandler(kind: .openVPN) { [weak self] items, _ in self?.merge(.openVPN, items, [:], [:]) }
        let openConnect = ConnectHandler { [weak self] items, forms in
            self?.merge(.openConnect, items, [:], [:])
            self?.forms = forms
        }
        Task.detached {
            let a = try? box.value.subscribeTailscaleStatus(tailscale)
            let b = try? box.value.subscribeOpenVPNStatus(openVPN)
            let c = try? box.value.subscribeOpenConnectStatus(openConnect)
            await MainActor.run { self.subscriptions = [a, b, c, tailscale, openVPN, openConnect].compactMap { $0 as AnyObject? } }
        }
    }

    func stop() {
        for subscription in subscriptions {
            try? (subscription as? LibboxTailscaleStatusSubscription)?.close()
            try? (subscription as? LibboxOpenVPNStatusSubscription)?.close()
            try? (subscription as? LibboxOpenConnectStatusSubscription)?.close()
        }
        subscriptions = []
        let box = client.map(Box.init)
        client = nil
        Task.detached { try? box?.value.disconnect() }
    }

    private func merge(_ kind: EndpointStatus.Kind, _ items: [EndpointStatus], _ peers: [String: [TailscalePeer]], _ files: [String: Int32]) {
        statuses = statuses.filter { $0.kind != kind } + items
        if kind == .tailscale {
            self.peers = peers
            waitingFiles = files
        }
    }

    func setExitNode(endpoint: String, peer: String) {
        let box = client.map(Box.init)
        Task.detached { try? box?.value.setTailscaleExitNode(endpoint, stableID: peer) }
    }

    /// `values` are username/password for OpenVPN, or the form's submission keys for OpenConnect.
    func answer(_ status: EndpointStatus, values: [String: String]) {
        guard let challengeID = status.challengeID, let box = client.map(Box.init) else { return }
        Task.detached {
            switch status.kind {
            case .openVPN:
                let response = LibboxOpenVPNChallengeResponse()
                response.username = values["username"] ?? ""
                response.password = values["password"] ?? ""
                try? box.value.submitOpenVPNChallengeResponse(status.tag, challengeID: challengeID, response: response)
            case .openConnect:
                guard let form = LibboxNewOpenConnectFormValues() else { return }
                for (key, value) in values { form.add(key, value: value) }
                try? box.value.submitOpenConnectAuthResponse(status.tag, challengeID: challengeID, response: LibboxNewOpenConnectAuthFormResponse(form))
            case .tailscale:
                break
            }
        }
    }

    func cancel(_ status: EndpointStatus) {
        guard let challengeID = status.challengeID, let box = client.map(Box.init) else { return }
        Task.detached {
            if status.kind == .openVPN { try? box.value.cancelOpenVPNChallenge(status.tag, challengeID: challengeID) }
            if status.kind == .openConnect { try? box.value.cancelOpenConnectAuthChallenge(status.tag, challengeID: challengeID) }
        }
    }

    struct Box<T>: @unchecked Sendable {
        let value: T
        init(_ value: T) { self.value = value }
    }

    private final class TailscaleHandler: NSObject, LibboxTailscaleStatusHandlerProtocol, @unchecked Sendable {
        let update: @MainActor ([EndpointStatus], [String: [TailscalePeer]], [String: Int32]) -> Void
        init(_ update: @escaping @MainActor ([EndpointStatus], [String: [TailscalePeer]], [String: Int32]) -> Void) { self.update = update }
        func onError(_ message: String?) {}
        func onStatusUpdate(_ status: LibboxTailscaleStatusUpdate?) {
            var items: [EndpointStatus] = []
            var peers: [String: [TailscalePeer]] = [:]
            var files: [String: Int32] = [:]
            let endpoints = status?.endpoints()
            while let endpoints, endpoints.hasNext(), let e = endpoints.next() {
                items.append(EndpointStatus(kind: .tailscale, tag: e.endpointTag, state: e.backendState, stateText: e.stateText, authURL: e.authURL))
                files[e.endpointTag] = e.waitingFileCount
                var list: [TailscalePeer] = []
                let groups = e.userGroups()
                while let groups, groups.hasNext(), let group = groups.next() {
                    let iterator = group.peers()
                    while let iterator, iterator.hasNext(), let peer = iterator.next() {
                        list.append(TailscalePeer(id: peer.stableID, name: peer.hostName, online: peer.online,
                                                  exitNodeOption: peer.exitNodeOption, isExitNode: peer.exitNode))
                    }
                }
                peers[e.endpointTag] = list
            }
            let update = self.update
            Task { @MainActor in update(items, peers, files) }
        }
    }

    /// OpenVPN and OpenConnect handlers are separate classes: both protocols
    /// declare `onStatusUpdate:`, one Objective-C selector per class.
    private final class VPNHandler: NSObject, LibboxOpenVPNStatusHandlerProtocol, @unchecked Sendable {
        let update: @MainActor ([EndpointStatus], [String: [FormField]]) -> Void
        init(kind _: EndpointStatus.Kind, _ update: @escaping @MainActor ([EndpointStatus], [String: [FormField]]) -> Void) {
            self.update = update
        }
        func onError(_ message: String?) {}
        func onStatusUpdate(_ status: LibboxOpenVPNStatusUpdate?) {
            var items: [EndpointStatus] = []
            let endpoints = status?.endpoints()
            while let endpoints, endpoints.hasNext(), let e = endpoints.next() {
                items.append(EndpointStatus(kind: .openVPN, tag: e.endpointTag, state: e.state, stateText: e.stateText, error: e.error,
                                            challengeID: e.challenge.map(\.id_)))
            }
            let update = self.update
            Task { @MainActor in update(items, [:]) }
        }
    }

    private final class ConnectHandler: NSObject, LibboxOpenConnectStatusHandlerProtocol, @unchecked Sendable {
        let update: @MainActor ([EndpointStatus], [String: [FormField]]) -> Void
        init(_ update: @escaping @MainActor ([EndpointStatus], [String: [FormField]]) -> Void) { self.update = update }
        func onError(_ message: String?) {}
        func onStatusUpdate(_ status: LibboxOpenConnectStatusUpdate?) {
            var items: [EndpointStatus] = []
            var forms: [String: [FormField]] = [:]
            let endpoints = status?.endpoints()
            while let endpoints, endpoints.hasNext(), let e = endpoints.next() {
                items.append(EndpointStatus(kind: .openConnect, tag: e.endpointTag, state: e.state, stateText: e.stateText, error: e.error,
                                            challengeID: e.authChallenge.map(\.id_)))
                var fields: [FormField] = []
                let iterator = e.authChallenge?.form?.fields()
                while let iterator, iterator.hasNext(), let field = iterator.next() {
                    fields.append(FormField(key: field.submissionKey, label: field.label.isEmpty ? field.name : field.label,
                                            secret: field.kind.lowercased() == "password"))
                }
                if !fields.isEmpty { forms[e.endpointTag] = fields }
            }
            let update = self.update
            let snapshot = forms
            Task { @MainActor in update(items, snapshot) }
        }
    }
}
