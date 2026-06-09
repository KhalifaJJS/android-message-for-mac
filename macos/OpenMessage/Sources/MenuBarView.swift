import SwiftUI

/// The menu bar icon. Shows a steady bubble when everything is read, and a
/// blinking badge plus the unread count when new messages have arrived.
struct MenuBarLabel: View {
    @ObservedObject var inbox: InboxMonitor

    var body: some View {
        if inbox.totalUnread > 0 {
            // Blink between the badged and plain bubble to draw the eye.
            Image(systemName: inbox.blinkOn ? "message.badge.fill" : "message.fill")
            Text("\(inbox.totalUnread)")
        } else {
            Image(systemName: "message")
        }
    }
}

struct MenuBarView: View {
    @ObservedObject var backend: BackendManager
    @ObservedObject var inbox: InboxMonitor
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Status
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.callout)
                if inbox.totalUnread > 0 {
                    Spacer(minLength: 8)
                    Text("\(inbox.totalUnread) unread")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Recent conversations with a one-line preview. Clicking a row opens
            // the inbox and marks that conversation read (clearing its unread dot).
            if !inbox.items.isEmpty {
                Divider()
                ForEach(inbox.items.prefix(6)) { item in
                    Button {
                        openInbox()
                        if item.unread { inbox.markRead(item.id) }
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(item.unread ? Color.accentColor : Color.clear)
                                .frame(width: 6, height: 6)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.name)
                                    .font(.callout.weight(item.unread ? .semibold : .regular))
                                    .lineLimit(1)
                                Text(item.preview.isEmpty ? " " : item.preview)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }

            // Per-platform alert: a paired bridge silently stopped syncing.
            // Surfaced here because the backend process stays "running" when
            // one platform dies, so the green dot alone would hide the problem
            // (this is exactly how Google Messages rotted for months unnoticed).
            if let alert = backend.platformAlert {
                Divider()
                Button {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                    NotificationCenter.default.post(name: .openPlatformsRequested, object: nil)
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(alert)
                            .font(.callout)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .help("Open Platforms to re-pair")
            }

            Divider()

            Button("Open Messages") {
                openInbox()
            }
            .keyboardShortcut("o")

            SettingsLink {
                Text("Settings…")
            }

            Divider()

            Button("Quit OpenMessage") {
                backend.stop()
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }

    private func openInbox() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }

    private var statusColor: Color {
        // A platform alert outranks the green "running" dot — a paired bridge
        // that stopped syncing is a yellow-warning condition even though the
        // backend process is healthy.
        if backend.platformAlert != nil && backend.state == .running {
            return .yellow
        }
        switch backend.state {
        case .running: return .green
        case .starting: return .yellow
        case .error: return .red
        default: return .gray
        }
    }

    private var statusText: String {
        if backend.platformAlert != nil && backend.state == .running {
            return "Attention needed"
        }
        switch backend.state {
        case .running: return "Connected"
        case .starting: return "Starting..."
        case .needsPairing: return "Needs pairing"
        case .error: return "Error"
        case .stopped: return "Stopped"
        }
    }
}
