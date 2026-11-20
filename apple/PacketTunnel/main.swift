import Foundation
import NetworkExtension

// A system extension runs as its own process; hand control to NetworkExtension,
// which instantiates PacketTunnelProvider (Info.plist NEProviderClasses).
autoreleasepool {
    NEProvider.startSystemExtensionMode()
}
dispatchMain()
