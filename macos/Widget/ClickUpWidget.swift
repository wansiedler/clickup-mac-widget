import AppIntents
import SwiftUI
import WidgetKit

// MARK: Timeline

struct ClickUpEntry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot?
    let error: String?
}

struct Provider: TimelineProvider {
    private static let refresh: TimeInterval = 15 * 60

    func placeholder(in _: Context) -> ClickUpEntry {
        ClickUpEntry(date: .now, snapshot: .sample, error: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (ClickUpEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        Task { completion(await load()) }
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<ClickUpEntry>) -> Void) {
        Task {
            let entry = await load()
            completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(Self.refresh))))
        }
    }

    private func load() async -> ClickUpEntry {
        do {
            let snapshot = try await ClickUpAPI.fromKeychain().snapshot(teamOverride: TokenStore.read(.teamId))
            return ClickUpEntry(date: .now, snapshot: snapshot, error: nil)
        } catch {
            return ClickUpEntry(date: .now, snapshot: nil, error: error.localizedDescription)
        }
    }
}

// MARK: Interactive stop button (macOS 14+)

struct StopTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop ClickUp timer"

    @Parameter(title: "Workspace ID")
    var teamId: String

    init() {}

    init(teamId: String) {
        self.teamId = teamId
    }

    func perform() async throws -> some IntentResult {
        try await ClickUpAPI.fromKeychain().stopTimer(teamId: teamId)
        return .result()
    }
}

// MARK: Views

struct ClickUpWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ClickUpEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                switch family {
                case .systemSmall: SmallView(s: snapshot)
                case .systemMedium: ListView(s: snapshot, limit: 4)
                default: ListView(s: snapshot, limit: 11)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Label("ClickUp", systemImage: "exclamationmark.triangle").font(.caption.bold())
                    Text(entry.error ?? "No data").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

private struct SmallView: View {
    let s: Snapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("ClickUp", systemImage: "checklist").font(.caption).foregroundStyle(.secondary)
            Counter(value: s.overdue.count, label: "overdue", tint: .red)
            Counter(value: s.today.count, label: "today", tint: .orange)
            Spacer(minLength: 0)
            if let timer = s.timer {
                TimerRow(entry: timer, teamId: s.teamId, compact: true)
            } else {
                Text("\(s.upcoming.count) upcoming").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(ClickUpAPI.appURL)
    }
}

private struct Counter: View {
    let value: Int
    let label: String
    let tint: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("\(value)").font(.title2.bold().monospacedDigit()).foregroundStyle(value > 0 ? tint : .secondary)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct ListView: View {
    struct Item: Identifiable {
        let row: Snapshot.Row
        let tint: Color
        var id: String { row.id }
    }

    let s: Snapshot
    let limit: Int

    private var items: [Item] {
        let all = s.overdue.map { Item(row: $0, tint: .red) }
            + s.today.map { Item(row: $0, tint: .orange) }
            + s.upcoming.map { Item(row: $0, tint: .secondary) }
        return Array(all.prefix(s.timer == nil ? limit : limit - 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("ClickUp", systemImage: "checklist").font(.caption.bold())
                Spacer()
                if s.overdue.count > 0 {
                    Text("\(s.overdue.count) overdue").font(.caption2.bold()).foregroundStyle(.red)
                }
                Text("\(s.today.count) today").font(.caption2).foregroundStyle(.orange)
            }
            if let timer = s.timer {
                TimerRow(entry: timer, teamId: s.teamId, compact: false)
            }
            if items.isEmpty {
                Spacer()
                Text("Nothing due").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
            ForEach(items) { TaskRow(row: $0.row, tint: $0.tint) }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct TaskRow: View {
    let row: Snapshot.Row
    let tint: Color

    var body: some View {
        let task = row.task
        Link(destination: URL(string: task.url) ?? ClickUpAPI.appURL) {
            HStack(spacing: 5) {
                if row.depth > 0 {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, CGFloat(row.depth - 1) * 10)
                }
                Text(task.ticket)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                if let parent = row.parentName {
                    Text("\(parent) ›").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Text(task.name).font(.caption).lineLimit(1).layoutPriority(1)
                Spacer(minLength: 4)
                StatusPill(status: task.status)
                if let due = task.due {
                    Text(due, format: .dateTime.month(.abbreviated).day())
                        .font(.caption2).foregroundStyle(tint).fixedSize()
                }
            }
        }
    }
}

/// Status name on its ClickUp colour. The text keeps it readable when macOS
/// renders the widget monochrome.
private struct StatusPill: View {
    let status: CUTask.Status

    var body: some View {
        let color = Color(hex: status.color) ?? .gray
        Text(status.status.uppercased())
            .font(.system(size: 8, weight: .bold))
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.22), in: Capsule())
            .fixedSize()
    }
}

private struct TimerRow: View {
    let entry: CUTimeEntry
    let teamId: String
    let compact: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "timer").foregroundStyle(.green)
            if let start = entry.startDate {
                Text(start, style: .timer).font(.caption.monospacedDigit()).fixedSize()
            }
            if !compact {
                Link(destination: entry.taskURL) {
                    Text(entry.task?.name ?? entry.note ?? "No task").font(.caption).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Button(intent: StopTimerIntent(teamId: teamId)) {
                Image(systemName: "stop.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
        }
    }
}

extension Color {
    init?(hex: String?) {
        guard var h = hex?.trimmingCharacters(in: .whitespaces), !h.isEmpty else { return nil }
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }
}

// MARK: Widget

struct ClickUpTasksWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ClickUpTasks", provider: Provider()) { entry in
            ClickUpWidgetView(entry: entry)
        }
        .configurationDisplayName("ClickUp tasks")
        .description("Overdue, due today, upcoming, and the running timer.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct ClickUpWidgetBundle: WidgetBundle {
    var body: some Widget {
        ClickUpTasksWidget()
    }
}

#Preview(as: .systemMedium) {
    ClickUpTasksWidget()
} timeline: {
    ClickUpEntry(date: .now, snapshot: .sample, error: nil)
}
