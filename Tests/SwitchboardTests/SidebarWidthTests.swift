import Foundation
import Testing
@testable import Switchboard

@MainActor
struct SidebarWidthTests {
    @Test func defaultsToOneThird() {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "sw-\(UUID())")!)
        #expect(settings.sidebarWidth == .third)
        #expect(settings.sidebarWidth.fraction == 1.0 / 3)
    }

    @Test func persistsAcrossLaunches() {
        let defaults = UserDefaults(suiteName: "sw-\(UUID())")!
        AppSettings(defaults: defaults).sidebarWidth = .half
        #expect(AppSettings(defaults: defaults).sidebarWidth == .half)
    }
}
