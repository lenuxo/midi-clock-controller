import Foundation

enum InterfaceZoom {
    static let minimum = 80
    static let maximum = 150
    static func clamped(_ percent: Int) -> Int { min(maximum, max(minimum, percent)) }
    static func adjusted(_ percent: Int, by step: Int) -> Int { clamped(clamped(percent) + step) }
}
