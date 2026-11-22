import Foundation

enum LockinActivity {
    static let blockPrefix = "lockin.block."
    static let breakPrefix = "lockin.break."

    static func blockName(for segmentID: UUID) -> String {
        blockPrefix + segmentID.uuidString
    }

    static func breakName(for breakID: UUID) -> String {
        breakPrefix + breakID.uuidString
    }
}
