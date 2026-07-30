import Foundation

// ===== 1. A generic FUNCTION — works with any type =====
// Without generics, you'd need one swap function per type.
// With generics, ONE function handles them all.
func swapTwoValues<T>(_ a: inout T, _ b: inout T) {
    let temp = a
    a = b
    b = temp
}

var x = 5
var y = 10
swapTwoValues(&x, &y)
print("x: \(x), y: \(y)")   // x: 10, y: 5  — worked with Ints

var first = "hello"
var second = "world"
swapTwoValues(&first, &second)
print("first: \(first), second: \(second)")   // swapped Strings too!


// ===== 2. A generic TYPE — a container that holds any type =====
struct Box<T> {
    var value: T

    func describe() -> String {
        return "This box contains: \(value)"
    }
}

let intBox = Box(value: 42)
print(intBox.describe())        // This box contains: 42

let stringBox = Box(value: "Swift")
print(stringBox.describe())     // This box contains: Swift

let boolBox = Box(value: true)
print(boolBox.describe())       // This box contains: true
