import Foundation

// ===== 1. Define a custom error type =====
enum WithdrawalError: Error {
    case insufficientFunds
    case negativeAmount
}

// ===== 2. A function that can throw errors =====
func withdraw(balance: Double, amount: Double) throws -> Double {
    if amount < 0 {
        throw WithdrawalError.negativeAmount
    }
    if amount > balance {
        throw WithdrawalError.insufficientFunds
    }
    return balance - amount
}

// ===== 3. Handle errors with do / try / catch =====

// A successful case
do {
    let newBalance = try withdraw(balance: 100, amount: 30)
    print("Withdrawal successful. New balance: \(newBalance)")
} catch {
    print("Something went wrong: \(error)")
}

// A failing case — too much money
do {
    let newBalance = try withdraw(balance: 100, amount: 500)
    print("New balance: \(newBalance)")
} catch WithdrawalError.insufficientFunds {
    print("Error: Not enough funds")
} catch WithdrawalError.negativeAmount {
    print("Error: Amount can't be negative")
} catch {
    print("Unexpected error: \(error)")
}

// A failing case — negative amount
do {
    let newBalance = try withdraw(balance: 100, amount: -20)
    print("New balance: \(newBalance)")
} catch WithdrawalError.negativeAmount {
    print("Error: Amount can't be negative")
} catch {
    print("Unexpected error: \(error)")
}
