import Foundation
import StatusDeckKit

private let hangingResources: Bundle? = {
    var info = Dl_info()
    let entry: @convention(c) () -> UnsafeMutableRawPointer = statusdeckPluginCreate
    let address = unsafeBitCast(entry, to: UnsafeRawPointer.self)
    guard dladdr(address, &info) != 0, let library = info.dli_fname else { return nil }
    let folder = URL(fileURLWithPath: String(cString: library)).deletingLastPathComponent()
    return Bundle(url: folder.appendingPathComponent("HangingClipboardPlugin_Tendedero.bundle"))
}()

func L(_ english: String) -> String {
    let language = DeckLanguage.current.resolved()
    guard language != .english else { return english }
    let lookup = language == .traditionalChinese ? DeckLanguage.chinese : language
    if let path = hangingResources?.path(forResource: lookup.rawValue, ofType: "lproj"),
       let bundle = Bundle(path: path) {
        let value = bundle.localizedString(forKey: english, value: english, table: nil)
        if value != english { return language.translation(value, english: value) }
    }
    return language.translation(english, english: english)
}
