import Foundation

// ===== STRUCT — value type (copies are independent) =====
struct PointStruct {
    var x: Int
    var y: Int
}

var structA = PointStruct(x: 1, y: 2)
var structB = structA        // makes a COPY
structB.x = 99

print("Struct A: \(structA.x)")   // 1  — unchanged
print("Struct B: \(structB.x)")   // 99 — only the copy changed


// ===== CLASS — reference type (copies share the same object) =====
class PointClass {
    var x: Int
    var y: Int
    init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

var classA = PointClass(x: 1, y: 2)
var classB = classA          // both point to the SAME object
classB.x = 99

print("Class A: \(classA.x)")     // 99 — changed too!
print("Class B: \(classB.x)")     // 99 — same object


// ===== Classes support inheritance; structs don't =====
class Animal {
    func sound() -> String { return "Some sound" }
}

class Dog: Animal {              // Dog inherits from Animal
    override func sound() -> String { return "Woof" }
}

let dog = Dog()
print(dog.sound())               // "Woof"
