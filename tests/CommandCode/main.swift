import Foundation

@main
struct CommandCodeChecks {
    @MainActor static func main() async {
        let credits = Data(#"{"credits":{"monthlyCredits":62.4611058191},"windowLimits":{"fiveHour":{"used":0.131632466,"cap":14,"resetAt":1790940606965},"weekly":{"used":7.5388941809,"cap":35,"resetAt":1791045003318}}}"#.utf8)
        let subscription = Data(#"{"data":{"planId":"individual-goat","status":"active","currentPeriodEnd":"2026-10-26T16:28:27.000Z"}}"#.utf8)
        let full = CommandCodeAPI.decode(credits: credits, subscription: subscription)
        precondition(full.status == .ok && full.quotas.count == 3)
        precondition(abs(full.quotas[0].used - 0.9402319) < 0.00001)
        precondition(abs(full.quotas[1].used - 21.5396977) < 0.00001)
        precondition(abs(full.quotas[2].used - 10.7698488) < 0.00001)
        precondition(full.quotas[0].resetsAt?.timeIntervalSince1970 == 1790940606.965)
        let partial = CommandCodeAPI.decode(credits: credits, subscription: nil)
        precondition(partial.quotas.count == 2)
        if case .stale = partial.status {} else { fatalError("Missing month must be stale") }
        let state = AppState()
        state.update(snapshot: full)
        state.update(snapshot: partial)
        precondition(state.snapshots["command-code"]?.quotas.count == 3)
        precondition(state.snapshots["command-code"]?.quotas[2].resetText?.contains("上次数据") == true)
        let invalid = Data(#"{"credits":{"monthlyCredits":null},"windowLimits":{"fiveHour":{"used":true,"cap":14,"resetAt":1790940606965},"weekly":{"used":1,"cap":0,"resetAt":1791045003318}}}"#.utf8)
        let failure = CommandCodeAPI.decode(credits: invalid, subscription: subscription)
        precondition(failure.quotas.isEmpty)
        state.update(snapshot: failure)
        precondition(state.snapshots["command-code"]?.quotas.count == 3)
        let unknown = Data(#"{"data":{"planId":"unknown","status":"active","currentPeriodEnd":"2026-10-26T16:28:27Z"}}"#.utf8)
        precondition(CommandCodeAPI.decode(credits: credits, subscription: unknown).quotas.count == 2)
        state.update(snapshot: full)
        precondition(state.snapshots["command-code"]?.status == .ok)
        print("PASS: quota math, resets, missing fields, invalid values, unknown plan, stale retention and recovery")
        if CommandLine.arguments.contains("--live"), let key = CommandCodeAPI.loadKey() {
            let live = await CommandCodeAPI.fetch(apiKey: key)
            precondition(live.status == .ok && live.quotas.count == 3, "Live API must return three valid windows")
            print("PASS: live URLSession request returned three windows")
            for q in live.quotas { print(q.id, String(format: "%.2f%%", q.used), q.resetText ?? "") }
        }
    }
}
