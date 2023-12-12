import CioInternalCommon
import Segment

/// Plugin class that adds device attributes to Segment requests
class DeviceAttributes: Plugin {
    public let type = PluginType.before
    public weak var analytics: Analytics?

    public var attributes: [String: Any]?

    public required init() {}

    public func execute<T: RawEvent>(event: T?) -> T? {
        guard var workingEvent = event else { return event }

        if var context = workingEvent.context?.dictionaryValue, let attributes = attributes {
            context[keyPath: "device.attributes"] = attributes
            do {
                workingEvent.context = try JSON(context)
            } catch {
                analytics?.reportInternalError(error)
            }
        }
        return workingEvent
    }
}
