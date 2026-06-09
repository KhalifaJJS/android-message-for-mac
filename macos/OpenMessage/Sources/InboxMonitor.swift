import Combine
import Foundation
import os
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Watches the local backend for conversation activity and exposes the state the
/// menu bar and desktop widget need: a blinking unread indicator, the unread
/// count, and a short list of recent conversations with previews.
///
/// Data sources: the backend's SSE stream (`/api/events`) for near-instant
/// wake-ups, plus a periodic poll of `/api/conversations` as a fallback. On every
/// change it writes a snapshot to the shared App Group container and asks
/// WidgetKit to reload, so the desktop widget stays in sync.
@MainActor
final class InboxMonitor: ObservableObject {
    @Published private(set) var items: [InboxItem] = []
    @Published private(set) var totalUnread: Int = 0
    /// Toggles on a timer while there are unread messages, driving the menu bar
    /// dot's blink. False (steady) when everything is read.
    @Published private(set) var blinkOn: Bool = false

    private let baseURL: URL
    private let logger = Logger(subsystem: "com.openmessage.app", category: "Inbox")
    private let session = URLSession(configuration: .ephemeral)

    private var started = false
    private var eventTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var blinkTimer: Timer?
    private var refreshing = false
    private var pendingRefresh = false

    /// How many recent conversations to surface (menu bar + widget).
    private let recentLimit = 8

    init(baseURL: URL = InboxShared.backendBaseURL) {
        self.baseURL = baseURL
    }

    func start() {
        guard !started else { return }
        started = true
        pollTask = Task { [weak self] in await self?.pollLoop() }
        eventTask = Task { [weak self] in await self?.eventLoop() }
    }

    func stop() {
        started = false
        eventTask?.cancel(); eventTask = nil
        pollTask?.cancel(); pollTask = nil
        blinkTimer?.invalidate(); blinkTimer = nil
    }

    /// Tell the backend a conversation has been seen, then refresh.
    func markRead(_ conversationID: String) {
        Task { [weak self] in
            guard let self else { return }
            var req = URLRequest(url: self.baseURL.appendingPathComponent("api/mark-read"))
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["conversation_id": conversationID])
            _ = try? await self.session.data(for: req)
            await self.refresh()
        }
    }

    // MARK: - Loops

    /// Fallback poll every few seconds in case the SSE stream is unavailable.
    private func pollLoop() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: .seconds(8))
        }
    }

    /// Subscribe to the backend SSE stream and refresh on any relevant event.
    /// Reconnects with a short backoff if the stream drops or isn't up yet.
    private func eventLoop() async {
        let url = baseURL.appendingPathComponent("api/events")
        while !Task.isCancelled {
            do {
                var req = URLRequest(url: url)
                req.timeoutInterval = .infinity
                req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                let (bytes, response) = try await session.bytes(for: req)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
                for try await line in bytes.lines {
                    if Task.isCancelled { return }
                    guard line.hasPrefix("data:") else { continue }
                    let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                    if shouldRefresh(forEventPayload: payload) {
                        await refresh()
                    }
                }
            } catch {
                if Task.isCancelled { return }
                logger.debug("SSE reconnect: \(error.localizedDescription, privacy: .public)")
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// We refresh on conversation/message/status events but ignore heartbeats
    /// and typing churn so we don't hammer the backend.
    private func shouldRefresh(forEventPayload payload: String) -> Bool {
        guard let data = payload.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else {
            return false
        }
        switch type {
        case "conversations", "messages", "status": return true
        default: return false
        }
    }

    // MARK: - Refresh

    private func refresh() async {
        // Coalesce overlapping refreshes (a burst of SSE events shouldn't fan
        // out into many concurrent fetches).
        if refreshing { pendingRefresh = true; return }
        refreshing = true
        defer { refreshing = false }

        do {
            let snapshot = try await InboxBackend.fetchInbox(
                baseURL: baseURL, recentLimit: recentLimit, session: session)
            apply(items: snapshot.items, totalUnread: snapshot.totalUnread)
        } catch {
            logger.debug("refresh failed: \(error.localizedDescription, privacy: .public)")
        }

        if pendingRefresh {
            pendingRefresh = false
            await refresh()
        }
    }

    private func apply(items: [InboxItem], totalUnread: Int) {
        if items != self.items { self.items = items }
        if totalUnread != self.totalUnread {
            self.totalUnread = totalUnread
            updateBlink()
        }
        writeSnapshot(items: items, totalUnread: totalUnread)
        reloadWidgets()
        logger.info("inbox state: unread=\(totalUnread, privacy: .public) items=\(items.count, privacy: .public) first=\(items.first?.name ?? "-", privacy: .public)")
    }

    // MARK: - Blink

    private func updateBlink() {
        if totalUnread > 0 {
            guard blinkTimer == nil else { return }
            blinkOn = true
            let timer = Timer(timeInterval: 0.6, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.blinkOn.toggle() }
            }
            RunLoop.main.add(timer, forMode: .common)
            blinkTimer = timer
        } else {
            blinkTimer?.invalidate(); blinkTimer = nil
            blinkOn = false
        }
    }

    // MARK: - Widget bridge

    private func writeSnapshot(items: [InboxItem], totalUnread: Int) {
        let snapshot = InboxSnapshot(
            items: items,
            totalUnread: totalUnread,
            updatedAt: Int64(Date().timeIntervalSince1970 * 1000)
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        // Primary: the App Group container the widget reads. Fallback: the app's
        // data dir, which keeps a diagnostics/cache copy when the build isn't
        // signed with the App Group entitlement.
        if let url = InboxShared.snapshotURL() {
            try? data.write(to: url, options: .atomic)
        }
        let fallback = (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Application Support/GoogleRCS/\(InboxShared.snapshotFile)")
        try? data.write(to: URL(fileURLWithPath: fallback), options: .atomic)
    }

    private func reloadWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}

