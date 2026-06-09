import Foundation

/// Fetches inbox state from the local Go backend. Shared by the app's
/// `InboxMonitor` and the desktop widget so both decode the API identically.
enum InboxBackend {
    /// Pull the most recent conversations plus a one-line preview for each, and
    /// fold them into a snapshot. Throws on transport/HTTP failure so callers can
    /// fall back to a cached snapshot.
    static func fetchInbox(
        baseURL: URL = InboxShared.backendBaseURL,
        recentLimit: Int = 8,
        session: URLSession = .shared
    ) async throws -> InboxSnapshot {
        let convos = try await fetchConversations(baseURL: baseURL, session: session)
        let recent = Array(convos.prefix(recentLimit))
        var rows: [InboxItem] = []
        for c in recent {
            let preview = await fetchPreview(baseURL: baseURL, conversation: c, session: session)
            rows.append(InboxItem(
                id: c.conversationID,
                name: c.displayName,
                preview: preview,
                timestamp: c.lastMessageTS,
                unread: c.unreadCount > 0,
                platform: c.sourcePlatform ?? ""
            ))
        }
        let unread = convos.filter { $0.unreadCount > 0 }.count
        return InboxSnapshot(
            items: rows,
            totalUnread: unread,
            updatedAt: Int64(Date().timeIntervalSince1970 * 1000)
        )
    }

    private static func fetchConversations(baseURL: URL, session: URLSession) async throws -> [Conversation] {
        var comps = URLComponents(url: baseURL.appendingPathComponent("api/conversations"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "limit", value: "30")]
        let (data, response) = try await session.data(from: comps.url!)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode([Conversation].self, from: data)
    }

    private static func fetchPreview(baseURL: URL, conversation c: Conversation, session: URLSession) async -> String {
        let path = "api/conversations/\(c.conversationID)/messages"
        guard var comps = URLComponents(url: baseURL.appendingPathComponent(path),
                                        resolvingAgainstBaseURL: false) else { return "" }
        comps.queryItems = [URLQueryItem(name: "limit", value: "1")]
        guard let url = comps.url else { return "" }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return "" }
            let msgs = try JSONDecoder().decode([Message].self, from: data)
            guard let m = msgs.first else { return "" }
            let body = m.body.replacingOccurrences(of: "\n", with: " ")
            if m.isFromMe { return "You: \(body)" }
            if c.isGroup, let sender = m.senderName, !sender.isEmpty {
                return "\(sender): \(body)"
            }
            return body
        } catch {
            return ""
        }
    }
}

/// Mirrors the Go `db.Conversation` JSON shape from `/api/conversations`.
struct Conversation: Decodable {
    let conversationID: String
    let name: String
    let isGroup: Bool
    let lastMessageTS: Int64
    let unreadCount: Int
    let sourcePlatform: String?
    let unifiedName: String?

    var displayName: String {
        if let u = unifiedName, !u.isEmpty { return u }
        return name.isEmpty ? "Unknown" : name
    }

    enum CodingKeys: String, CodingKey {
        case conversationID = "ConversationID"
        case name = "Name"
        case isGroup = "IsGroup"
        case lastMessageTS = "LastMessageTS"
        case unreadCount = "UnreadCount"
        case sourcePlatform = "source_platform"
        case unifiedName = "unified_name"
    }
}

/// Mirrors the Go `db.Message` JSON shape from `/api/conversations/{id}/messages`.
struct Message: Decodable {
    let body: String
    let senderName: String?
    let isFromMe: Bool

    enum CodingKeys: String, CodingKey {
        case body = "Body"
        case senderName = "SenderName"
        case isFromMe = "IsFromMe"
    }
}
