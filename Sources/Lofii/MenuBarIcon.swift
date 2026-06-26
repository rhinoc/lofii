import AppKit

enum MenuBarIcon {
    static let image: NSImage = {
        guard let url = LofiiResources.url(forResource: "MenuBarIcon", withExtension: "svg"),
              let image = NSImage(contentsOf: url)
        else {
            return NSImage(systemSymbolName: "radio", accessibilityDescription: "lofii")!
        }
        image.size = NSSize(width: 22, height: 22)
        image.isTemplate = true
        return image
    }()
}
