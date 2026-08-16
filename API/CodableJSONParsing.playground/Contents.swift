import Foundation

// 9.2 Codable JSON Parsing
//
// Every section below decodes a real-shaped payload and prints the result, so
// you can run the playground and read down the console.

// ===== 1. The simple case: JSON in, struct out =====

struct Session: Decodable {
    let id: Int
    let title: String
    let minutes: Int
}

let simpleJSON = """
{ "id": 1, "title": "Deep work", "minutes": 50 }
"""

let session = try JSONDecoder().decode(Session.self, from: Data(simpleJSON.utf8))
print("1.", session.title, "-", session.minutes, "minutes")

// Conforming to Decodable is enough to be decoded; Codable is just
// Decodable + Encodable, which you want when the type also goes back out.

// ===== 2. Names that don't match: CodingKeys =====

struct User: Codable {
    let id: Int
    let displayName: String
    let joinedAt: String

    // Only the keys that differ need listing - but all cases must be present,
    // which is the usual reason this enum looks repetitive.
    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case joinedAt = "joined_at"
    }
}

let userJSON = """
{ "id": 7, "display_name": "Krisha", "joined_at": "2026-07-01" }
"""

let user = try JSONDecoder().decode(User.self, from: Data(userJSON.utf8))
print("2.", user.displayName, "joined", user.joinedAt)

// ===== 3. The shortcut, and its sharp edge =====

struct Repo: Decodable {
    let fullName: String
    let htmlUrl: String       // note: NOT htmlURL
    let stargazersCount: Int
}

let repoJSON = """
{ "full_name": "Krisha190235/onboarding-mac-developer",
  "html_url": "https://github.com/Krisha190235/onboarding-mac-developer",
  "stargazers_count": 3 }
"""

let snakeDecoder = JSONDecoder()
snakeDecoder.keyDecodingStrategy = .convertFromSnakeCase
let repo = try snakeDecoder.decode(Repo.self, from: Data(repoJSON.utf8))
print("3.", repo.fullName, "has", repo.stargazersCount, "stars")

// convertFromSnakeCase saves the CodingKeys enum, but it produces `htmlUrl`,
// not `htmlURL` - so a property named the way Swift style suggests fails to
// decode. Pick one approach per type and be consistent.

// ===== 4. Nested objects and arrays =====

struct Day: Decodable {
    let date: String
    let sessions: [Session]
    let summary: Summary

    struct Summary: Decodable {
        let totalMinutes: Int
        let completed: Bool
    }

    enum CodingKeys: String, CodingKey {
        case date, sessions, summary
    }
}

let dayJSON = """
{
  "date": "2026-08-16",
  "sessions": [
    { "id": 1, "title": "Deep work", "minutes": 50 },
    { "id": 2, "title": "Email",     "minutes": 15 }
  ],
  "summary": { "totalMinutes": 65, "completed": true }
}
"""

let day = try JSONDecoder().decode(Day.self, from: Data(dayJSON.utf8))
print("4.", day.sessions.count, "sessions,", day.summary.totalMinutes, "minutes total")

// Nesting needs no special handling: an array of Decodable is Decodable, and a
// nested type is just another Decodable.

// ===== 5. Missing vs null vs absent =====

struct Profile: Decodable {
    let name: String
    let bio: String?          // may be null, or may be missing entirely
    let website: String?
}

let profileJSON = """
{ "name": "Krisha", "bio": null }
"""

let profile = try JSONDecoder().decode(Profile.self, from: Data(profileJSON.utf8))
print("5. bio:", profile.bio ?? "(null)", "| website:", profile.website ?? "(absent)")

// An optional property tolerates BOTH null and a missing key. A non-optional
// property fails on either - which is the right default: it makes the contract
// explicit instead of silently inventing a value.

// ===== 6. Dates =====

struct Event: Decodable {
    let name: String
    let startsAt: Date
}

let eventJSON = """
{ "name": "Standup", "startsAt": "2026-08-17T09:30:00Z" }
"""

let dateDecoder = JSONDecoder()
dateDecoder.dateDecodingStrategy = .iso8601
let event = try dateDecoder.decode(Event.self, from: Data(eventJSON.utf8))
print("6.", event.name, "at", event.startsAt)

// Other strategies: .secondsSince1970, .millisecondsSince1970,
// .formatted(DateFormatter), and .custom for anything stranger.

// ===== 7. Enums, and surviving a value you've never seen =====

enum Status: String, Decodable {
    case active, paused, finished
    case unknown

    // Without this, a new server-side status breaks every response containing
    // it. Decoding a single value uses a singleValueContainer.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Status(rawValue: raw) ?? .unknown
    }
}

struct Task_: Decodable {
    let title: String
    let status: Status
}

let tasksJSON = """
[ { "title": "Write tests",  "status": "active" },
  { "title": "Ship release", "status": "archived" } ]
"""

let tasks = try JSONDecoder().decode([Task_].self, from: Data(tasksJSON.utf8))
for task in tasks { print("7.", task.title, "->", task.status) }

// ===== 8. Flattening a nested payload with a custom init =====

struct Article: Decodable {
    let title: String
    let authorName: String     // comes from author.name, one level down

    enum CodingKeys: String, CodingKey { case title, author }
    enum AuthorKeys: String, CodingKey { case name }

    init(from decoder: Decoder) throws {
        let root = try decoder.container(keyedBy: CodingKeys.self)
        title = try root.decode(String.self, forKey: .title)

        let author = try root.nestedContainer(keyedBy: AuthorKeys.self, forKey: .author)
        authorName = try author.decode(String.self, forKey: .name)
    }
}

let articleJSON = """
{ "title": "Sandboxing on macOS", "author": { "name": "Krisha", "id": 7 } }
"""

let article = try JSONDecoder().decode(Article.self, from: Data(articleJSON.utf8))
print("8.", article.title, "by", article.authorName)

// ===== 9. Reading the error instead of guessing =====

let brokenJSON = """
{ "id": 1, "title": "Deep work", "minutes": "fifty" }
"""

do {
    _ = try JSONDecoder().decode(Session.self, from: Data(brokenJSON.utf8))
} catch let error as DecodingError {
    switch error {
    case .typeMismatch(let type, let context):
        print("9. typeMismatch: expected \(type) at",
              context.codingPath.map(\.stringValue).joined(separator: "."))
    case .keyNotFound(let key, _):
        print("9. keyNotFound:", key.stringValue)
    case .valueNotFound(let type, let context):
        print("9. valueNotFound: \(type) at", context.codingPath)
    case .dataCorrupted(let context):
        print("9. dataCorrupted:", context.debugDescription)
    @unknown default:
        print("9. unknown DecodingError")
    }
}

// DecodingError names the exact key path that failed - far more useful than
// "couldn't parse response", and worth surfacing in logs.

// ===== 10. Going the other way: encoding =====

struct NewSession: Codable {
    let title: String
    let minutes: Int
    let startedAt: Date
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
encoder.dateEncodingStrategy = .iso8601
encoder.keyEncodingStrategy = .convertToSnakeCase

let payload = NewSession(title: "Focus block", minutes: 25, startedAt: Date())
let encoded = try encoder.encode(payload)
print("10.\n" + (String(data: encoded, encoding: .utf8) ?? ""))

// Round-trip check: what was encoded decodes back to an equal value.
let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .iso8601
decoder.keyDecodingStrategy = .convertFromSnakeCase
let roundTripped = try decoder.decode(NewSession.self, from: encoded)
print("10. round trip ok:", roundTripped.title == payload.title,
      "| minutes:", roundTripped.minutes)

// The encoder's strategies mirror the decoder's. Setting one and forgetting the
// other is the most common reason a round trip fails.
