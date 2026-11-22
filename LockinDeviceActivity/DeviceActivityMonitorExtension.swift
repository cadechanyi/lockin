import Foundation
import DeviceActivity
import ManagedSettings

@objc(DeviceActivityMonitorExtension)
final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        if activity.rawValue.hasPrefix(LockinActivity.breakPrefix) {
            BlockEngine.clearShields()
            return
        }
        BlockEngine.applyShieldsIfNeeded()
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        if activity.rawValue.hasPrefix(LockinActivity.breakPrefix) {
            BlockEngine.applyShieldsIfNeeded()
            return
        }
        guard let snapshot = BlockEngine.loadSnapshot() else {
            BlockEngine.clearShields()
            return
        }
        let phase = ScheduleEvaluator.evaluate(snapshot: snapshot)
        if phase.shieldsShouldBeOn {
            BlockEngine.applyShields()
        } else {
            BlockEngine.clearShields()
        }
    }
}
