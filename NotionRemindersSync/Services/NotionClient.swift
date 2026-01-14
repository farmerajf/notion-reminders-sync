import Foundation

/// HTTP client for interacting with the Notion API
@Observable
final class NotionClient {
    static let shared = NotionClient()

    private let baseURL = "https://api.notion.com/v1"
    private let apiVersion = "2022-06-28"
    private let keychain = KeychainService.shared

    private var apiKey: String? {
        keychain.getNotionAPIKey()
    }

    @ObservationIgnored
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    @ObservationIgnored
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private init() {}

    // MARK: - Connection Test

    func testConnection() async throws -> Bool {
        guard apiKey != nil else {
            throw NotionError.noAPIKey
        }

        let _: UserResponse = try await request(
            method: "GET",
            path: "/users/me"
        )
        return true
    }

    // MARK: - Database Operations

    func listDatabases() async throws -> [NotionDatabase] {
        // Notion Search API expects filter with "value" and "property" keys
        let body: [String: Any] = [
            "filter": [
                "value": "database",
                "property": "object"
            ]
        ]

        let response: SearchResponse = try await request(
            method: "POST",
            path: "/search",
            bodyDict: body
        )

        print("[NotionClient] Search returned \(response.results.count) results")

        let databases = response.results.compactMap { result -> NotionDatabase? in
            guard case .database(let db) = result else { return nil }
            print("[NotionClient] Found database: \(db.title) (id: \(db.id))")
            return db
        }

        print("[NotionClient] Total databases found: \(databases.count)")
        return databases
    }

    func getDatabase(id: String) async throws -> NotionDatabase {
        let response: DatabaseResponse = try await request(
            method: "GET",
            path: "/databases/\(id)"
        )
        return response.toNotionDatabase()
    }

    // MARK: - Page Operations

    func queryDatabase(
        databaseId: String,
        filter: QueryFilter? = nil,
        startCursor: String? = nil
    ) async throws -> QueryResponse {
        var body: [String: Any] = [:]
        if let filter = filter {
            body["filter"] = filter.toDictionary()
        }
        if let cursor = startCursor {
            body["start_cursor"] = cursor
        }

        return try await request(
            method: "POST",
            path: "/databases/\(databaseId)/query",
            bodyDict: body.isEmpty ? nil : body
        )
    }

    func getAllPages(in databaseId: String) async throws -> [NotionPage] {
        var allPages: [NotionPage] = []
        var cursor: String? = nil

        repeat {
            let response = try await queryDatabase(databaseId: databaseId, startCursor: cursor)
            allPages.append(contentsOf: response.results)
            cursor = response.hasMore ? response.nextCursor : nil
        } while cursor != nil

        return allPages
    }

    func createPage(
        in databaseId: String,
        properties: [String: NotionPropertyValue]
    ) async throws -> NotionPage {
        let body = CreatePageRequest(
            parent: Parent(databaseId: databaseId),
            properties: properties
        )

        return try await request(
            method: "POST",
            path: "/pages",
            body: body
        )
    }

    func updatePage(
        pageId: String,
        properties: [String: NotionPropertyValue]
    ) async throws -> NotionPage {
        let body = UpdatePageRequest(properties: properties)

        return try await request(
            method: "PATCH",
            path: "/pages/\(pageId)",
            body: body
        )
    }

    func archivePage(pageId: String) async throws -> NotionPage {
        let body: [String: Any] = ["archived": true]

        return try await request(
            method: "PATCH",
            path: "/pages/\(pageId)",
            bodyDict: body
        )
    }

    func getPage(pageId: String) async throws -> NotionPage {
        return try await request(
            method: "GET",
            path: "/pages/\(pageId)"
        )
    }

    // MARK: - Private Request Methods

    private func request<T: Decodable>(
        method: String,
        path: String,
        body: (some Encodable)? = nil as Empty?
    ) async throws -> T {
        let bodyData = try body.map { try encoder.encode($0) }
        return try await performRequest(method: method, path: path, bodyData: bodyData)
    }

    private func request<T: Decodable>(
        method: String,
        path: String,
        bodyDict: [String: Any]?
    ) async throws -> T {
        let bodyData = try bodyDict.map { try JSONSerialization.data(withJSONObject: $0) }
        return try await performRequest(method: method, path: path, bodyData: bodyData)
    }

    private func performRequest<T: Decodable>(
        method: String,
        path: String,
        bodyData: Data?
    ) async throws -> T {
        guard let apiKey = apiKey else {
            throw NotionError.noAPIKey
        }

        guard let url = URL(string: baseURL + path) else {
            throw NotionError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(apiVersion, forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NotionError.invalidResponse
        }

        if httpResponse.statusCode == 429 {
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
            throw NotionError.rateLimited(retryAfter: retryAfter)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorResponse = try? decoder.decode(NotionErrorResponse.self, from: data) {
                throw NotionError.apiError(code: errorResponse.code, message: errorResponse.message)
            }
            throw NotionError.httpError(statusCode: httpResponse.statusCode)
        }

        return try decoder.decode(T.self, from: data)
    }

    // MARK: - Errors

    enum NotionError: LocalizedError {
        case noAPIKey
        case invalidURL
        case invalidResponse
        case httpError(statusCode: Int)
        case apiError(code: String, message: String)
        case rateLimited(retryAfter: String?)
        case decodingError(Error)

        var errorDescription: String? {
            switch self {
            case .noAPIKey:
                return "No Notion API key configured"
            case .invalidURL:
                return "Invalid API URL"
            case .invalidResponse:
                return "Invalid response from Notion"
            case .httpError(let statusCode):
                return "HTTP error: \(statusCode)"
            case .apiError(let code, let message):
                return "Notion API error (\(code)): \(message)"
            case .rateLimited(let retryAfter):
                if let retry = retryAfter {
                    return "Rate limited. Retry after \(retry) seconds"
                }
                return "Rate limited. Please try again later"
            case .decodingError(let error):
                return "Failed to decode response: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - API Request/Response Types

private struct Empty: Encodable {}

private struct UserResponse: Decodable {
    let id: String
    let name: String?
    let type: String
}

private struct SearchResponse: Decodable {
    let results: [SearchResult]
    let hasMore: Bool
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case results
        case hasMore = "has_more"
        case nextCursor = "next_cursor"
    }
}

private enum SearchResult: Decodable {
    case database(NotionDatabase)
    case page(NotionPage)
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let object = try container.decode(String.self, forKey: .object)

        switch object {
        case "database":
            let response = try DatabaseResponse(from: decoder)
            self = .database(response.toNotionDatabase())
        case "page":
            let page = try NotionPage(from: decoder)
            self = .page(page)
        default:
            self = .unknown
        }
    }

    enum CodingKeys: String, CodingKey {
        case object
    }
}

private struct DatabaseResponse: Decodable {
    let id: String
    let title: [TitleText]
    let properties: [String: PropertyDefinition]
    let url: String?
    let lastEditedTime: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, properties, url
        case lastEditedTime = "last_edited_time"
    }

    struct TitleText: Decodable {
        let plainText: String

        enum CodingKeys: String, CodingKey {
            case plainText = "plain_text"
        }
    }

    struct PropertyDefinition: Decodable {
        let id: String
        let name: String
        let type: String
        let select: SelectConfig?
        let multiSelect: SelectConfig?
        let status: StatusConfig?

        enum CodingKeys: String, CodingKey {
            case id, name, type, select, status
            case multiSelect = "multi_select"
        }

        struct SelectConfig: Decodable {
            let options: [OptionDef]?
        }

        struct StatusConfig: Decodable {
            let options: [OptionDef]?
            let groups: [GroupDef]?
        }

        struct OptionDef: Decodable {
            let id: String
            let name: String
            let color: String?
        }

        struct GroupDef: Decodable {
            let id: String
            let name: String
            let color: String?
            let optionIds: [String]

            enum CodingKeys: String, CodingKey {
                case id, name, color
                case optionIds = "option_ids"
            }
        }
    }

    func toNotionDatabase() -> NotionDatabase {
        let props = properties.map { (name, def) in
            var options: [NotionSelectOption]? = nil
            var statusGroups: [NotionStatusGroup]? = nil
            if let selectOptions = def.select?.options ?? def.multiSelect?.options ?? def.status?.options {
                options = selectOptions.map { NotionSelectOption(id: $0.id, name: $0.name, color: $0.color) }
            }
            if let groups = def.status?.groups {
                statusGroups = groups.map {
                    NotionStatusGroup(
                        id: $0.id,
                        name: $0.name,
                        color: $0.color,
                        optionIds: $0.optionIds
                    )
                }
            }
            return NotionProperty(
                id: def.id,
                name: name,
                type: def.type,
                options: options,
                statusGroups: statusGroups
            )
        }

        return NotionDatabase(
            id: id,
            title: title.map { $0.plainText }.joined(),
            properties: props,
            url: url,
            lastEditedTime: lastEditedTime
        )
    }
}

struct QueryResponse: Decodable {
    let results: [NotionPage]
    let hasMore: Bool
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case results
        case hasMore = "has_more"
        case nextCursor = "next_cursor"
    }
}

struct QueryFilter {
    enum FilterType {
        case equals(property: String, value: Any)
        case contains(property: String, value: String)
        case checkbox(property: String, equals: Bool)
    }

    let filters: [FilterType]

    func toDictionary() -> [String: Any] {
        if filters.count == 1, let first = filters.first {
            return singleFilterDict(first)
        }

        return [
            "and": filters.map { singleFilterDict($0) }
        ]
    }

    private func singleFilterDict(_ filter: FilterType) -> [String: Any] {
        switch filter {
        case .equals(let property, let value):
            return [
                "property": property,
                "rich_text": ["equals": value]
            ]
        case .contains(let property, let value):
            return [
                "property": property,
                "rich_text": ["contains": value]
            ]
        case .checkbox(let property, let equals):
            return [
                "property": property,
                "checkbox": ["equals": equals]
            ]
        }
    }
}

private struct CreatePageRequest: Encodable {
    let parent: Parent
    let properties: [String: NotionPropertyValue]
}

private struct Parent: Encodable {
    let databaseId: String

    enum CodingKeys: String, CodingKey {
        case databaseId = "database_id"
    }
}

private struct UpdatePageRequest: Encodable {
    let properties: [String: NotionPropertyValue]
}

private struct NotionErrorResponse: Decodable {
    let code: String
    let message: String
}

// MARK: - NotionPage Decodable Extension

extension NotionPage: Decodable {
    enum CodingKeys: String, CodingKey {
        case id, properties, url, archived
        case parent
        case createdTime = "created_time"
        case lastEditedTime = "last_edited_time"
    }

    struct ParentInfo: Decodable {
        let databaseId: String?

        enum CodingKeys: String, CodingKey {
            case databaseId = "database_id"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)

        let parent = try container.decodeIfPresent(ParentInfo.self, forKey: .parent)
        databaseId = parent?.databaseId ?? ""

        properties = try container.decode([String: NotionPropertyValue].self, forKey: .properties)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        createdTime = try container.decode(Date.self, forKey: .createdTime)
        lastEditedTime = try container.decode(Date.self, forKey: .lastEditedTime)
        archived = try container.decodeIfPresent(Bool.self, forKey: .archived) ?? false
    }
}
