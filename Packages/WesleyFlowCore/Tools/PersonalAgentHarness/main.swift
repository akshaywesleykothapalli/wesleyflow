import Foundation
import Domain
import SystemOperations

@main struct PersonalAgentHarness {
    @MainActor static func main() async {
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            guard let command = args.first else { print("Usage: PersonalAgentHarness 'create note hello then remind me review in 10 minutes then open Notes' [--execute]"); return }
            let plan = try PersonalIntentParser.parse(command)
            for (i, step) in plan.steps.enumerated() { print("\(i+1). \(step.tool.rawValue): \(step.text) \(step.date?.ISO8601Format() ?? "")") }
            guard args.contains("--execute") else { print("Parsed offline. No effects. Use app Commands for native permissions."); return }
            print("Approve exactly these actions? Type APPROVE:")
            guard readLine() == "APPROVE" else { return }
            let url = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("WesleyFlow/PersonalAgent/harness-queue.json")
            let engine = try PersonalAgentEngine(url:url,runner:NativePersonalTools())
            try engine.enqueue(plan); try await engine.approveAndRun(plan)
            print(engine.records.last?.state.rawValue ?? "unknown")
            print("CLI permission attribution differs from the app; verify TCC through the native app.")
        } catch { print("Failed: \(error)") }
    }
}
