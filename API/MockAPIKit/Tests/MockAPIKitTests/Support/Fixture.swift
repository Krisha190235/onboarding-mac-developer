//
//  Fixture.swift
//
//  Loads the JSON in Tests/MockAPIKitTests/Fixtures. These are real responses,
//  captured from jsonplaceholder with curl and trimmed — not JSON I invented,
//  which is the difference between a test that proves the model matches the API
//  and one that proves the model matches my imagination.
//
//  Bundle.module exists because Package.swift declares the resources. It's
//  generated per target; there is no Bundle.main in a test bundle worth using.
//

import Foundation
import Testing

enum Fixture {
    static func data(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name,
                                          withExtension: "json",
                                          subdirectory: "Fixtures") else {
            throw FixtureError.missing(name)
        }
        return try Data(contentsOf: url)
    }

    static func json(_ name: String) throws -> String {
        String(decoding: try data(name), as: UTF8.self)
    }

    enum FixtureError: Error, CustomStringConvertible {
        case missing(String)

        var description: String {
            switch self {
            case .missing(let name):
                return "Fixtures/\(name).json isn't in the test bundle - check "
                     + "resources: [.copy(\"Fixtures\")] in Package.swift"
            }
        }
    }
}
