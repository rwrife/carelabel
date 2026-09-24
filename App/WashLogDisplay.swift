import Foundation

// Issue #6: date display helper for wash-log rows and "last washed"
// surfacing. Built per call — DateFormatter is a mutable reference type,
// so a shared instance would be rejected in Swift 6 language mode
// (matching the pattern in GarmentDetailView).

enum WashLogDisplay {
    static func dateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
