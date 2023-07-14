import CioInternalCommon
import CioTracking
import Foundation

// sourcery: InjectRegister = "ModuleHookProvider"
class MessagingInAppModuleHookProvider: ModuleHookProvider {
    private var diGraph: DIGraph {
        CustomerIO.shared.diGraph
    }

    var profileIdentifyHook: ProfileIdentifyHook? {
        MessagingInAppImplementation(diGraph: diGraph)
    }

    var queueRunnerHook: QueueRunnerHook? {
        nil
    }

    var screenTrackingHook: ScreenTrackingHook? {
        MessagingInAppImplementation(diGraph: diGraph)
    }
}
