import Foundation

let taxRate = 0.1

// Refactored: guard clause validates the input first
func priceWithTax(_ price: Double) -> Double {
    guard price >= 0 else {
        print("Error: price cannot be negative")
        return 0
    }
    return price * (1 + taxRate)
}

// Test covering invalid (negative) input
func testPriceWithTax() {
    // Valid input
    print(priceWithTax(100))   // Expected: 110.0

    // Invalid input — should print an error and return 0
    print(priceWithTax(-50))   // Expected: "Error: price cannot be negative" then 0.0
}

testPriceWithTax()