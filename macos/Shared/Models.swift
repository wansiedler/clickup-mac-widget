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
    /// Parent task id; nil for a top-level task.
    let parent: String?
    let customId: String?

    enum CodingKeys: String, CodingKey {
        case id, name, url, status, priority, list, parent
        case dueDate = "due_date"
        case customId = "custom_id"
    }

    /// What ClickUp shows as the ticket number.
    var ticket: String { customId ?? "#\(id)" }

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
    /// A task placed in its bucket's tree. `parentName` is set only when the
    /// parent is not shown right above it (another bucket, or not assigned to me).
    struct Row: Codable, Hashable, Identifiable {
        let task: CUTask
        let depth: Int
        let parentName: String?
        var id: String { task.id }
    }

    var fetchedAt: Date
    var teamId: String
    var overdue: [Row] = []
    var today: [Row] = []
    var upcoming: [Row] = []
    var noDate: [Row] = []
    var timer: CUTimeEntry?

    var dueNowCount: Int { overdue.count + today.count }

    static func make(tasks: [CUTask], timer: CUTimeEntry?, teamId: String,
                     parentNames: [String: String] = [:],
                     now: Date = .now, calendar: Calendar = .current) -> Snapshot {
        let names = Dictionary(tasks.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
            .merging(parentNames, uniquingKeysWith: { a, _ in a })
        let startOfToday = calendar.startOfDay(for: now)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now
        var overdue: [CUTask] = [], today: [CUTask] = [], upcoming: [CUTask] = [], noDate: [CUTask] = []
        for task in tasks.sorted(by: CUTask.urgencyOrder) {
            guard let due = task.due else {
                noDate.append(task)
                continue
            }
            if due < startOfToday {
                overdue.append(task)
            } else if due < startOfTomorrow {
                today.append(task)
            } else {
                upcoming.append(task)
            }
        }
        return Snapshot(fetchedAt: now, teamId: teamId,
                        overdue: tree(overdue, names: names), today: tree(today, names: names),
                        upcoming: tree(upcoming, names: names), noDate: tree(noDate, names: names),
                        timer: timer)
    }

    /// Children follow their parent when both sit in the same bucket; the rest
    /// stay at depth 0 with a parent breadcrumb. Input order is kept per level.
    static func tree(_ tasks: [CUTask], names: [String: String]) -> [Row] {
        let ids = Set(tasks.map(\.id))
        var children: [String: [CUTask]] = [:]
        var roots: [CUTask] = []
        for task in tasks {
            if let parent = task.parent, ids.contains(parent) {
                children[parent, default: []].append(task)
            } else {
                roots.append(task)
            }
        }
        var rows: [Row] = []
        func walk(_ task: CUTask, _ depth: Int) {
            rows.append(Row(task: task, depth: depth,
                            parentName: depth == 0 ? task.parent.flatMap { names[$0] } : nil))
            guard depth < 4 else { return }
            for child in children[task.id] ?? [] { walk(child, depth + 1) }
        }
        roots.forEach { walk($0, 0) }
        return rows
    }

    static let sample: Snapshot = {
        func t(_ id: String, _ name: String, _ days: Double?, _ status: String, _ color: String,
               parent: String? = nil) -> CUTask {
            CUTask(id: id, name: name, url: "https://app.clickup.com/t/\(id)",
                   status: .init(status: status, color: color), priority: nil,
                   dueDate: days.map { String(Int((Date.now.timeIntervalSince1970 + $0 * 86_400) * 1000)) },
                   list: .init(id: "l", name: "Sprint"), parent: parent, customId: nil)
        }
        return Snapshot.make(
            tasks: [
                t("86c1", "Fix CI cache rot", -2, "blocked", "#e5484d"),
                t("86c2", "Review rollout PR", 0, "in review", "#f76b15"),
                t("86c3", "Write runbook", 0, "in progress", "#3e63dd", parent: "86c2"),
                t("86c4", "Plan next sprint", 3, "to do", "#8e8c99"),
            ],
            timer: CUTimeEntry(id: "e", start: String(Int((Date.now.timeIntervalSince1970 - 2_700) * 1000)),
                               note: nil, task: .init(id: "2", name: "Review rollout PR")),
            teamId: "0")
    }()
}
