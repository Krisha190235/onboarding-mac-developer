# 9.2 Codable JSON Parsing

**Deliverable:** playground decoding JSON.

The playground: `API/CodableJSONParsing.playground`. Ten sections, each decoding a
real-shaped payload and printing the result — open it and read down the console.

| # | Section | Point it makes |
| --- | --- | --- |
| 1 | JSON in, struct out | `Decodable` conformance alone is enough; `Codable` is `Decodable + Encodable` |
| 2 | `CodingKeys` | Renaming keys, and why the enum has to list every case |
| 3 | `.convertFromSnakeCase` | The shortcut, and how it produces `htmlUrl` rather than `htmlURL` |
| 4 | Nested objects and arrays | No special handling needed — nesting composes |
| 5 | Missing vs null vs absent | An optional tolerates both; a non-optional fails on either |
| 6 | Dates | `.iso8601` and the other strategies |
| 7 | Enums with an unknown fallback | Surviving a value the server added after you shipped |
| 8 | Flattening with a custom `init(from:)` | `nestedContainer` to lift `author.name` up a level |
| 9 | Reading `DecodingError` | The error names the exact failing key path |
| 10 | Encoding and round-tripping | Encoder strategies must mirror the decoder's |

## The three that actually catch people out

**Optionality is the contract.** A non-optional property fails to decode if the
key is missing *or* explicitly `null`. That's the right default — it turns a
silent wrong value into a loud error at the boundary — but it means modelling
optionality honestly rather than defensively marking everything `?`.

**Unknown enum cases break whole responses.** A plain `enum Status: String,
Decodable` throws when the server introduces `"archived"`, and because one bad
element fails the entire array, a single new value can take out a screen. A
custom `init(from:)` with an `unknown` fallback costs four lines:

```swift
init(from decoder: Decoder) throws {
    let raw = try decoder.singleValueContainer().decode(String.self)
    self = Status(rawValue: raw) ?? .unknown
}
```

**Strategies come in pairs.** `keyDecodingStrategy` / `keyEncodingStrategy` and
`dateDecodingStrategy` / `dateEncodingStrategy` are separate settings; configuring
one and forgetting the other is the usual reason a round trip doesn't come back
equal.

## Relationship to 9.1

`FetchRepoJSON.swift` uses explicit `CodingKeys`; section 3 here shows the
`.convertFromSnakeCase` alternative and exactly why I didn't use it there —
`html_url` becomes `htmlUrl`, and `spdx_id` becomes `spdxId`, neither of which is
what you'd write by hand. Both are fine; mixing them within one type is not.

## What I learned

Codable is generous by default and strict where it counts, and the strictness is
the useful part: it fails at the boundary, with a `DecodingError` that names the
key path, rather than handing the rest of the app a plausible-looking wrong value.
Most of the work is deciding what "optional" really means for each field, which is
a modelling question rather than a parsing one.

## Sources

- [Encoding and decoding custom types](https://developer.apple.com/documentation/foundation/archives-and-serialization/encoding-and-decoding-custom-types) — Apple
- [`JSONDecoder`](https://developer.apple.com/documentation/foundation/jsondecoder) — Apple
