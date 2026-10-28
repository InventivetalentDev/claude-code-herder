import Foundation

/// Casual dates like "October 25 to a few min ago".
enum HumanTime {
    static func span(from start: Date, to end: Date, now: Date = .now) -> String {
        let from = describe(start, now: now)
        let to = describe(end, now: now)
        return from == to ? from : "\(from) to \(to)"
    }

    static func describe(_ date: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        let seconds = now.timeIntervalSince(date)
        let time = date.formatted(date: .omitted, time: .shortened)
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
            break
        }
        if calendar.isDate(date, inSameDayAs: now) {
            return "today at \(time)"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
            calendar.isDate(date, inSameDayAs: yesterday)
        {
            return "yesterday at \(time)"
        }
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(.dateTime.month(.wide).day())
        }
        return date.formatted(.dateTime.month(.wide).day().year())
    }
}
