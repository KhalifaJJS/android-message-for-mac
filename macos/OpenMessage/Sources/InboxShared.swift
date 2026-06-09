import Foundation

/// Shared data model + constants used by both the main app (which produces the
/// snapshot) and the desktop widget (which reads it). Kept dependency-free so
/// the same source file can be compiled into the WidgetKit extension target.
enum InboxShared {
    /// App Group used to share the inbox snapshot with the widget extension.
    /// Both targets must carry this group in their entitlements.
    static let appGroup = "group.com.openmessage.app"

    /// Custom URL scheme the widget opens to bring the app to the front.
    static let urlScheme = "openmessage"

    /// Filename of the JSON snapshot inside the App Group container.
    static let snapshotFile = "inbox-snapshot.json"

    /// Backend base URL (the Go server the app spawns).
    static let backendBaseURL = URL(string: "http://127.0.0.1:7007")!

    /// Location of the shared snapshot, or nil if the App Group is unavailable
    /// (e.g. the build isn't signed with the group entitlement yet).
    static func snapshotURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(snapshotFile)
    }
}

/// One conversation row shown in the menu bar and the widget.
struct InboxItem: Codable, Identifiable, Equatable {
    let id: String        // conversation id
    let name: String      // contact / group name
    let preview: String   // last message text, one line
    let timestamp: Int64  // last message time (ms)
    let unread: Bool      // has unseen messages
    let platform: String  // sms, whatsapp, signal, ...
}

/// The snapshot the app writes and the widget reads.
struct InboxSnapshot: Codable, Equatable {
    var items: [InboxItem]
    var totalUnread: Int
    var updatedAt: Int64  // ms

    static let empty = InboxSnapshot(items: [], totalUnread: 0, updatedAt: 0)
}
