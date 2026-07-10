import SwiftData

extension ModelContext {
    /// Save that logs on failure instead of silently swallowing it.
    /// ponytail: a printed line is the whole error strategy — this is a
    /// single-user app; surface in UI only if failures ever actually happen.
    func saveOrLog(_ label: String = #function) {
        do {
            try save()
        } catch {
            print("⚠️ MintLeaf: save failed in \(label): \(error)")
        }
    }
}
