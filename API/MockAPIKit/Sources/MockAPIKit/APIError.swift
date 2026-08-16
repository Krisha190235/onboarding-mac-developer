//
//  APIError.swift
//
//  Condensed from 9.5. Same three questions: what goes in the log, what goes on
//  the screen, and is a Retry button worth showing.
//

import Foundation

public enum APIError: LocalizedError {
    case invalidURL(String)
    case offline
    case timedOut
    case cancelled
    case http(status: Int, body: String)
    case malformedResponse(DecodingError)
    case unknown(Error)

    /// Safe for a user to read.
    public var userMessage: String {
        switch self {
        case .offline:
            return "You appear to be offline. Check your connection and try again."
        case .timedOut:
            return "The server took too long to respond."
        case .cancelled:
            return ""
        case .http(let status, _) where status == 404:
            return "That post no longer exists."
        case .http(let status, _) where status == 401 || status == 403:
            return "Your session has expired. Please sign in again."
        case .http(let status, _) where (500...599).contains(status):
            return "The server is having trouble. Try again in a moment."
        case .http, .invalidURL, .malformedResponse, .unknown:
            return "Something went wrong."
        }
    }

    /// For the log.
    public var errorDescription: String? {
        switch self {
        case .invalidURL(let path):        return "couldn't build a URL from '\(path)'"
        case .offline:                     return "URLError.notConnectedToInternet"
        case .timedOut:                    return "URLError.timedOut"
        case .cancelled:                   return "cancelled"
        case .http(let status, let body):  return "HTTP \(status): \(body.prefix(120))"
        case .malformedResponse(let error): return "decoding: \(APIError.describe(error))"
        case .unknown(let error):          return "unexpected: \(error)"
        }
    }

    public var isRetryable: Bool {
        switch self {
        case .offline, .timedOut:
            return true
        case .http(let status, _):
            return (500...599).contains(status) || status == 408 || status == 429
        case .cancelled, .invalidURL, .malformedResponse, .unknown:
            return false
        }
    }

    /// `DecodingError.localizedDescription` says "the data couldn't be read".
    /// Everything useful — which key, which type, how deep — is in the Context.
    public static func describe(_ error: DecodingError) -> String {
        func path(_ context: DecodingError.Context) -> String {
            let parts = context.codingPath.map { key -> String in
                if let index = key.intValue { return "[\(index)]" }
                return key.stringValue
            }
            return parts.isEmpty ? "<root>" : parts.joined(separator: ".")
        }

        switch error {
        case .keyNotFound(let key, let context):
            return "missing key '\(key.stringValue)' at \(path(context))"
        case .typeMismatch(let type, let context):
            return "expected \(type) at \(path(context))"
        case .valueNotFound(let type, let context):
            return "null where \(type) was required at \(path(context))"
        case .dataCorrupted(let context):
            return "corrupt data at \(path(context)) - \(context.debugDescription)"
        @unknown default:
            return "unknown decoding failure"
        }
    }

    public static func map(_ error: Error) -> APIError {
        switch error {
        case let error as APIError:      return error
        case let error as DecodingError: return .malformedResponse(error)
        case let error as URLError:
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost: return .offline
            case .timedOut:                                       return .timedOut
            case .cancelled:                                      return .cancelled
            default:                                              return .unknown(error)
            }
        case is CancellationError: return .cancelled
        default:                   return .unknown(error)
        }
    }
}
