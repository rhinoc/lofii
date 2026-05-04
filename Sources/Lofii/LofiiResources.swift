import Foundation

/// SwiftPM places resources in `lofii_lofii.bundle` (`Bundle.module`) for
/// development builds. Release `.app` bundles flatten the same resources into
/// `Contents/Resources/` (`Bundle.main`) to avoid a nested bundle at the app
/// root, which would break codesign.
enum LofiiResources {
    static let bundle: Bundle = {
        let main = Bundle.main
        if main.url(forResource: "Statics", withExtension: nil) != nil
            || main.url(forResource: "BongoCat", withExtension: nil) != nil
        {
            return main
        }
        return Bundle.module
    }()
}
