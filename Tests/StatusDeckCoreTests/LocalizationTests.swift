import StatusDeckKit
import Testing

@Suite struct LocalizationTests {
    @Test(arguments: [
        ("fr-CA", DeckLanguage.french), ("de-CH", .german), ("ja-JP", .japanese),
        ("ko-KR", .korean), ("zh-CN", .chinese), ("zh-Hant-TW", .traditionalChinese),
        ("zh-HK", .traditionalChinese), ("zh_Hant_MO", .traditionalChinese),
        ("zh-Hans-HK", .chinese), ("yue-HK", .traditionalChinese),
        ("en-GB", .english), ("es-ES", .english), ("system", .english), ("", .english)
    ])
    func resolvesPrimarySystemLanguage(_ test: (String, DeckLanguage)) {
        #expect(DeckLanguage.system.resolved(preferredLanguage: test.0) == test.1)
    }

    @Test func manualSelectionAndTranslatedLabels() {
        #expect(DeckLanguage.german.resolved(preferredLanguage: "fr-CA") == .german)
        #expect(DeckLanguage.system.resolved(preferredLanguage: nil) == .english)
        #expect(DeckLanguage.french.translation("显示器") == "Écrans")
        #expect(DeckLanguage.german.translation("设置", english: "Preferences") == "Einstellungen")
        #expect(DeckLanguage.japanese.translation("剪贴板") == "クリップボード")
        #expect(DeckLanguage.korean.translation("启用") == "활성화")
        #expect(DeckLanguage.traditionalChinese.translation("显示器软件鼠标剪贴板") == "顯示器軟體滑鼠剪貼簿")
        #expect(DeckLanguage.system.resolved(preferredLanguage: "es").translation("声音") == "Sound")
        #expect(DeckLanguage.french.translation("新文字", english: "Untranslated label") == "Untranslated label")
    }
}
