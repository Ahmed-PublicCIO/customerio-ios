import CioInternalCommon
import CioTracking
import Foundation
#if canImport(UserNotifications) && canImport(UIKit)
import UIKit
import UserNotifications
#endif

internal class MessagingPushImplementation: MessagingPushInstance {
    let logger: Logger
    let jsonAdapter: JsonAdapter
    let sdkConfig: SdkConfig // TODO: we can no longer inject the SDK config into objects if we want to allow dynamic changing of the SDK config. or, we modify the SdkConfig object to dynamically pull from a store. so all propererties are computed properties.
    let backgroundQueue: Queue

    private var customerIO: CustomerIO {
        CustomerIO.shared
    }

    /// testing init
    internal init(
        logger: Logger,
        jsonAdapter: JsonAdapter,
        sdkConfig: SdkConfig,
        backgroundQueue: Queue
    ) {
        self.sdkConfig = sdkConfig
        self.logger = logger
        self.jsonAdapter = jsonAdapter
        self.backgroundQueue = backgroundQueue
    }

    internal init(diGraph: DIGraph) {
        self.sdkConfig = diGraph.sdkConfig
        self.logger = diGraph.logger
        self.jsonAdapter = diGraph.jsonAdapter
        self.backgroundQueue = diGraph.queue
    }

    func deleteDeviceToken() {
        customerIO.deleteDeviceToken()
    }

    func registerDeviceToken(_ deviceToken: String) {
        customerIO.registerDeviceToken(deviceToken)
    }

    func trackMetric(deliveryID: String, event: Metric, deviceToken: String) {
        customerIO.trackMetric(deliveryID: deliveryID, event: event, deviceToken: deviceToken)
    }

    #if canImport(UserNotifications)
    func trackMetric(
        notificationContent: UNNotificationContent,
        event: Metric
    ) {
        guard let deliveryID: String = notificationContent.userInfo["CIO-Delivery-ID"] as? String,
              let deviceToken: String = notificationContent.userInfo["CIO-Delivery-Token"] as? String
        else {
            return
        }

        trackMetric(deliveryID: deliveryID, event: event, deviceToken: deviceToken)
    }

    // There are files that are created just for displaying a rich push. After a push is interacted with, those files
    // are no longer needed.
    // This function's job is to cleanup after a push is no longer being displayed.
    internal func cleanupAfterPushInteractedWith(pushContent: CustomerIOParsedPushPayload) {
        pushContent.cioAttachments.forEach { attachment in
            let localFilePath = attachment.url

            try? FileManager.default.removeItem(at: localFilePath)
        }
    }
    #endif
}
