import Foundation

// ===== An optional might have a value, or be nil =====
var username: String? = "Krisha"
var nickname: String? = nil

// ===== if let — unwrap only if there's a value =====
if let name = username {
    print("Username is \(name)")   // runs, because username has a value
} else {
    print("No username")
}

if let nick = nickname {
    print("Nickname is \(nick)")
} else {
    print("No nickname set")       // runs, because nickname is nil
}

// ===== guard let — unwrap early or exit =====
func greet(_ name: String?) {
    guard let name = name else {
        print("No name provided")
        return
    }
    print("Hello, \(name)!")
}

greet("Krisha")   // prints "Hello, Krisha!"
greet(nil)        // prints "No name provided"

// ===== Chaining multiple optionals in one if let =====
var firstName: String? = "Krisha"
var lastName: String? = "Patel"

if let first = firstName, let last = lastName {
    print("Full name: \(first) \(last)")   // both unwrapped together
} else {
    print("Missing part of the name")
}

// ===== Optional chaining with ? =====
let length = username?.count   // safely gets count only if username isn't nil
print("Username length: \(String(describing: length))")
