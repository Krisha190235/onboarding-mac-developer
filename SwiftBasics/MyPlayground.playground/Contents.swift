import Foundation

// ===== A protocol is a contract — any type adopting it must meet its requirements =====
protocol Greetable {
    var name: String { get }
    func greet() -> String
}

// ===== An extension can give the protocol a DEFAULT implementation =====
extension Greetable {
    func greet() -> String {
        return "Hello, my name is \(name)"
    }
}

// ===== A struct adopting the protocol gets greet() for free =====
struct Person: Greetable {
    var name: String
}

let krisha = Person(name: "Krisha")
print(krisha.greet())   // uses the default: "Hello, my name is Krisha"

// ===== A type can also provide its OWN version, overriding the default =====
struct Robot: Greetable {
    var name: String
    func greet() -> String {
        return "BEEP BOOP. Unit \(name) online."
    }
}

let robot = Robot(name: "R2")
print(robot.greet())   // uses Robot's own version

// ===== Extensions can also add functionality to existing types =====
extension Int {
    func squared() -> Int {
        return self * self
    }
}

print(5.squared())   // 25 — we added a method to Int itself!
