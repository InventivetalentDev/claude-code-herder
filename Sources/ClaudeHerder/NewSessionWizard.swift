import SwiftUI

/// Workspace → (branch name, for a new cow) → first message → a new Ghostty tab.
struct NewSessionWizard: View {
    let cows: [URL]
    let onStart: (Workspace, _ name: String, _ prompt: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var step = Step.workspace
    @State private var workspace = Workspace.newCow
    @State private var name = ""
    @State private var prompt = ""
    @FocusState private var focused: Bool

    enum Step {
        case workspace, branch, message
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(Theme.serif(24, weight: .medium))
                .foregroundStyle(Theme.ink)
            page.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            buttons
        }
        .padding(28)
        .frame(width: 520, height: 440)
        .background(Theme.background)
        .preferredColorScheme(.light)
    }

    private var title: String {
        switch step {
        case .workspace: "Where should it run?"
        case .branch: "Name the branch"
        case .message: "What should Claude do?"
        }
    }

    @ViewBuilder
    private var page: some View {
        switch step {
        case .workspace:
            ScrollView {
                VStack(spacing: 8) {
                    option(.newCow, "New cow", detail: "A fresh copy-on-write checkout")
                    option(.repo, NewSession.repo.lastPathComponent, detail: "The repo itself")
                    ForEach(cows, id: \.self) { cow in
                        option(.cow(cow), "🐮 \(cow.lastPathComponent)", detail: "Existing cow")
                    }
                }
            }
        case .branch:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 0) {
                    Text(NewSession.branchPrefix).foregroundStyle(Theme.tertiary)
                    TextField("my-feature", text: $name)
                        .textFieldStyle(.plain)
                        .foregroundStyle(Theme.ink)
                        .focused($focused)
                }
                .font(.system(size: 15, design: .monospaced))
                .outlinedControl()
                Text(nameProblem ?? "Cloned into cows/\(NewSession.folderName(for: name))")
                    .font(.system(size: 12))
                    .foregroundStyle(nameProblem == nil ? Theme.tertiary : Theme.deletedRed)
                    .opacity(name.isEmpty ? 0 : 1)
            }
            .onAppear { focused = true }
        case .message:
            TextEditor(text: $prompt)
                .font(.system(size: 14))
                .foregroundStyle(Theme.ink)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
                .focused($focused)
                .onAppear { focused = true }
        }
    }

    private func option(_ choice: Workspace, _ label: String, detail: String) -> some View {
        let selected = workspace == choice
        return Button {
            workspace = choice
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ink)
                    Text(detail).font(.system(size: 12)).foregroundStyle(Theme.tertiary)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Theme.clay : Theme.borderStrong)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selected ? Theme.clay : Theme.border, lineWidth: selected ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var buttons: some View {
        HStack {
            if step == .workspace {
                Button("Cancel") { dismiss() }
                    .buttonStyle(PillButtonStyle(prominent: false))
                    .keyboardShortcut(.cancelAction)
            } else {
                Button("Back", action: goBack)
                    .buttonStyle(PillButtonStyle(prominent: false))
                    .keyboardShortcut(.cancelAction)
            }
            Spacer()
            if step == .message {
                // ⌘↩ because plain Return types a newline in the message.
                Button("Start Session", action: start)
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(trimmedPrompt.isEmpty)
                    .opacity(trimmedPrompt.isEmpty ? 0.4 : 1)
                    .help("⌘↩")
            } else {
                Button("Next", action: goNext)
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canGoNext)
                    .opacity(canGoNext ? 1 : 0.4)
            }
        }
    }

    private var nameProblem: String? {
        NewSession.problem(withName: name, existing: cows)
    }

    private var trimmedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canGoNext: Bool {
        step != .branch || (!name.isEmpty && nameProblem == nil)
    }

    private func goNext() {
        switch step {
        case .workspace: step = workspace == .newCow ? .branch : .message
        case .branch: step = .message
        case .message: break
        }
    }

    private func goBack() {
        switch step {
        case .workspace: break
        case .branch: step = .workspace
        case .message: step = workspace == .newCow ? .branch : .workspace
        }
    }

    private func start() {
        onStart(workspace, name, trimmedPrompt)
        dismiss()
    }
}
