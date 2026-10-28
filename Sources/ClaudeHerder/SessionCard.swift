import AppKit
import SwiftUI

struct SessionCard: View {
    let session: Session
    let folder: FolderState
    let isDone: Bool
    let onOpen: () -> Void
    let onToggleDone: () -> Void

    @State private var isHovered = false
    @State private var justCopied = false

    private static let exactDateStyle = Date.FormatStyle()
        .weekday(.abbreviated).month(.abbreviated).day().hour().minute()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if folder == .liveCow {
                    Text("🐮").help("Its cow checkout still exists")
                }
                Text(session.projectName.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(folder == .missing ? Theme.deletedRed : Theme.secondary)
                    .lineLimit(1)
                    .help(folder == .missing ? "Folder deleted; copy the ID to continue it elsewhere" : "")
            }
            .frame(height: 16)
            .padding(.trailing, 24)  // room for the star overlay

            Text(InlineMarkdown.render(session.title))
                .font(Theme.serif(20, weight: .medium))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            summary
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

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
            .opacity(isHovered ? 0 : 1)  // the session ID takes this spot on hover
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay { if isHovered { hoverActions } }
        // Above the dimming, so marking done still works while hovered.
        .overlay(alignment: .topTrailing) {
            doneButton.frame(height: 16).padding(20)
        }
        // Clicking anywhere opens; the buttons above handle their own clicks.
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture {
            if canOpen {
                onOpen()
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isHovered ? Theme.borderStrong : Theme.border)
        )
        .shadow(color: Theme.ink.opacity(isHovered ? 0.08 : 0), radius: 12, y: 4)
        .offset(y: isHovered ? -2 : 0)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
    }

    /// Resuming needs the folder, so a deleted one can't be opened.
    private var canOpen: Bool {
        folder != .missing && session.cwd != nil
    }

    /// Dims the card, shows Open in the middle and the session ID bottom-left.
    private var hoverActions: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 14).fill(Theme.dim)
            Group {
                if canOpen {
                    Button(action: onOpen) {
                        HStack(spacing: 4) {
                            Text("Open")
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                        }
                    }
                    .buttonStyle(PillButtonStyle())
                    .help("claude --resume in \(session.cwd ?? "")")
                } else {
                    Text("Folder deleted")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.deletedRed)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Button(action: copyID) {
                HStack(spacing: 6) {
                    Text(session.id)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: justCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                        .frame(width: 14)
                }
                .foregroundStyle(justCopied ? Theme.clay : Theme.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Copy session ID")
            .padding(20)
        }
        .transition(.opacity)
    }

    /// Always shown on done cards; otherwise only on hover, like Open.
    private var doneButton: some View {
        Button(action: onToggleDone) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "checkmark.circle")
                .font(.system(size: 17))
                .foregroundStyle(isDone ? Theme.clay : Theme.tertiary)
        }
        .buttonStyle(.plain)
        .help(isDone ? "Mark as not done" : "Mark as done")
        .opacity(isDone || isHovered ? 1 : 0)
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
            Text(InlineMarkdown.render(recap))
                .font(.system(size: 14))
                .foregroundStyle(Theme.secondary)
                .lineSpacing(3)
                .lineLimit(5)
        } else if let prompt = session.firstPrompt {
            // No recap yet: the opening prompt is the next best description.
            Text(InlineMarkdown.render("“\(prompt)”"))
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
