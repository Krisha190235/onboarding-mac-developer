#!/usr/bin/env swift
//
//  PostRequest.swift - 9.4 POST Request
//
//  Sending data rather than fetching it: a JSON body, a form-urlencoded body,
//  a multipart upload, and the parts that only matter for writes - status
//  codes, retry safety and idempotency.
//
//  Run it:
//      swift API/PostRequest.swift
//
//  Targets are public test endpoints, so nothing real is created:
//    - jsonplaceholder.typicode.com  fakes a create and echoes the resource
//    - httpbin.org                   echoes exactly what it received
//
//  Requires Swift 5.7 or later for top-level `await`.
//

import Foundation

// MARK: - Shared

enum APIError: LocalizedError {
    case client(status: Int, body: String)   // 4xx - don't retry, fix the request
    case server(status: Int)                 // 5xx - retrying may work
    case notHTTP

    var errorDescription: String? {
        switch self {
        case .client(let status, let body):
            return "HTTP \(status): \(body.prefix(200))"
        case .server(let status):
            return "HTTP \(status) - server side, retryable"
        case .notHTTP:
            return "Response wasn't HTTP"
        }
    }

    var isRetryable: Bool {
        if case .server = self { return true }
        return false
    }
}

/// Validates a write response and hands back the body.
/// Writes succeed with more than one status: 200 with a body, 201 Created,
/// 202 Accepted, 204 No Content.
func validate(_ data: Data, _ response: URLResponse) throws -> Data {
    guard let http = response as? HTTPURLResponse else { throw APIError.notHTTP }

    switch http.statusCode {
    case 200, 201, 202, 204:
        if let location = http.value(forHTTPHeaderField: "Location") {
            print("      Location: \(location)")
        }
        return data
    case 400...499:
        // The body of a 4xx usually says exactly what's wrong - printing
        // "request failed" instead of reading it wastes the best clue you get.
        throw APIError.client(status: http.statusCode,
                              body: String(data: data, encoding: .utf8) ?? "")
    default:
        throw APIError.server(status: http.statusCode)
    }
}

// MARK: - 1. JSON body

struct NewSession: Encodable {
    let title: String
    let minutes: Int
    let userId: Int
}

struct CreatedSession: Decodable {
    let id: Int
    let title: String
    let minutes: Int
}

func postJSON() async throws -> CreatedSession {
    var request = URLRequest(url: URL(string: "https://jsonplaceholder.typicode.com/posts")!)
    request.httpMethod = "POST"
    // Content-Type describes what you're sending; Accept describes what you
    // want back. Sending JSON without the header is the most common cause of
    // an inexplicable 400 or 415.
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.timeoutInterval = 15

    let body = NewSession(title: "Deep work", minutes: 50, userId: 7)
    let encoded = try JSONEncoder().encode(body)

    // upload(for:from:) rather than setting httpBody: it's the API meant for
    // sending data, and unlike httpBody it also works on background sessions.
    let (data, response) = try await URLSession.shared.upload(for: request, from: encoded)
    let validated = try validate(data, response)

    return try JSONDecoder().decode(CreatedSession.self, from: validated)
}

// MARK: - 2. Form-urlencoded body
//
// Old web forms and plenty of OAuth endpoints want this instead of JSON.
// Percent-encoding has to be done by hand, and urlQueryAllowed is too
// permissive - it leaves +, & and = alone, which corrupts the pairs.

func formEncoded(_ pairs: [String: String]) -> Data {
    let allowed = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    let encoded = pairs
        .sorted { $0.key < $1.key }
        .map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }
        .joined(separator: "&")

    return Data(encoded.utf8)
}

func postForm() async throws -> String {
    var request = URLRequest(url: URL(string: "https://httpbin.org/post")!)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 15

    let body = formEncoded([
        "title": "Deep work & focus",     // & and spaces must survive the trip
        "minutes": "50",
        "note": "50% done"
    ])

    let (data, response) = try await URLSession.shared.upload(for: request, from: body)
    let validated = try validate(data, response)
    return String(data: validated, encoding: .utf8) ?? ""
}

// MARK: - 3. Multipart/form-data
//
// What a file upload looks like underneath: a boundary string separating
// parts, each with its own headers. CRLF line endings are required.

func multipartBody(fields: [String: String],
                   fileName: String,
                   fileContents: Data,
                   boundary: String) -> Data {
    var body = Data()
    let crlf = "\r\n"

    for (key, value) in fields.sorted(by: { $0.key < $1.key }) {
        body.append(Data("--\(boundary)\(crlf)".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"\(key)\"\(crlf)\(crlf)".utf8))
        body.append(Data("\(value)\(crlf)".utf8))
    }

    body.append(Data("--\(boundary)\(crlf)".utf8))
    body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\(crlf)".utf8))
    body.append(Data("Content-Type: text/plain\(crlf)\(crlf)".utf8))
    body.append(fileContents)
    body.append(Data(crlf.utf8))

    body.append(Data("--\(boundary)--\(crlf)".utf8))   // closing boundary has trailing dashes
    return body
}

func postMultipart() async throws -> Int {
    let boundary = "Boundary-\(UUID().uuidString)"

    var request = URLRequest(url: URL(string: "https://httpbin.org/post")!)
    request.httpMethod = "POST"
    request.setValue("multipart/form-data; boundary=\(boundary)",
                     forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 20

    let body = multipartBody(fields: ["title": "Session log"],
                             fileName: "session.txt",
                             fileContents: Data("50 minutes of deep work\n".utf8),
                             boundary: boundary)

    let (data, response) = try await URLSession.shared.upload(for: request, from: body)
    _ = try validate(data, response)
    return body.count
}

// MARK: - 4. Retrying a write safely
//
// A GET can be retried freely. A POST cannot: the first attempt may have
// succeeded and only the response got lost, so a blind retry can create the
// same thing twice. Retry only transport failures and 5xx, and send an
// idempotency key so the server can recognise the duplicate.

func postWithRetry(attempts: Int = 3) async throws -> CreatedSession {
    let idempotencyKey = UUID().uuidString   // same value for every retry

    var lastError: Error?
    for attempt in 1...attempts {
        do {
            var request = URLRequest(url: URL(string: "https://jsonplaceholder.typicode.com/posts")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
            request.timeoutInterval = 15

            let encoded = try JSONEncoder().encode(
                NewSession(title: "Retried session", minutes: 25, userId: 7))
            let (data, response) = try await URLSession.shared.upload(for: request, from: encoded)
            let validated = try validate(data, response)

            print("      succeeded on attempt \(attempt) with key \(idempotencyKey.prefix(8))")
            return try JSONDecoder().decode(CreatedSession.self, from: validated)

        } catch let error as APIError where error.isRetryable {
            lastError = error
        } catch let error as URLError where error.code == .timedOut
                                        || error.code == .networkConnectionLost {
            lastError = error
        }
        // Anything else - a 4xx, a decoding failure - is not retried: the same
        // request will fail the same way.

        if attempt < attempts {
            let backoff = pow(2.0, Double(attempt - 1)) + Double.random(in: 0...0.3)
            print("      attempt \(attempt) failed, retrying in \(String(format: "%.1f", backoff))s")
            try await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
        }
    }

    throw lastError ?? APIError.notHTTP
}

// MARK: - Run them

print("1. POST JSON to jsonplaceholder")
do {
    let created = try await postJSON()
    print("   created id \(created.id): \(created.title), \(created.minutes) min\n")
} catch {
    print("   failed: \(error.localizedDescription)\n")
}

print("2. POST form-urlencoded to httpbin")
do {
    let echoed = try await postForm()
    // httpbin echoes the parsed form back, so you can see the encoding survived
    let formLine = echoed
        .split(separator: "\n")
        .first { $0.contains("\"form\"") || $0.contains("title") }
        .map(String.init) ?? "(no form field in reply)"
    print("   echoed: \(formLine.trimmingCharacters(in: .whitespaces))\n")
} catch {
    print("   failed: \(error.localizedDescription)\n")
}

print("3. POST multipart/form-data to httpbin")
do {
    let bytes = try await postMultipart()
    print("   uploaded a \(bytes)-byte multipart body\n")
} catch {
    print("   failed: \(error.localizedDescription)\n")
}

print("4. POST with retry and an idempotency key")
do {
    let created = try await postWithRetry()
    print("   created id \(created.id)\n")
} catch {
    print("   failed after retries: \(error.localizedDescription)\n")
}

// Notes that don't fit in code:
//  - Inside a sandboxed app this needs com.apple.security.network.client (8.4).
//  - Never log a request that carries an Authorization header or a token;
//    print the URL and status, not the headers.
//  - Tokens belong in the Keychain, not in the source or a plist.
