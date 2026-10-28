import AppKit
import SwiftUI

struct SessionCard: View {
    let session: Session
    let folder: FolderState
    let isFavorite: Bool
    let onOpen: () -> Void
    let onToggleFavorite: () -> Void

    @State private var isHovered = false
    @State private var justCopied = false

    private static let exactDateStyle = Date.FormatStyle()
        .weekday(.abbreviated).month(.abbreviated).day().hour().minute()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                switch folder {
                case .liveCow:
                    Text("🐮").help("Its cow checkout still exists")
                case .missing:
                    Text("❌").help("Its folder is gone; copy the ID to continue it elsewhere")
                case .present:
                    EmptyView()
                }
                Text(session.projectName.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                Spacer()
                favoriteButton
            }
            .frame(height: 16)

            Text(session.title)
                .font(Theme.serif(20, weight: .medium))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            summary
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    // Re-render each minute so "a few min ago" doesn't go stale.
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        Text(HumanTime.span(from: session.firstAt, to: session.lastAt, now: context.date))
                    }
                    .help(exactSpan)
                    Text(stats)
                }
                .font(.system(size: 12))
                .foregroundStyle(Theme.tertiary)

                Spacer()

                HStack(spacing: 8) {
                    Button(justCopied ? "Copied" : "Copy ID", action: copyID)
                        .buttonStyle(PillButtonStyle(prominent: false))
                        .help(session.id)
                    // Resuming needs the folder, so a deleted one gets no Open.
                    if folder != .missing, let cwd = session.cwd {
                        Button(action: onOpen) {
                            HStack(spacing: 4) {
                                Text("Open")
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                        }
                        .buttonStyle(PillButtonStyle())
                        .help("claude --resume in \(cwd)")
                    }
                }
                .opacity(isHovered ? 1 : 0)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isHovered ? Theme.borderStrong : Theme.border)
        )
        .shadow(color: Theme.ink.opacity(isHovered ? 0.08 : 0), radius: 12, y: 4)
        .offset(y: isHovered ? -2 : 0)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
    }

    /// Always shown once starred; otherwise only on hover, like Open.
    private var favoriteButton: some View {
        Button(action: onToggleFavorite) {
            Text(isFavorite ? "★" : "☆")
                .font(.system(size: 16))
                .foregroundStyle(isFavorite ? Theme.clay : Theme.tertiary)
        }
        .buttonStyle(.plain)
        .help(isFavorite ? "Remove from favorites" : "Add to favorites")
        .opacity(isFavorite || isHovered ? 1 : 0)
    }

    private func copyID() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(session.id, forType: .string)
        justCopied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            justCopied = false
        }
    }

    @ViewBuilder
    private var summary: some View {
        if let recap = session.recap {
            Text(recap)
                .font(.system(size: 14))
                .foregroundStyle(Theme.secondary)
                .lineSpacing(3)
                .lineLimit(5)
        } else if let prompt = session.firstPrompt {
            // No recap yet: the opening prompt is the next best description.
            Text("“\(prompt)”")
                .font(.system(size: 14).italic())
                .foregroundStyle(Theme.tertiary)
                .lineSpacing(3)
                .lineLimit(4)
        }
    }

    private var exactSpan: String {
        "\(session.firstAt.formatted(Self.exactDateStyle)) → \(session.lastAt.formatted(Self.exactDateStyle))"
    }

    private var stats: String {
        let messages = "\(session.messageCount) messages"
        guard let cost = session.costUSD else {
            return messages + " · cost unknown"
        }
        return messages + " · " + cost.formatted(.currency(code: "USD"))
    }
}
