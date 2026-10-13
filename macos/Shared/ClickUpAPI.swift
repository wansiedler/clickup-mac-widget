import Foundation

enum ClickUpError: LocalizedError {
    case noToken
    case noWorkspace
    case http(Int, String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .noToken: "No API token. Open the ClickUp Widget app and paste one."
        case .noWorkspace: "This token sees no workspace."
        case let .http(code, body): code == 401 ? "Token rejected (401)." : "HTTP \(code): \(body)"
        case let .decoding(what): "Unexpected response: \(what)"
        }
    }
}

/// Minimal ClickUp API v2 client. Auth is a personal token (`pk_…`) in the
/// Authorization header, no OAuth.
struct ClickUpAPI {
    static let base = URL(string: "https://api.clickup.com/api/v2/")!
    static let appURL = URL(string: "https://app.clickup.com/")!

    let token: String
    var session: URLSession = .shared

    static func fromKeychain() throws -> ClickUpAPI {
        guard let token = TokenStore.read(.token) else { throw ClickUpError.noToken }
        return ClickUpAPI(token: token)
    }

    // MARK: Endpoints

    func userId() async throws -> Int {
        try await get("user", as: UserResponse.self).user.id
    }

    func workspaces() async throws -> [Workspace] {
        try await get("team", as: TeamsResponse.self).teams
    }

    func myOpenTasks(teamId: String, userId: Int, maxPages: Int = 5) async throws -> [CUTask] {
        var all: [CUTask] = []
        for page in 0..<maxPages {
            let resp = try await get("team/\(teamId)/task", query: [
                URLQueryItem(name: "assignees[]", value: String(userId)),
                URLQueryItem(name: "subtasks", value: "true"),
                URLQueryItem(name: "include_closed", value: "false"),
                URLQueryItem(name: "order_by", value: "due_date"),
                URLQueryItem(name: "page", value: String(page)),
            ], as: TasksResponse.self)
            all += resp.tasks
            if resp.lastPage ?? (resp.tasks.count < 100) { break }
        }
        return all
    }

    func currentTimer(teamId: String) async throws -> CUTimeEntry? {
        try await get("team/\(teamId)/time_entries/current", as: TimerResponse.self).data
    }

    func stopTimer(teamId: String) async throws {
        _ = try await send("team/\(teamId)/time_entries/stop", method: "POST")
    }

    func snapshot(teamOverride: String?, now: Date = .now) async throws -> Snapshot {
        async let uid = userId()
        let teamId: String
        if let teamOverride, !teamOverride.isEmpty {
            teamId = teamOverride
        } else {
            guard let first = try await workspaces().first else { throw ClickUpError.noWorkspace }
            teamId = first.id
        }
        // An async let initializer cannot capture another async let, so resolve the user first.
        let userId = try await uid
        async let tasks = myOpenTasks(teamId: teamId, userId: userId)
        // A failing timer endpoint must not blank the task list.
        let timer: CUTimeEntry? = (try? await currentTimer(teamId: teamId)) ?? nil
        let all = try await tasks
        let missing = Set(all.compactMap(\.parent)).subtracting(all.map(\.id))
        let parents = await taskNames(Array(missing.prefix(15)))
        return Snapshot.make(tasks: all, timer: timer, teamId: teamId, parentNames: parents, now: now)
    }

    /// Names of parent tasks that are not assigned to me; failures are skipped.
    func taskNames(_ ids: [String]) async -> [String: String] {
        await withTaskGroup(of: (String, String?).self) { group in
            for id in ids {
                group.addTask { (id, try? await get("task/\(id)", as: TaskName.self).name) }
            }
            var out: [String: String] = [:]
            for await (id, name) in group {
                if let name { out[id] = name }
            }
            return out
        }
    }

    // MARK: Transport

    private func send(_ path: String, method: String = "GET", query: [URLQueryItem] = []) async throws -> Data {
        var comps = URLComponents(url: Self.base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.timeoutInterval = 20
        req.setValue(token, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw ClickUpError.http(code, String(decoding: data.prefix(200), as: UTF8.self))
        }
        return data
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [], as _: T.Type) async throws -> T {
        let data = try await send(path, query: query)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ClickUpError.decoding("\(path): \(error)")
        }
    }
}

private struct UserResponse: Decodable {
    struct User: Decodable { let id: Int }
    let user: User
}

private struct TaskName: Decodable {
    let name: String
}

private struct TeamsResponse: Decodable {
    let teams: [Workspace]
}

private struct TasksResponse: Decodable {
    let tasks: [CUTask]
    let lastPage: Bool?

    enum CodingKeys: String, CodingKey {
        case tasks
        case lastPage = "last_page"
    }
}

private struct TimerResponse: Decodable {
    let data: CUTimeEntry?

    enum CodingKeys: String, CodingKey { case data }

    init(from decoder: Decoder) throws {
        // No running timer comes back as `null` or `{}` depending on the account.
        let c = try decoder.container(keyedBy: CodingKeys.self)
        data = try? c.decodeIfPresent(CUTimeEntry.self, forKey: .data)
    }
}
