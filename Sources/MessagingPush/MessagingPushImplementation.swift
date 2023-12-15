import CioInternalCommon
import Foundation
#if canImport(UserNotifications) && canImport(UIKit)
import UIKit
import UserNotifications
#endif

class MessagingPushImplementation: MessagingPushInstance {
    let moduleConfig: MessagingPushConfigOptions
    let logger: Logger
    let jsonAdapter: JsonAdapter

    private let eventHandlingManager: EventBusHandler

    /// testing init
    init(
        moduleConfig: MessagingPushConfigOptions,
        logger: Logger,
        jsonAdapter: JsonAdapter,
        eventHandlingManager: EventBusHandler
    ) {
        self.moduleConfig = moduleConfig
        self.logger = logger
        self.jsonAdapter = jsonAdapter
        self.eventHandlingManager = eventHandlingManager
    }

    init(diGraph: DIGraphShared, moduleConfig: MessagingPushConfigOptions) {
        self.moduleConfig = moduleConfig
        self.logger = diGraph.logger
        self.jsonAdapter = diGraph.jsonAdapter
        self.eventHandlingManager = EventBusHandler(eventBus: diGraph.eventBus, eventStorage: diGraph.eventStorage)
    }

    private func handleEventStorageError(_ error: Error) {
        // Implement error handling logic
        print("Error loading stored events: \(error)")
    }

    func deleteDeviceToken() {
        eventHandlingManager.postEvent(DeleteDeviceTokenEvent())
    }

    func registerDeviceToken(_ deviceToken: String) {
        eventHandlingManager.postEvent(RegisterDeviceTokenEvent(token: deviceToken))
    }

    func trackMetric(deliveryID: String, event: Metric, deviceToken: String) {
        eventHandlingManager.postEvent(TrackMetricEvent(deliveryID: deliveryID, event: event.rawValue, deviceToken: deviceToken))
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
    func cleanupAfterPushInteractedWith(pushContent: CustomerIOParsedPushPayload) {
        pushContent.cioAttachments.forEach { attachment in
            let localFilePath = attachment.url

            try? FileManager.default.removeItem(at: localFilePath)
        }
    }
    #endif
}
