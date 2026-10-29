import SwiftUI
import UniformTypeIdentifiers

/// Folder → profile and first message → a new iTerm2 tab.
struct NewSessionWizard: View {
    let recentFolders: [URL]
    let profiles: [Profile]
    let onStart: (_ folder: URL, _ profile: Profile, _ prompt: String) -> Void

    @Environment(\.dismiss) private var dismiss
    /// The last profile picked, by ID.
    @AppStorage("newSessionProfile") private var profileID = ""
    @State private var step = Step.folder
    @State private var folder: URL?
    /// Picked with "Choose another folder…"; listed above the recent ones.
    @State private var pickedFolder: URL?
    @State private var choosingFolder = false
    @State private var prompt = ""
    @FocusState private var focused: Bool

    enum Step {
        case folder, message
    }

    init(recentFolders: [URL], profiles: [Profile], onStart: @escaping (URL, Profile, String) -> Void) {
        self.recentFolders = recentFolders
        self.profiles = profiles
        self.onStart = onStart
        _folder = State(initialValue: recentFolders.first)
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
        case .folder: "Where should it run?"
        case .message: "What should \(profile?.isClaude == false ? "Codex" : "Claude") do?"
        }
    }

    /// Falls back to the first profile when the remembered one is gone from the config.
    private var profile: Profile? {
        profiles.first { $0.id == profileID } ?? profiles.first
    }

    private var folders: [URL] {
        (pickedFolder.map { [$0] } ?? []) + recentFolders.filter { $0 != pickedFolder }
    }

    @ViewBuilder
    private var page: some View {
        switch step {
        case .folder:
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(folders, id: \.self) { url in
                        option(url)
                    }
                    Button("Choose another folder…") { choosingFolder = true }
                        .buttonStyle(PillButtonStyle(prominent: false))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result {
                    pickedFolder = url
                    folder = url
                }
            }
        case .message:
            VStack(alignment: .leading, spacing: 12) {
                Picker("Profile", selection: Binding(get: { profile?.id ?? "" }, set: { profileID = $0 })) {
                    ForEach(profiles) { Text($0.label).tag($0.id) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                TextEditor(text: $prompt)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.ink)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
                    .focused($focused)
                    .onAppear { focused = true }
                Text("In \(folder.map(Self.abbreviated) ?? "")")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private func option(_ url: URL) -> some View {
        let selected = folder == url
        return Button {
            folder = url
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(url.lastPathComponent).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ink)
                    Text(Self.abbreviated(url))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
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
            if step == .folder {
                Button("Cancel") { dismiss() }
                    .buttonStyle(PillButtonStyle(prominent: false))
                    .keyboardShortcut(.cancelAction)
            } else {
                Button("Back") { step = .folder }
                    .buttonStyle(PillButtonStyle(prominent: false))
                    .keyboardShortcut(.cancelAction)
            }
            Spacer()
            if step == .message {
                // ⌘↩ because plain Return types a newline in the message.
                Button("Start Session", action: start)
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canStart)
                    .opacity(canStart ? 1 : 0.4)
                    .help("⌘↩")
            } else {
                Button("Next") { step = .message }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(folder == nil)
                    .opacity(folder == nil ? 0.4 : 1)
            }
        }
    }

    private var trimmedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canStart: Bool {
        !trimmedPrompt.isEmpty && profile != nil
    }

    private func start() {
        guard let folder, let profile else {
            return
        }
        onStart(folder, profile, trimmedPrompt)
        dismiss()
    }

    /// `~/Projects/x` rather than `/Users/me/Projects/x`.
    private static func abbreviated(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.hasPrefix(home + "/") ? "~" + url.path.dropFirst(home.count) : url.path
    }
}
