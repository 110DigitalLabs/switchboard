import Testing
@testable import Switchboard

struct RowActivityTests {
    @Test func promptThenStopFinishesAndNotifiesOnce() {
        var activity = RowActivity()
        #expect(activity.apply(.promptSubmitted) == false)
        #expect(activity.state == .working)
        #expect(activity.apply(.toolActivity) == false)
        #expect(activity.apply(.turnFinished) == true)
        #expect(activity.state == .finished)
        // Claude's idle reminder escalates an unseen turn, without a second notification.
        #expect(activity.apply(.idleReminder) == false)
        #expect(activity.state == .needsInput)
    }

    @Test func viewingSettlesFinishedToIdleAndIdleReminderIsIgnored() {
        var activity = RowActivity(state: .finished)
        activity.markViewed()
        #expect(activity.state == .idle)
        activity.apply(.idleReminder)
        #expect(activity.state == .idle)
    }

    @Test func subagentsAreCounted() {
        var activity = RowActivity()
        activity.apply(.promptSubmitted)
        activity.apply(.subagentStarted)
        activity.apply(.subagentStarted)
        #expect(activity.state == .subagentsRunning)
        activity.apply(.toolActivity)
        #expect(activity.state == .subagentsRunning)
        activity.apply(.subagentStopped)
        #expect(activity.state == .subagentsRunning)
        activity.apply(.subagentStopped)
        #expect(activity.state == .working)
        #expect(activity.runningSubagents == 0)
        activity.apply(.subagentStopped)
        #expect(activity.runningSubagents == 0)
    }

    @Test func lateSubagentStopKeepsFinished() {
        var activity = RowActivity()
        activity.apply(.subagentStarted)
        activity.apply(.turnFinished)
        activity.apply(.subagentStopped)
        #expect(activity.state == .finished)
    }

    @Test func permissionNeedsInputUntilWorkResumes() {
        var activity = RowActivity()
        activity.apply(.toolActivity)
        #expect(activity.apply(.needsInput) == true)
        activity.apply(.toolActivity)
        #expect(activity.state == .working)
    }

    @Test func newSessionResets() {
        var activity = RowActivity(state: .needsInput, runningSubagents: 2)
        activity.apply(.sessionStarted)
        #expect(activity == RowActivity())
    }
}
