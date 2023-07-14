import CioInternalCommon
import Foundation

class TrackingModuleHookProvider: ModuleHookProvider {
    private var diGraph: DIGraph {
        CustomerIO.shared.diGraph
    }

    var profileIdentifyHook: ProfileIdentifyHook? {
        nil
    }

    var queueRunnerHook: QueueRunnerHook? {
        diGraph.queueRunnerHook
    }

    var screenTrackingHook: ScreenTrackingHook? {
        nil
    }
}
