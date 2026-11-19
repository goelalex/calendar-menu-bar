import AppKit

let app = NSApplication.shared
let controller = StatusItemController()
app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
controller.start()
app.run()
