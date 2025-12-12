import Foundation

/// Represents a Notion database
struct NotionDatabase: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let title: String
    let properties: [NotionProperty]
    let url: String?
    let lastEditedTime: Date?

    init(
        id: String,
        title: String,
        properties: [NotionProperty] = [],
        url: String? = nil,
        lastEditedTime: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.properties = properties
        self.url = url
        self.lastEditedTime = lastEditedTime
    }
}

/// Represents a Notion database property definition
struct NotionProperty: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let name: String
    let type: String

    // For select/multi-select properties
    var options: [NotionSelectOption]?

    init(id: String, name: String, type: String, options: [NotionSelectOption]? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.options = options
    }
}

/// Represents a select option in Notion
struct NotionSelectOption: Codable, Equatable, Hashable {
    let id: String
    let name: String
    let color: String?

    init(id: String, name: String, color: String? = nil) {
        self.id = id
        self.name = name
        self.color = color
    }
}

/// Represents a Notion page (database item)
struct NotionPage: Identifiable, Equatable {
    let id: String
    let databaseId: String
    let properties: [String: NotionPropertyValue]
    let url: String?
    let createdTime: Date
    let lastEditedTime: Date
    let archived: Bool

    init(
        id: String,
        databaseId: String,
        properties: [String: NotionPropertyValue] = [:],
        url: String? = nil,
        createdTime: Date = Date(),
        lastEditedTime: Date = Date(),
        archived: Bool = false
    ) {
        self.id = id
        self.databaseId = databaseId
        self.properties = properties
        self.url = url
        self.createdTime = createdTime
        self.lastEditedTime = lastEditedTime
        self.archived = archived
    }
}

/// Represents a Notion property value
enum NotionPropertyValue: Codable, Equatable {
    case title([RichText])
    case richText([RichText])
    case number(Double?)
    case select(SelectValue?)
    case multiSelect([SelectValue])
    case date(DateValue?)
    case checkbox(Bool)
    case url(String?)
    case email(String?)
    case phone(String?)

    struct RichText: Equatable, Codable {
        let plainText: String
        let href: String?

        init(plainText: String, href: String? = nil) {
            self.plainText = plainText
            self.href = href
        }

        // Decoding from Notion API (read format)
        enum CodingKeys: String, CodingKey {
            case plainText = "plain_text"
            case href
            case text  // For write format nested structure
        }

        enum TextKeys: String, CodingKey {
            case content
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // Read format uses plain_text
            plainText = try container.decode(String.self, forKey: .plainText)
            href = try container.decodeIfPresent(String.self, forKey: .href)
        }

        // Encoding to Notion API (write format: {"text": {"content": "..."}})
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            var textContainer = container.nestedContainer(keyedBy: TextKeys.self, forKey: .text)
            try textContainer.encode(plainText, forKey: .content)
        }
    }

    struct SelectValue: Codable, Equatable {
        let id: String?
        let name: String
        let color: String?

        init(id: String? = nil, name: String, color: String? = nil) {
            self.id = id
            self.name = name
            self.color = color
        }
    }

    struct DateValue: Codable, Equatable {
        let start: String
        let end: String?
        let timeZone: String?

        init(start: String, end: String? = nil, timeZone: String? = nil) {
            self.start = start
            self.end = end
            self.timeZone = timeZone
        }

        enum CodingKeys: String, CodingKey {
            case start, end
            case timeZone = "time_zone"
        }
    }

    // Custom Codable implementation
    enum CodingKeys: String, CodingKey {
        case type, title, richText = "rich_text", number, select, multiSelect = "multi_select"
        case date, checkbox, url, email, phone = "phone_number"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "title":
            let value = try container.decode([RichText].self, forKey: .title)
            self = .title(value)
        case "rich_text":
            let value = try container.decode([RichText].self, forKey: .richText)
            self = .richText(value)
        case "number":
            let value = try container.decodeIfPresent(Double.self, forKey: .number)
            self = .number(value)
        case "select":
            let value = try container.decodeIfPresent(SelectValue.self, forKey: .select)
            self = .select(value)
        case "multi_select":
            let value = try container.decode([SelectValue].self, forKey: .multiSelect)
            self = .multiSelect(value)
        case "date":
            let value = try container.decodeIfPresent(DateValue.self, forKey: .date)
            self = .date(value)
        case "checkbox":
            let value = try container.decode(Bool.self, forKey: .checkbox)
            self = .checkbox(value)
        case "url":
            let value = try container.decodeIfPresent(String.self, forKey: .url)
            self = .url(value)
        case "email":
            let value = try container.decodeIfPresent(String.self, forKey: .email)
            self = .email(value)
        case "phone_number":
            let value = try container.decodeIfPresent(String.self, forKey: .phone)
            self = .phone(value)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown property type: \(type)")
        }
    }

    // Encoding for Notion API writes - does NOT include "type" field
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .title(let value):
            // Write format: {"title": [{"text": {"content": "..."}}]}
            try container.encode(value, forKey: .title)
        case .richText(let value):
            try container.encode(value, forKey: .richText)
        case .number(let value):
            try container.encodeIfPresent(value, forKey: .number)
        case .select(let value):
            try container.encodeIfPresent(value, forKey: .select)
        case .multiSelect(let value):
            try container.encode(value, forKey: .multiSelect)
        case .date(let value):
            try container.encodeIfPresent(value, forKey: .date)
        case .checkbox(let value):
            try container.encode(value, forKey: .checkbox)
        case .url(let value):
            try container.encodeIfPresent(value, forKey: .url)
        case .email(let value):
            try container.encodeIfPresent(value, forKey: .email)
        case .phone(let value):
            try container.encodeIfPresent(value, forKey: .phone)
        }
    }
}

// MARK: - Helper Extensions
extension NotionPropertyValue {
    /// Extracts plain text from title or rich_text property
    var plainText: String? {
        switch self {
        case .title(let richTexts), .richText(let richTexts):
            return richTexts.map { $0.plainText }.joined()
        default:
            return nil
        }
    }

    /// Extracts select value name
    var selectName: String? {
        switch self {
        case .select(let value):
            return value?.name
        default:
            return nil
        }
    }

    /// Extracts checkbox value
    var isChecked: Bool {
        switch self {
        case .checkbox(let value):
            return value
        default:
            return false
        }
    }

    /// Extracts date start value
    var dateStart: String? {
        switch self {
        case .date(let value):
            return value?.start
        default:
            return nil
        }
    }
}
