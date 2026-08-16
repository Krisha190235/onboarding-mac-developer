#!/usr/bin/env swift
//
//  FetchRepoJSON.swift - 9.1 URLSession GET Request
//
//  Fetches a GitHub repository as JSON, decodes it into a Swift type, and
//  prints both the decoded values and the raw JSON.
//
//  Run it:
//      swift API/FetchRepoJSON.swift
//      swift API/FetchRepoJSON.swift apple/swift
//
//  No API token needed - this endpoint is public and rate-limited to 60
//  requests an hour per IP for unauthenticated callers.
//
//  Requires Swift 5.7 or later for top-level `await`.
//

import Foundation

// MARK: - The shape of the response

/// Only the fields this tool actually uses. A decoder ignores everything else
/// in the payload, which is what makes Codable pleasant against a big API:
/// you model the slice you care about, not the whole thing.
struct Repository: Decodable {
    let fullName: String
    let description: String?      // optional because GitHub returns null
    let htmlURL: String
    let language: String?
    let stargazersCount: Int
    let forksCount: Int
    let openIssuesCount: Int
    let pushedAt: Date
    let owner: Owner
    let license: License?         // whole object can be null

    struct Owner: Decodable {
        let login: String
    }

    struct License: Decodable {
        let spdxID: String?

        enum CodingKeys: String, CodingKey {
            case spdxID = "spdx_id"
        }
    }

    // Explicit keys rather than .convertFromSnakeCase, because the automatic
    // strategy turns "html_url" into "htmlUrl" and "spdx_id" into "spdxId" -
    // subtly not what you'd name them by hand.
    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case description
        case htmlURL = "html_url"
        case language
        case stargazersCount = "stargazers_count"
        case forksCount = "forks_count"
        case openIssuesCount = "open_issues_count"
        case pushedAt = "pushed_at"
        case owner
        case license
    }
}

// MARK: - Errors worth telling the user apart

enum FetchError: LocalizedError {
    case notHTTP
    case notFound(String)
    case rateLimited(remaining: String?)
    case badStatus(Int)

    var errorDescription: String? {
        switch self {
        case .notHTTP:
            return "The response wasn't an HTTP response."
        case .notFound(let repo):
            return "No public repository called \(repo) - check the name, or it may be private."
        case .rateLimited(let remaining):
            return "GitHub rate-limited this request (remaining: \(remaining ?? "0")). Try again later."
        case .badStatus(let code):
            return "Unexpected HTTP status \(code)."
        }
    }
}

// MARK: - The request

func fetchRepository(_ repo: String) async throws -> (Repository, Data) {
    guard let url = URL(string: "https://api.github.com/repos/\(repo)") else {
        throw URLError(.badURL)
    }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.timeoutInterval = 15
    // GitHub rejects requests with no User-Agent, and versions its API through
    // headers rather than the URL.
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
    request.setValue("onboarding-mac-developer/1.0", forHTTPHeaderField: "User-Agent")

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let http = response as? HTTPURLResponse else { throw FetchError.notHTTP }

    // A 404 is a perfectly successful network round trip. URLSession only
    // throws for transport problems - the status code is yours to check.
    switch http.statusCode {
    case 200:
        break
    case 403, 429:
        throw FetchError.rateLimited(
            remaining: http.value(forHTTPHeaderField: "X-RateLimit-Remaining"))
    case 404:
        throw FetchError.notFound(repo)
    default:
        throw FetchError.badStatus(http.statusCode)
    }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601   // GitHub sends "2026-08-16T09:12:33Z"

    return (try decoder.decode(Repository.self, from: data), data)
}

// MARK: - Output helpers

func prettyPrinted(_ data: Data) -> String {
    guard let object = try? JSONSerialization.jsonObject(with: data),
          let pretty = try? JSONSerialization.data(withJSONObject: object,
                                                   options: [.prettyPrinted, .sortedKeys]),
          let text = String(data: pretty, encoding: .utf8) else {
        return String(data: data, encoding: .utf8) ?? "(unreadable)"
    }
    return text
}

// MARK: - Main

let repoName = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Krisha190235/onboarding-mac-developer"

print("GET https://api.github.com/repos/\(repoName)\n")

do {
    let (repo, raw) = try await fetchRepository(repoName)

    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short

    print("Decoded:")
    print("  name         \(repo.fullName)")
    print("  owner        \(repo.owner.login)")
    print("  description  \(repo.description ?? "(none)")")
    print("  language     \(repo.language ?? "(none)")")
    print("  stars        \(repo.stargazersCount)")
    print("  forks        \(repo.forksCount)")
    print("  open issues  \(repo.openIssuesCount)")
    print("  licence      \(repo.license?.spdxID ?? "(none)")")
    print("  last push    \(formatter.string(from: repo.pushedAt))")
    print("  url          \(repo.htmlURL)")

    // The deliverable: the JSON as fetched, formatted for reading.
    let lines = prettyPrinted(raw).split(separator: "\n", omittingEmptySubsequences: false)
    print("\nRaw JSON (\(lines.count) lines, first 30 shown):")
    for line in lines.prefix(30) { print("  \(line)") }
    if lines.count > 30 { print("  ... \(lines.count - 30) more lines") }

} catch let error as FetchError {
    print("Failed: \(error.localizedDescription)")
    exit(1)
} catch let error as URLError where error.code == .notConnectedToInternet {
    print("Failed: no network connection.")
    exit(1)
} catch let error as DecodingError {
    // Worth catching separately: this means the API changed shape, not that
    // the network failed.
    print("Failed to decode the response - the payload didn't match Repository:")
    print("  \(error)")
    exit(1)
} catch {
    print("Failed: \(error.localizedDescription)")
    exit(1)
}
