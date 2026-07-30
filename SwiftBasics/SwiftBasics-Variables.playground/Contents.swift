import Foundation

// ===== Variables (var) — can change =====
var age = 20
print("Age is \(age)")
age = 21          // allowed — var can change
print("Age is now \(age)")

// ===== Constants (let) — cannot change =====
let name = "Krisha"
print("Name is \(name)")
// name = "Someone else"   // ❌ this would cause an error — let can't change

// ===== Data Types =====

// Int — whole numbers
let numberOfTasks: Int = 5

// Double — decimal numbers
let taxRate: Double = 0.1

// String — text
let greeting: String = "Hello, Swift!"

// Bool — true or false
let isLearning: Bool = true

print(numberOfTasks)
print(taxRate)
print(greeting)
print(isLearning)

// ===== Type Inference =====
// Swift can figure out the type automatically, so you don't always need to write it
let inferredInt = 42          // Swift knows this is an Int
let inferredDouble = 3.14     // Swift knows this is a Double
let inferredString = "text"   // Swift knows this is a String

print("Inferred: \(inferredInt), \(inferredDouble), \(inferredString)")
