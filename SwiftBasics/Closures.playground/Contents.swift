import Foundation

let numbers = [1, 2, 3, 4, 5, 6]

// ===== A closure stored in a variable =====
let double = { (n: Int) -> Int in
    return n * 2
}
print(double(5))   // 10

// ===== map — transform every element =====
let doubled = numbers.map { $0 * 2 }
print("Doubled: \(doubled)")   // [2, 4, 6, 8, 10, 12]

// ===== filter — keep only elements that match a condition =====
let evens = numbers.filter { $0 % 2 == 0 }
print("Evens: \(evens)")       // [2, 4, 6]

// ===== reduce — combine all elements into one value =====
let sum = numbers.reduce(0) { $0 + $1 }
print("Sum: \(sum)")           // 21

// ===== Chaining them together =====
// Take numbers, keep evens, double them, then sum
let result = numbers
    .filter { $0 % 2 == 0 }   // [2, 4, 6]
    .map { $0 * 2 }           // [4, 8, 12]
    .reduce(0, +)             // 24
print("Chained result: \(result)")   // 24
