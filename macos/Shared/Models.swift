import Foundation

struct CUTask: Codable, Hashable, Identifiable {
    struct Status: Codable, Hashable {
        let status: String
        let color: String?
    }

    struct Priority: Codable, Hashable {
        let priority: String
        let color: String?
    }

    struct ListRef: Codable, Hashable {
        let id: String
        let name: String?
    }

    let id: String
    let name: String
    let url: String
    let status: Status
    let priority: Priority?
    /// Milliseconds since epoch, as a string — ClickUp's wire format.
    let dueDate: String?
    let list: ListRef?

    enum CodingKeys: String, CodingKey {
        case id, name, url, status, priority, list
        case dueDate = "due_date"
    }

    var due: Date? {
        dueDate.flatMap(Double.init).map { Date(timeIntervalSince1970: $0 / 1000) }
    }

    var priorityRank: Int {
        switch priority?.priority {
        case "urgent": 1
        case "high": 2
        case "normal": 3
        case "low": 4
        default: 5
        }
    }

    /// Earliest due first, undated last, then by priority.
    static func urgencyOrder(_ a: CUTask, _ b: CUTask) -> Bool {
        switch (a.due, b.due) {
        case let (x?, y?) where x != y: return x < y
        case (.some, nil): return true
        case (nil, .some): return false
        default: return a.priorityRank < b.priorityRank
        }
    }
}

struct CUTimeEntry: Codable, Hashable {
    struct TaskRef: Codable, Hashable {
        let id: String
        let name: String
    }

    let id: String
    /// Milliseconds since epoch, as a string.
    let start: String
    let note: String?
    let task: TaskRef?

    enum CodingKeys: String, CodingKey {
        case id, start, task
        case note = "description"
    }

    var startDate: Date? {
        Double(start).map { Date(timeIntervalSince1970: $0 / 1000) }
    }

    var taskURL: URL {
        URL(string: "https://app.clickup.com/t/\(task?.id ?? "")") ?? ClickUpAPI.appURL
    }
}

struct Workspace: Codable, Hashable, Identifiable {
    let id: String
    let name: String
}

/// Everything a widget render needs, bucketed once at fetch time.
struct Snapshot: Codable, Hashable {
    var fetchedAt: Date
    var teamId: String
    var overdue: [CUTask] = []
    var today: [CUTask] = []
    var upcoming: [CUTask] = []
    var noDate: [CUTask] = []
    var timer: CUTimeEntry?

    var dueNowCount: Int { overdue.count + today.count }

    static func make(tasks: [CUTask], timer: CUTimeEntry?, teamId: String,
                     now: Date = .now, calendar: Calendar = .current) -> Snapshot {
        var s = Snapshot(fetchedAt: now, teamId: teamId, timer: timer)
        let startOfToday = calendar.startOfDay(for: now)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now
        for task in tasks.sorted(by: CUTask.urgencyOrder) {
            guard let due = task.due else {
                s.noDate.append(task)
                continue
            }
            if due < startOfToday {
                s.overdue.append(task)
            } else if due < startOfTomorrow {
                s.today.append(task)
            } else {
                s.upcoming.append(task)
            }
        }
        return s
    }

    static let sample: Snapshot = {
        func t(_ id: String, _ name: String, _ days: Double?, _ color: String) -> CUTask {
            CUTask(id: id, name: name, url: "https://app.clickup.com/t/\(id)",
                   status: .init(status: "in progress", color: color), priority: nil,
                   dueDate: days.map { String(Int((Date.now.timeIntervalSince1970 + $0 * 86_400) * 1000)) },
                   list: .init(id: "l", name: "Sprint"))
        }
        return Snapshot.make(
            tasks: [
                t("1", "Fix CI cache rot", -2, "#e5484d"),
                t("2", "Review rollout PR", 0, "#f76b15"),
                t("3", "Write runbook", 0, "#3e63dd"),
                t("4", "Plan next sprint", 3, "#8e8c99"),
            ],
            timer: CUTimeEntry(id: "e", start: String(Int((Date.now.timeIntervalSince1970 - 2_700) * 1000)),
                               note: nil, task: .init(id: "2", name: "Review rollout PR")),
            teamId: "0")
    }()
}
