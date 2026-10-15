import Testing
import UIKit
@testable import BatteryETA

struct GuideTests {
    @Test func showsWhileNoIPIsSaved() {
        #expect(GuideSheet.showsAtLaunch(BatterySettings()))
        #expect(!GuideSheet.showsAtLaunch(BatterySettings(host: "192.168.1.50")))
    }

    @Test func theScreenshotsShip() {
        for name in ["GuideGear", "GuideIP", "GuideLocalAPI"] {
            #expect(UIImage(named: name) != nil, "No image \(name)")
        }
    }
}
