import SwiftUI

struct SessionCard: View {
    let session: Session
    let onOpen: () -> Void

    private static let dateStyle = Date.FormatStyle()
        .month(.abbreviated).day().hour().minute()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(session.projectName.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)

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
                    Text("\(session.firstAt.formatted(Self.dateStyle)) → \(session.lastAt.formatted(Self.dateStyle))")
                    Text(stats)
                }
                .font(.system(size: 12))
                .foregroundStyle(Theme.tertiary)
                .monospacedDigit()

                Spacer()

                Button(action: onOpen) {
                    HStack(spacing: 4) {
                        Text("Open")
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    }
                }
                .buttonStyle(PillButtonStyle())
                .disabled(session.cwd == nil)
                .help(session.cwd.map { "claude --resume in \($0)" } ?? "Unknown folder")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
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

    private var stats: String {
        let messages = "\(session.messageCount) messages"
        guard let cost = session.costUSD else {
            return messages + " · cost unknown"
        }
        return messages + " · " + cost.formatted(.currency(code: "USD"))
    }
}
