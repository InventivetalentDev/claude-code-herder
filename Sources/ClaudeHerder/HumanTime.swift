import Foundation

/// Casual dates like "October 25 to a few min ago".
enum HumanTime {
    static func span(from start: Date, to end: Date, now: Date = .now) -> String {
        // Same recent day: name it once, e.g. "today 14:51 to 15:05".
        if relative(end, now: now) == nil, Calendar.current.isDate(start, inSameDayAs: end),
            let day = dayName(start, now: now)
        {
            return "\(day) \(clock(start)) to \(clock(end))"
        }
        let from = describe(start, now: now)
        let to = describe(end, now: now)
        return from == to ? from : "\(from) to \(to)"
    }

    static func describe(_ date: Date, now: Date = .now) -> String {
        if let relative = relative(date, now: now) {
            return relative
        }
        if let day = dayName(date, now: now) {
            return "\(day) at \(clock(date))"
        }
        if Calendar.current.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(.dateTime.month(.wide).day())
        }
        return date.formatted(.dateTime.month(.wide).day().year())
    }

    /// "a few min ago" style, for the last few hours only.
    private static func relative(_ date: Date, now: Date) -> String? {
        let seconds = now.timeIntervalSince(date)
        switch seconds {
        case ..<60:
            return "just now"
        case ..<(5 * 60):
            return "a few min ago"
        case ..<3600:
            return "\(Int(seconds / 60)) min ago"
        case ..<(3 * 3600):
            let hours = Int(seconds / 3600)
            return hours == 1 ? "an hour ago" : "\(hours) hours ago"
        default:
            return nil
        }
    }

    private static func dayName(_ date: Date, now: Date) -> String? {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) {
            return "today"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
            calendar.isDate(date, inSameDayAs: yesterday)
        {
            return "yesterday"
        }
        return nil
    }

    private static func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
