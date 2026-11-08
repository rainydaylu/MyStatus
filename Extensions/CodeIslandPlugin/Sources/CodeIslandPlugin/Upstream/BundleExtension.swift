import Foundation

extension Bundle {
    /// Resolve the installed resource bundle without using the build machine's path.
    static let appModule: Bundle = {
        let bundleName = "CodeIslandPlugin_CodeIslandPlugin"

        // .app bundle: Contents/Resources/<bundleName>.bundle
        if let resourceURL = CodeIslandPluginResources.folder,
           let bundle = Bundle(url: resourceURL.appendingPathComponent("\(bundleName).bundle")) {
            return bundle
        }

        let adjacent = Bundle.main.bundleURL.appendingPathComponent("\(bundleName).bundle")
        return Bundle(url: adjacent) ?? .main
    }()
}
