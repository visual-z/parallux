import Foundation

// launchd starts this tool as root from the app bundle (SMAppService.daemon,
// plist Contents/Library/LaunchDaemons/<label>.plist). It serves XPC until
// launchd stops it; KeepAlive restarts it if it crashes.
let service = HelperService()
service.start()
dispatchMain()
