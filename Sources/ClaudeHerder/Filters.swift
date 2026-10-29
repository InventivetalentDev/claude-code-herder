import Foundation

enum PeriodPreset: String, CaseIterable, Identifiable {
    case today = "Today"
    case lastWeek = "Last 7 days"
    case lastMonth = "Last 30 days"
    case allTime = "All time"
    case custom = "Custom"

    var id: Self { self }
}

struct Period: Equatable {
    var preset: PeriodPreset = .lastMonth
    var customStart = Calendar.current.date(byAdding: .day, value: -30, to: .now)!
    var customEnd = Date.now

    /// Nil means unbounded.
    func interval(now: Date = .now) -> DateInterval? {
        let calendar = Calendar.current
        switch preset {
        case .today:
            return DateInterval(start: calendar.startOfDay(for: now), end: now)
        case .lastWeek:
            return DateInterval(start: now.addingTimeInterval(-7 * 86_400), end: now)
        case .lastMonth:
            return DateInterval(start: now.addingTimeInterval(-30 * 86_400), end: now)
        case .allTime:
            return nil
        case .custom:
            let start = calendar.startOfDay(for: min(customStart, customEnd))
            let lastDay = calendar.startOfDay(for: max(customStart, customEnd))
            let end = calendar.date(byAdding: .day, value: 1, to: lastDay)!
            return DateInterval(start: start, end: end)
        }
    }

    var label: String {
        guard preset == .custom else {
            return preset.rawValue
        }
        let style = Date.FormatStyle().month(.abbreviated).day()
        return "\(customStart.formatted(style)) – \(customEnd.formatted(style))"
    }

    /// A session counts if any part of it falls in the period.
    func contains(_ session: Session) -> Bool {
        guard let interval = interval() else {
            return true
        }
        return session.lastAt >= interval.start && session.firstAt <= interval.end
    }
}

enum SortKey: String, CaseIterable, Identifiable {
    case lastMessage = "Last message"
    case firstMessage = "First message"
    case messageCount = "Message count"
    case cost = "Cost"

    var id: Self { self }

    func ascending(_ a: Session, _ b: Session) -> Bool {
        switch self {
        case .lastMessage:
            return a.lastAt < b.lastAt
        case .firstMessage:
            return a.firstAt < b.firstAt
        case .messageCount:
            return (a.messageCount ?? 0) < (b.messageCount ?? 0)
        case .cost:
            return (a.costUSD ?? 0) < (b.costUSD ?? 0)
        }
    }
}
