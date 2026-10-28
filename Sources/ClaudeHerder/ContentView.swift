import AppKit
import SwiftUI

struct ContentView: View {
    @State private var store = SessionStore()
    @State private var query = ""
    @State private var searchMatches: Set<String>?
    @State private var isSearching = false
    @State private var period = Period()
    @State private var sortKey = SortKey.lastMessage
    @State private var sortDescending = true
    @State private var pageLimit = ContentView.pageSize
    @State private var errorMessage: String?
    @State private var showingPeriod = false

    private static let pageSize = 40

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.border)
            content
        }
        .background(Theme.background)
        .preferredColorScheme(.light)
        .task { await store.reload() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await store.reload() }
        }
        .task(id: query) { await runSearch() }
        .onChange(of: filterKey) { pageLimit = Self.pageSize }
        .alert("Something went wrong", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            Spark(size: 22)
            Text("Claude Herder")
                .font(Theme.serif(26))
                .foregroundStyle(Theme.ink)
                .fixedSize()

            Spacer(minLength: 24)

            searchField.frame(maxWidth: 360)
            periodButton
            sortMenu

            Button {
                Task { await store.reload() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.secondary)
            .keyboardShortcut("r")
            .help("Reload sessions (⌘R)")
            .disabled(store.isLoading)
        }
        .padding(.horizontal, 28)
        .padding(.top, 34)  // clears the traffic lights over the hidden title bar
        .padding(.bottom, 16)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.tertiary)
            TextField("Search transcripts…", text: $query)
                .textFieldStyle(.plain)
                .foregroundStyle(Theme.ink)
            if isSearching {
                ProgressView().controlSize(.small)
            } else if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.system(size: 14))
        .outlinedControl()
    }

    private var periodButton: some View {
        Button {
            showingPeriod.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                Text(period.label).fixedSize()
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
            }
            .font(.system(size: 13))
            .foregroundStyle(Theme.ink)
            .outlinedControl()
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingPeriod, arrowEdge: .bottom) {
            PeriodPicker(period: $period)
        }
    }

    private var sortMenu: some View {
        HStack(spacing: 0) {
            Menu {
                Picker("Sort by", selection: $sortKey) {
                    ForEach(SortKey.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Text(sortKey.rawValue).font(.system(size: 13)).fixedSize()
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button {
                sortDescending.toggle()
            } label: {
                Image(systemName: sortDescending ? "arrow.down" : "arrow.up")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
            .help(sortDescending ? "Newest / largest first" : "Oldest / smallest first")
        }
        .foregroundStyle(Theme.ink)
        .outlinedControl()
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        let sessions = visibleSessions
        if !store.hasLoaded {
            centered { ProgressView("Reading transcripts…") }
        } else if sessions.isEmpty {
            centered {
                Text(query.isEmpty ? "No sessions in this period." : "No sessions match “\(query)”.")
                    .font(Theme.serif(18))
                    .foregroundStyle(Theme.secondary)
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    summaryLine(count: sessions.count)
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 400), spacing: 18)], spacing: 18
                    ) {
                        ForEach(sessions.prefix(pageLimit)) { session in
                            SessionCard(session: session) { open(session) }
                        }
                    }
                    if sessions.count > pageLimit {
                        // Infinite scroll: reaching the end loads the next page. The id makes
                        // onAppear fire again if the sentinel is still on screen afterwards.
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .id(pageLimit)
                            .onAppear { pageLimit += Self.pageSize }
                    }
                }
                .padding(28)
            }
        }
    }

    private func summaryLine(count: Int) -> some View {
        HStack(spacing: 8) {
            Text("\(count) sessions")
            if let cost = totalCost {
                Text("·")
                Text(cost.formatted(.currency(code: "USD")))
            }
            if !store.failures.isEmpty {
                Text("·")
                Button("\(store.failures.count) transcripts failed to load") {
                    errorMessage = store.failures.map { "\($0.path)\n\($0.message)" }
                        .joined(separator: "\n\n")
                }
                .buttonStyle(.link)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(Theme.tertiary)
    }

    private func centered(@ViewBuilder _ inner: () -> some View) -> some View {
        inner().frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Logic

    private var visibleSessions: [Session] {
        store.sessions
            .filter { period.contains($0) && (searchMatches?.contains($0.id) ?? true) }
            .sorted { sortDescending ? sortKey.ascending($1, $0) : sortKey.ascending($0, $1) }
    }

    private var totalCost: Double? {
        let costs = visibleSessions.compactMap(\.costUSD)
        return costs.isEmpty ? nil : costs.reduce(0, +)
    }

    /// Anything that changes which sessions show resets the scroll page.
    private var filterKey: [AnyHashable] {
        [query, period.label, sortKey, sortDescending]
    }

    private func runSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            searchMatches = nil
            return
        }
        // Debounce typing; a newer query cancels this task.
        do {
            try await Task.sleep(for: .milliseconds(250))
        } catch {
            return
        }
        isSearching = true
        defer { isSearching = false }
        do {
            let ids = try await TranscriptSearch.sessionIDs(
                matching: trimmed, in: SessionIndexer.projectsRoot)
            guard !Task.isCancelled else {
                return
            }
            searchMatches = ids
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func open(_ session: Session) {
        guard let cwd = session.cwd else {
            return
        }
        Task {
            do {
                try await Ghostty.resume(sessionID: session.id, in: cwd)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct PeriodPicker: View {
    @Binding var period: Period

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(PeriodPreset.allCases.filter { $0 != .custom }) { preset in
                    Button {
                        period.preset = preset
                    } label: {
                        HStack {
                            Text(preset.rawValue)
                            Spacer()
                            if period.preset == preset {
                                Image(systemName: "checkmark").foregroundStyle(Theme.clay)
                            }
                        }
                        .frame(width: 130)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                }
            }
            .font(.system(size: 13))
            Divider()
            // Picking any date switches to a custom range.
            calendar("From", selection: $period.customStart)
            calendar("To", selection: $period.customEnd)
        }
        .padding(16)
    }

    private func calendar(_ title: String, selection: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondary)
            DatePicker(
                title,
                selection: Binding(
                    get: { selection.wrappedValue },
                    set: {
                        selection.wrappedValue = $0
                        period.preset = .custom
                    }),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
        }
    }
}
