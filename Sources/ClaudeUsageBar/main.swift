import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// .accessory = no Dock icon, no entry in Cmd+Tab. This is the runtime
// equivalent of setting LSUIElement in an Info.plist, and works even
// though this is a bare `swift run` executable rather than a proper .app.
app.setActivationPolicy(.accessory)

app.run()
