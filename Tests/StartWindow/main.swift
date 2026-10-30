import AppKit

var failures = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { failures += 1; print("FAIL: \(message)") }
}
func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
func settleAnimation() { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.24)) }
final class RowActions: NSObject {
    var opened = 0
    @objc func open(_ sender: Any?) { opened += 1 }
}
// AppKit's real store writes the user's shared history. This in-memory boundary
// keeps tests isolated while exercising the production history reconstruction.
final class MemoryRecentDocuments: RecentDocumentStore {
    var recentDocumentURLs: [URL]
    var clearCount = 0
    init(_ urls: [URL]) { recentDocumentURLs = urls }
    func clearRecentDocuments(_ sender: Any?) { clearCount += 1; recentDocumentURLs = [] }
    func noteNewRecentDocumentURL(_ url: URL) {
        recentDocumentURLs.removeAll { $0 == url }
        recentDocumentURLs.insert(url, at: 0)
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let fixtureDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: fixtureDirectory) }
let newest = fixtureDirectory.appendingPathComponent("newest.docx")
let removed = fixtureDirectory.appendingPathComponent("remove.docx")
let oldest = fixtureDirectory.appendingPathComponent("oldest.docx")
try Data("underlying document".utf8).write(to: removed)
let history = MemoryRecentDocuments([newest, removed, oldest])
RecentDocumentHistory.remove(removed, from: history)
check(history.recentDocumentURLs == [newest, oldest], "single removal preserves newest-first order")
let fileAfterRemoval = try Data(contentsOf: removed)
check(fileAfterRemoval == Data("underlying document".utf8), "single removal preserves the original file")
RecentDocumentHistory.remove(removed, from: history)
check(history.clearCount == 1, "removing a missing history item leaves native history untouched")
RecentDocumentHistory.remove(newest, from: history)
RecentDocumentHistory.remove(oldest, from: history)
check(history.recentDocumentURLs.isEmpty, "removing the final item empties history")

let longHistory = MemoryRecentDocuments([newest, removed, oldest,
    fixtureDirectory.appendingPathComponent("fourth.docx"),
    fixtureDirectory.appendingPathComponent("fifth.docx"),
    fixtureDirectory.appendingPathComponent("sixth.docx"),
    fixtureDirectory.appendingPathComponent("seventh.docx")])
RecentDocumentHistory.remove(removed, from: longHistory)
check(longHistory.recentDocumentURLs.map(\.lastPathComponent) == ["newest.docx", "oldest.docx", "fourth.docx", "fifth.docx", "sixth.docx", "seventh.docx"], "removal also preserves entries beyond the five visible rows")

let preferencesName = "HanXStartWindowTests." + UUID().uuidString
let preferences = UserDefaults(suiteName: preferencesName)!
defer { preferences.removePersistentDomain(forName: preferencesName) }
var completeRegistration: (([String]) -> Void)?
let registration = DefaultAppRegistration(preferences: preferences) { completeRegistration = $0 }
let target = RowActions()
var removedURL: URL?
let row = RecentRow(url: removed, target: target, action: #selector(RowActions.open(_:))) { removedURL = $0 }
let remove = descendants(row).compactMap { $0 as? NSButton }.first
check(remove != nil, "each recent row provides a separate remove action")
if let remove {
    check(remove.alphaValue == 0, "remove action starts invisible outside the row")
    row.hovering = true
    settleAnimation()
    check(remove.alphaValue == 1, "remove action fades in when the pointer enters the row")
    row.layoutSubtreeIfNeeded()
    check(remove.frame.maxX <= row.bounds.maxX && remove.frame.minX > row.bounds.midX, "remove action stays at the trailing edge")
    remove.performClick(nil)
    check(removedURL == removed, "remove action identifies only its own history item")
    check(target.opened == 0, "clicking remove does not open the document")
    row.hovering = false
    settleAnimation()
    check(remove.alphaValue == 0, "remove action fades out when the pointer leaves the row")
    _ = row.accessibilityPerformPress()
    check(target.opened == 1, "the row retains its separate document-open action")
}
let uiHistory = MemoryRecentDocuments([newest, removed, oldest])
let start = StartWindowController(recentDocuments: uiHistory, defaultRegistration: registration)
let content = start.window!.contentView!
var buttons = descendants(content).compactMap { $0 as? NSButton }
let clearAll = buttons.first { $0.title == "모두 지우기" }
check(clearAll != nil, "recent history has a clear-all action")
let rows = descendants(content).compactMap { $0 as? RecentRow }
check(rows.map(\.url) == [newest, removed, oldest], "start screen presents native recent order")
if CommandLine.arguments.contains("--preview") {
    // Publication fixtures live only under this run's temporary directory.
    // Their visible path is 문서/HanX 예제, with no personal file names.
    NSApp.applicationIconImage = NSImage(contentsOfFile: "Resources/AppIcon.icns")
    let examples = fixtureDirectory.appendingPathComponent("문서/HanX 예제")
    try FileManager.default.createDirectory(at: examples, withIntermediateDirectories: true)
    let exampleNames = ["월간 매출.xlsx", "작업 보고서.docx", "프로젝트 발표.pptx"]
    let exampleURLs = try exampleNames.enumerated().map { index, name -> URL in
        let url = examples.appendingPathComponent(name)
        try Data().write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_793_318_400 - Double(index) * 3_600)], ofItemAtPath: url.path)
        return url
    }
    let previewPreferencesName = preferencesName + ".preview"
    let previewPreferences = UserDefaults(suiteName: previewPreferencesName)!
    defer { previewPreferences.removePersistentDomain(forName: previewPreferencesName) }
    let previewRegistration = DefaultAppRegistration(preferences: previewPreferences) { _ in }
    let preview = StartWindowController(recentDocuments: MemoryRecentDocuments(exampleURLs), defaultRegistration: previewRegistration)
    let previewContent = preview.window!.contentView!
    previewContent.layoutSubtreeIfNeeded()
    descendants(previewContent).compactMap { $0 as? RecentRow }.first?.hovering = true
    settleAnimation()
    if let image = previewContent.bitmapImageRepForCachingDisplay(in: previewContent.bounds) {
        previewContent.cacheDisplay(in: previewContent.bounds, to: image)
        if let data = image.representation(using: .png, properties: [:]) {
            try data.write(to: URL(fileURLWithPath: "build/start-window-preview.png"))
        }
    }
    preview.close()
}
if let removeMiddle = rows.dropFirst().first.flatMap({ descendants($0).compactMap { $0 as? NSButton }.first }) {
    removeMiddle.performClick(nil)
    check(uiHistory.recentDocumentURLs == [newest, oldest], "row action removes only that recent entry")
    check(descendants(content).compactMap { $0 as? RecentRow }.map(\.url) == [newest, oldest], "row action immediately refreshes visible history")
}
clearAll?.performClick(nil)
check(uiHistory.recentDocumentURLs.isEmpty, "clear all empties native recent history")
check(descendants(content).compactMap { $0 as? RecentRow }.isEmpty, "clear all replaces visible rows with an empty state")
check(clearAll?.isHidden == true, "clear all is hidden for empty history")
check(FileManager.default.fileExists(atPath: removed.path), "clear all leaves underlying files intact")
let cappedStart = StartWindowController(recentDocuments: longHistory, defaultRegistration: registration)
let cappedContent = cappedStart.window!.contentView!
check(descendants(cappedContent).compactMap { $0 as? RecentRow }.count == 5, "recent view keeps the existing five-row limit")
descendants(cappedContent).compactMap { $0 as? NSButton }.first { $0.title == "모두 지우기" }?.performClick(nil)
check(longHistory.recentDocumentURLs.isEmpty, "clear all also removes history beyond visible rows")
cappedStart.close()
if let button = buttons.first(where: { $0.title == "기본 앱으로 설정" }) {
    check(button.isBordered && button.bezelStyle == .smallSquare, "default application action is a rectangular bordered button")
    check(!button.isHidden, "setup is visible before a successful registration")
    button.performClick(nil)
    check(!button.isEnabled, "setup ignores repeated requests while registration is pending")
    completeRegistration?([])
    check(button.isHidden, "successful registration immediately hides setup")
    check(registration.isComplete, "successful registration is persisted")
    let laterRegistration = DefaultAppRegistration(preferences: preferences) { _ in }
    let laterStart = StartWindowController(recentDocuments: MemoryRecentDocuments([]), defaultRegistration: laterRegistration)
    check(descendants(laterStart.window!.contentView!).compactMap { $0 as? NSButton }.first { $0.title == "기본 앱으로 설정" }?.isHidden == true, "setup remains hidden in a new start screen")
    laterStart.close()
}
check(!descendants(content).compactMap { $0 as? NSTextField }.contains { $0.stringValue.hasPrefix("hwp, hwpx, docx") }, "footer omits extension listings")
start.close()
preferences.removePersistentDomain(forName: preferencesName)
let failedRegistration = DefaultAppRegistration(preferences: preferences) { $0(["org.openxmlformats.wordprocessingml.document"]) }
var failure: [String] = []
failedRegistration.register { failure = $0 }
check(!failedRegistration.isComplete && failure == ["org.openxmlformats.wordprocessingml.document"], "a failed registration preserves retry state and reports the failing type")
let retryStart = StartWindowController(recentDocuments: MemoryRecentDocuments([]), defaultRegistration: failedRegistration)
check(descendants(retryStart.window!.contentView!).compactMap { $0 as? NSButton }.first { $0.title == "기본 앱으로 설정" }?.isHidden == false, "failed registration keeps setup visible")
retryStart.close()
if failures > 0 { exit(1) }
print("PASS: start window history, removal actions, hover, clear all, and persisted default registration")
