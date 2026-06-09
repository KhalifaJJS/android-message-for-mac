import SwiftUI
import WidgetKit

// MARK: - Timeline

struct InboxEntry: TimelineEntry {
    let date: Date
    let snapshot: InboxSnapshot
    let reachable: Bool
}

struct InboxProvider: TimelineProvider {
    func placeholder(in context: Context) -> InboxEntry {
        InboxEntry(date: Date(), snapshot: Self.sample, reachable: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (InboxEntry) -> Void) {
        if context.isPreview {
            completion(InboxEntry(date: Date(), snapshot: Self.sample, reachable: true))
            return
        }
        Task { completion(await loadEntry()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<InboxEntry>) -> Void) {
        Task {
            let entry = await loadEntry()
            // The app pushes WidgetCenter reloads on new messages; this periodic
            // refresh is just a safety net so the widget self-heals if a push is
            // ever missed.
            let next = Calendar.current.date(byAdding: .minute, value: 10, to: Date()) ?? Date().addingTimeInterval(600)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    /// Live data from the local backend, falling back to the last snapshot the
    /// app wrote to the shared container when the backend isn't reachable.
    private func loadEntry() async -> InboxEntry {
        if let live = try? await InboxBackend.fetchInbox() {
            return InboxEntry(date: Date(), snapshot: live, reachable: true)
        }
        if let cached = readCachedSnapshot() {
            return InboxEntry(date: Date(), snapshot: cached, reachable: false)
        }
        return InboxEntry(date: Date(), snapshot: .empty, reachable: false)
    }

    private func readCachedSnapshot() -> InboxSnapshot? {
        guard let url = InboxShared.snapshotURL(),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(InboxSnapshot.self, from: data)
    }

    static let sample = InboxSnapshot(items: [
        InboxItem(id: "1", name: "엄마", preview: "저녁 먹었니? 일찍 들어와", timestamp: 0, unread: true, platform: "sms"),
        InboxItem(id: "2", name: "김철수", preview: "내일 회의 3시로 변경됐어요", timestamp: 0, unread: true, platform: "sms"),
        InboxItem(id: "3", name: "이영희", preview: "사진 잘 받았어 고마워!", timestamp: 0, unread: false, platform: "sms"),
    ], totalUnread: 2, updatedAt: 0)
}

// MARK: - View

struct MessagesWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: InboxEntry

    private var rowCount: Int { family == .systemLarge ? 6 : 3 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            let items = Array(entry.snapshot.items.prefix(rowCount))
            if items.isEmpty {
                Spacer()
                Text(entry.reachable ? "No messages yet" : "Open OpenMessage to connect")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                ForEach(items) { item in
                    row(item)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .containerBackground(for: .widget) { Color(.windowBackgroundColor) }
        .widgetURL(URL(string: "\(InboxShared.urlScheme)://open"))
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "message.fill")
                .foregroundStyle(.green)
            Text("Messages")
                .font(.headline)
            Spacer()
            if entry.snapshot.totalUnread > 0 {
                Text("\(entry.snapshot.totalUnread)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.red))
            }
        }
    }

    private func row(_ item: InboxItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(item.unread ? Color.accentColor : Color.clear)
                .frame(width: 7, height: 7)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.subheadline.weight(item.unread ? .semibold : .regular))
                    .lineLimit(1)
                Text(item.preview.isEmpty ? " " : item.preview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Widget

struct MessagesWidget: Widget {
    let kind = "MessagesWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: InboxProvider()) { entry in
            MessagesWidgetView(entry: entry)
        }
        .configurationDisplayName("Messages")
        .description("Recent texts and unread count from Google Messages.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

@main
struct MessagesWidgetBundle: WidgetBundle {
    var body: some Widget {
        MessagesWidget()
    }
}
