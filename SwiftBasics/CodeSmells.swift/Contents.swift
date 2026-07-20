import Foundation

// ❌ BAD: magic number — what does 1.1 mean?
func priceWithTaxBad(_ price: Double) -> Double {
    return price * 1.1
}

// ✅ GOOD: a named constant makes it clear and easy to change
let taxRate = 0.1

func priceWithTax(_ price: Double) -> Double {
    return price * (1 + taxRate)
}

print(priceWithTaxBad(100))
print(priceWithTax(100))

// ❌ BAD: deeply nested if statements — hard to read
struct User {
    let isActive: Bool
    let hasPermission: Bool
}

func grantAccess() {
    print("Access granted ✅")
}

func checkAccessBad(_ user: User?) {
    if user != nil {
        if user!.isActive {
            if user!.hasPermission {
                grantAccess()
            }
        }
    }
}

// ✅ GOOD: guard clause flattens the nesting
func checkAccess(_ user: User?) {
    guard let user = user, user.isActive, user.hasPermission else { return }
    grantAccess()
}

let testUser = User(isActive: true, hasPermission: true)
checkAccess(testUser)
