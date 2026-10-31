import Foundation
import Domain

/// Shared by the two app-owned FoundationModels drivers. Cancellation never releases
/// ownership before the framework call settles.
actor FoundationGenerationLease {
    static let shared=FoundationGenerationLease()
    private var owner:UUID?
    func claim(_ id:UUID) throws { guard owner == nil else { throw PersonalPlanningFailure.busy };owner=id }
    func release(_ id:UUID) { if owner == id { owner=nil } }
}
