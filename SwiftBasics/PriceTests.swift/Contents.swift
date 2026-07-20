import XCTest

let taxRate = 0.1

func priceWithTax(_ price: Double) -> Double {
    return price * (1 + taxRate)
}

class PriceTests: XCTestCase {

    func testPriceWithTax() {
        // A price of 100 with 10% tax should return 110
        XCTAssertEqual(priceWithTax(100), 110, accuracy: 0.001)
    }

    func testPriceWithZero() {
        // A price of 0 should return 0
        XCTAssertEqual(priceWithTax(0), 0, accuracy: 0.001)
    }
}
