import Foundation
import Testing
@testable import ParalluxKit

@Suite struct URLRouteTests {
    private func route(_ text: String) -> URLRoute? {
        URL(string: text).flatMap(URLRoute.parse)
    }

    @Test func urlRoutesCoverEveryLinkAndRejectTheRest() {
        let server = "parallux://aggregation-server?v=1&host=203.0.113.24&port=39000&psk=Zq3x0b9Ck2mVv7yQ1nH8sJt4wE6rU5aPxLdFgTiO0Bc#Tokyo"
        #expect(route(server) == .addAggregationServer(server))
        let sfm = "sing-box://import-remote-profile?url=https%3A%2F%2Fexample.com%2Fsub#Main"
        #expect(route(sfm) == .importRemoteProfile(sfm))
        let ours = "parallux://import-remote-profile?url=https%3A%2F%2Fexample.com%2Fsub#Main"
        #expect(route(ours) == .importRemoteProfile(ours))
        #expect(route("parallux://connect") == .connect)
        #expect(route("PARALLUX://Disconnect") == .disconnect)
        #expect(route("parallux://toggle") == .toggle)
        #expect(route("parallux://unknown") == nil)
        #expect(route("parallux://") == nil)
        #expect(route("https://aggregation-server?v=1") == nil)
        #expect(route("sing-box://connect") == nil, "sing-box:// only carries profile imports")
        #expect(route("mailto:someone@example.com") == nil)
    }
}

@Suite struct ApplicationsLocationTests {
    @Test func applicationsLocationIsClassifiedFromTheBundlePath() {
        let home = "/Users/alice"
        func classify(_ path: String) -> ApplicationsLocation { ApplicationsLocation.classify(bundlePath: path, home: home) }
        #expect(classify("/Applications/Parallux.app") == .ok)
        #expect(classify("/Applications/Network/Parallux.app") == .ok)
        #expect(classify("/Users/alice/Applications/Parallux.app") == .ok)
        #expect(classify("/private/var/folders/xy/abc/T/AppTranslocation/1234-5678/d/Parallux.app") == .translocated)
        #expect(classify("/Users/alice/Library/Developer/Xcode/DerivedData/Parallux-abc/Build/Products/Debug/Parallux.app") == .notInApplications)
        #expect(classify("/Users/alice/Downloads/Parallux.app") == .notInApplications)
        #expect(classify("/Users/alice/parallux/.build/xcode-signed/Build/Products/Debug/Parallux.app") == .notInApplications)
        #expect(classify("/ApplicationsFake/Parallux.app") == .notInApplications)
        #expect(classify("/Users/bob/Applications/Parallux.app") == .notInApplications, "another user's folder")
        #expect(classify("") == .notInApplications)
    }
}

@Suite struct WidgetSnapshotTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    @Test func widgetSnapshotsRoundTripAndGoStale() throws {
        let snapshot = WidgetSnapshot(connected: true, mode: "bond", linkCount: 3, rate: 76_500_000, profileName: "主力机场", updatedAt: now)
        #expect(WidgetSnapshot.decode(snapshot.encoded()) == snapshot)
        #expect(WidgetSnapshot.decode(nil) == nil)
        #expect(WidgetSnapshot.decode(Data("garbage".utf8)) == nil)
        #expect(!snapshot.isStale(now: now.addingTimeInterval(59)))
        #expect(snapshot.isStale(now: now.addingTimeInterval(60)))
        #expect(!snapshot.isStale(now: now.addingTimeInterval(-5)), "a clock step back is not stale")

        var throttle = WidgetSnapshotThrottle()
        let first = throttle.shouldWrite(snapshot)
        #expect(first, "the first snapshot is written")
        var faster = snapshot
        faster.rate = 1
        faster.updatedAt = now.addingTimeInterval(4)
        let early = throttle.shouldWrite(faster)
        #expect(!early, "a rate change within 5 s waits")
        faster.updatedAt = now.addingTimeInterval(5)
        let later = throttle.shouldWrite(faster)
        #expect(later, "after 5 s it is written")
        var off = faster
        off.connected = false
        off.updatedAt = now.addingTimeInterval(5.5)
        let changed = throttle.shouldWrite(off)
        #expect(changed, "a state change is written at once")
        #expect(WidgetSnapshotThrottle.isStateChange(from: faster, to: off))
        #expect(!WidgetSnapshotThrottle.isStateChange(from: snapshot, to: faster), "rate alone is not a state change")
        var moreLinks = snapshot
        moreLinks.linkCount = 2
        #expect(WidgetSnapshotThrottle.isStateChange(from: snapshot, to: moreLinks))
        var otherMode = snapshot
        otherMode.mode = "failover"
        #expect(WidgetSnapshotThrottle.isStateChange(from: snapshot, to: otherMode))
        #expect(WidgetSnapshotThrottle.isStateChange(from: nil, to: snapshot))
    }
}

@Suite struct CoreNotificationTests {
    @Test func coreNotificationsAreQueuedWithACap() {
        let queue = NotificationQueue()
        #expect(queue.drain().isEmpty)
        queue.push(CoreNotification(identifier: "a", title: "t", body: "b", openURL: "https://example.com"))
        let one = queue.drain()
        #expect(one.map(\.identifier) == ["a"])
        #expect(queue.drain().isEmpty, "drain empties the queue")
        #expect(NotificationQueue.decode(NotificationQueue.encode(one)) == one)
        #expect(NotificationQueue.decode(Data("x".utf8)).isEmpty)
        for index in 0..<(NotificationQueue.capacity + 5) {
            queue.push(CoreNotification(identifier: "n\(index)"))
        }
        let drained = queue.drain()
        #expect(drained.count == NotificationQueue.capacity)
        #expect(drained.first?.identifier == "n5", "the oldest are dropped")
        #expect(drained.last?.identifier == "n\(NotificationQueue.capacity + 4)")
    }
}

@Suite struct SettingsTabTests {
    @Test func aboutIsTheLastSettingsTab() {
        #expect(SettingsTab.allCases.last == .about)
        #expect(SettingsTab.about.title == "关于")
        #expect(!SettingsTab.about.symbol.isEmpty)
        #expect(SettingsTab.allCases.count == 7)
    }
}
