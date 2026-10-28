import Foundation

/// Sessions the user marked as done. A mark only covers activity up to when it was made, so
/// resuming a done session and chatting on brings it back.
struct DoneMarks {
    private(set) var markedAt: [String: Date]

    func isDone(_ session: Session) -> Bool {
        guard let at = markedAt[session.id] else {
            return false
        }
        return at >= session.lastAt
    }

    mutating func toggle(_ session: Session, now: Date = .now) {
        if isDone(session) {
            markedAt[session.id] = nil
        } else {
            markedAt[session.id] = now
        }
    }
}

extension DoneMarks {
    private static let defaultsKey = "doneSessions"

    static func load(from defaults: UserDefaults = .standard) -> DoneMarks {
        let stored = defaults.dictionary(forKey: defaultsKey) as? [String: Double] ?? [:]
        return DoneMarks(markedAt: stored.mapValues(Date.init(timeIntervalSince1970:)))
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(markedAt.mapValues(\.timeIntervalSince1970), forKey: Self.defaultsKey)
    }
}
