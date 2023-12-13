import Foundation

/// Defines the contract for an event bus system.
///
/// Specifies methods for sending events and registering for event notifications.
/// Supports type-safe event handling and scheduler-based execution.
public protocol EventBus: AutoMockable {
    /// Sends an event.
    ///
    /// - Parameters:
    ///     - event: An instance of the event that conforms to the `EventRepresentable` protocol.
    func send<E: EventRepresentable>(_ event: E)

    /// Triggers action when EventBus emits an event.
    ///
    /// - Parameters:
    ///     - eventType: Type of an event that triggers the action.
    ///     - action: The action to perform when an event is emitted by EventBus. The  event instance is passed as a parameter to action.
    /// - Returns: A cancellable instance, which needs to be stored as long as action needs to be triggered. Deallocation of the result will unsubscribe from the event and action will not be triggered.
    func addListener<E: EventRepresentable>(_ listener: Any, toEvents eventType: E.Type, onEventCall selector: Selector)

    /// Triggers action on specific scheduler when EventBus emits an event.
    ///
    /// - Parameters:
    ///     - eventType: Type of an event that triggers the action.
    ///     - scheduler: The scheduler that is used to perform action.
    ///     - action: The action to perform when an event is emitted by EventBus. The  event instance is passed as a parameter to action.
    /// - Returns: A cancellable instance, which needs to be stored as long as action needs to be triggered. Deallocation of the result will unsubscribe from the event and action will not be triggered.
    func stopListening(_ listener: Any)

    func parse<E: EventRepresentable>(_ notification: Notification) -> E?
}

/**
 A wrapper around notificationcenter to act as our SDK's eventbus.

 Keep file small in size because this file is tested during QA, not automated tests.

 This class's job:
 1. Allows us to use EventRepresentable data types for eventbus events.
 2. Mock Notificationcenter in our tests.
 */
// sourcery: InjectRegisterShared = "EventBus"
class NotificationCenterEventBus: EventBus {
    public func send<E: EventRepresentable>(_ event: E) {
        let nameOfEvent = String(describing: type(of: event)) // name of the class

        let eventData: [AnyHashable: Any] = [
            "data": event.params
        ]

        NotificationCenter.default.post(name: NSNotification.Name(rawValue: nameOfEvent), object: nil, userInfo: eventData)
    }

    func addListener<E>(_ listener: Any, toEvents eventType: E.Type, onEventCall selector: Selector) where E: EventRepresentable {
        let nameOfEvent = String(describing: eventType) // name of the class

        NotificationCenter.default.addObserver(listener, selector: selector, name: NSNotification.Name(rawValue: nameOfEvent), object: nil)
    }

    func stopListening(_ listener: Any) {
        NotificationCenter.default.removeObserver(listener)
    }

    func parse<E>(_ notification: Notification) -> E? where E: EventRepresentable {
        guard let userInfo = notification.userInfo else {
            return nil
        }

        guard let data = userInfo["data"] as? E else {
            logger.error("this should not happen. log an error to SDK here as it probably indicates a bug in the SDK code")
            return nil
        }

        return data
    }
}

// Example usage of eventbus:
class Foo {
    private let eventBus: EventBus

    init(eventBus: EventBus) {
        self.eventBus = eventBus

        self.eventBus.addListener(self, toEvents: ProfileIdentifiedEvent.self, onEventCall: #selector(onProfileIdentified))
    }

    deinit { // swift function called when an object gets removed from memory
        // remove eventbus listener.
        // important to not forget to do this. maybe we can write a linter rule to remind us to add this in files that use eventbus?
        self.eventBus.stopListening(self)
    }

    // Function that gets called by notificationcenter when eventbus sends an event
    @objc func onProfileIdentified(_ notification: Notification) {
        // Convert the NotificationCenter [AnyHashable: Any] data type and convert into the Event data type we need.
        guard let event: ProfileIdentifiedEvent = eventBus.parse(notification) else {
            return
        }

        // Do something with event
        event.identifier
    }
}
