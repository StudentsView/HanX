import AppKit

/// AppKit owns persistence and security-scoped bookmarks for the recent menu.
protocol RecentDocumentStore: AnyObject {
    var recentDocumentURLs: [URL] { get }
    func clearRecentDocuments(_ sender: Any?)
    func noteNewRecentDocumentURL(_ url: URL)
}
extension NSDocumentController: RecentDocumentStore {}

enum RecentDocumentHistory {
    static func remove(_ url: URL, from store: RecentDocumentStore) {
        let current = store.recentDocumentURLs
        guard current.contains(url) else { return }
        let retained = current.filter { $0 != url }
        // Keep existing URL objects and their grants alive while AppKit replaces
        // its history. Re-noting oldest first preserves newest-first ordering.
        let accessing = retained.filter { $0.startAccessingSecurityScopedResource() }
        defer { accessing.forEach { $0.stopAccessingSecurityScopedResource() } }
        store.clearRecentDocuments(nil)
        retained.reversed().forEach { store.noteNewRecentDocumentURL($0) }
    }
}

/// A successful request is remembered so the start screen offers setup once.
final class DefaultAppRegistration: NSObject {
    static let shared = DefaultAppRegistration()
    static let didComplete = Notification.Name("HanWordDefaultAppRegistrationDidComplete")
    private static let completedKey = "HanWordDefaultAppRegistrationCompleted"
    private let preferences: UserDefaults
    private let handler: (@escaping ([String]) -> Void) -> Void

    init(preferences: UserDefaults = .standard,
         handler: @escaping (@escaping ([String]) -> Void) -> Void = HWDocumentController.makeDefaultHandler) {
        self.preferences = preferences
        self.handler = handler
    }

    var isComplete: Bool { preferences.bool(forKey: Self.completedKey) }

    func register(completion: @escaping ([String]) -> Void) {
        handler { [self] failed in
            if failed.isEmpty {
                preferences.set(true, forKey: Self.completedKey)
                NotificationCenter.default.post(name: Self.didComplete, object: self)
            }
            completion(failed)
        }
    }
}
