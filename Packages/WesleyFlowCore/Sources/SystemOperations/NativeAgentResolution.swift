import Foundation
import Domain
@MainActor public enum NativeAgentResolution {
    public static func resolve(_ proposed:PersonalPlan) async throws ->PersonalPlan {
        var plan=try await NativePersonalMessages.resolve(proposed)
        plan=try NativePersonalFolders.resolve(plan)
        plan=try await NativeRecordTools.resolve(plan)
        plan=try NativeNotesActions.resolve(plan)
        plan=try await NativeContactActions.resolve(plan)
        plan=try NativeFileActions.resolve(plan)
        plan=try NativeScreenCapture.resolve(plan)
        plan=try NativeBrowserExtra.resolve(plan)
        plan=try await NativeMailActions.resolve(plan)
        plan=try NativeMenuActions.resolve(plan)
        plan=try NativeMacControl.resolve(plan)
        plan=try NativeScheduledMessages.resolve(plan)
        return try .init(id:plan.id,steps:plan.steps,createdAt:plan.createdAt,requiresReview:proposed.requiresReview)
    }
}
