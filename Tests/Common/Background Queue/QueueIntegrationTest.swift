@testable import CioInternalCommon
@testable import CioTracking
import Foundation
import SharedTests
import XCTest

class QueueIntegrationTest: IntegrationTest {
    private var queue: Queue!
    private var queueStorage: QueueStorage!

    override func setUp() {
        super.setUp()

        queue = diGraph.queue // Since this is an integration test, we want real instances in our test.
        queueStorage = diGraph.queueStorage
    }

    #if !os(Linux) // LINUX_DISABLE_FILEMANAGER
    func test_addTask_expectSuccessfullyAdded() {
        let addTaskActual = queue.addTask(
            type: String.random,
            data: ["foo": "bar"],
            groupStart: .identifiedProfile(identifier: String.random),
            blockingGroups: [.identifiedProfile(identifier: String.random)]
        )
        XCTAssertTrue(addTaskActual.success)
        XCTAssertEqual(addTaskActual.queueStatus.numTasksInQueue, 1)
    }

    func test_addTaskThenRun_expectToRunTaskInQueueAndCallCallback() {
        httpRequestRunnerStub.queueSuccessfulResponse()

        _ = queue.addTask(
            type: QueueTaskType.identifyProfile.rawValue,
            data: IdentifyProfileQueueTaskData(identifier: String.random, attributesJsonString: nil),
            groupStart: .identifiedProfile(identifier: String.random),
            blockingGroups: [.identifiedProfile(identifier: String.random)]
        )

        let expect = expectation(description: "Expect to complete")
        queue.run {
            expect.fulfill()
        }

        waitForExpectations()
        XCTAssertEqual(httpRequestRunnerStub.requestCallsCount, 1)

        let expect2 = expectation(description: "Expect to complete")
        queue.run {
            expect2.fulfill()
        }

        waitForExpectations()
        // assert that we didn't run any tasks because there were not to run
        XCTAssertEqual(httpRequestRunnerStub.requestCallsCount, 1)
    }

    func test_givenRunQueueAndFailTasksThenRerunQueue_expectQueueRerunsAllTasksAgain() {
        let givenGroupForTasks = QueueTaskGroup.identifiedProfile(identifier: String.random)
        _ = queue.addTask(
            type: QueueTaskType.trackEvent.rawValue,
            data: TrackEventQueueTaskData(identifier: String.random, attributesJsonString: ""),
            groupStart: givenGroupForTasks
        )
        _ = queue.addTask(
            type: QueueTaskType.trackEvent.rawValue,
            data: TrackEventQueueTaskData(identifier: String.random, attributesJsonString: ""),
            blockingGroups: [givenGroupForTasks]
        )

        httpRequestRunnerStub.queueNoRequestMade()

        var expect = expectation(description: "Expect to complete")
        queue.run {
            expect.fulfill()
        }
        waitForExpectations()

        XCTAssertEqual(queueStorage.getInventory().count, 2)
        XCTAssertEqual(httpRequestRunnerStub.requestCallsCount, 1)

        httpRequestRunnerStub.queueSuccessfulResponse()
        httpRequestRunnerStub.queueSuccessfulResponse()

        expect = expectation(description: "Expect to complete")
        queue.run {
            expect.fulfill()
        }
        waitForExpectations()

        // expect all of tasks to run and run successfully
        XCTAssertEqual(queueStorage.getInventory().count, 0)
        XCTAssertEqual(httpRequestRunnerStub.requestCallsCount, 3)
    }

    func test_givenRunQueueAndFailWith400_expectTaskToBeDeleted() {
        _ = queue.addTask(
            type: QueueTaskType.trackEvent.rawValue,
            data: TrackEventQueueTaskData(identifier: String.random, attributesJsonString: "")
        )
        httpRequestRunnerStub.queueResponse(code: 400, data: "".data)

        waitForQueueToFinishRunningTasks(queue)

        XCTAssertEqual(queueStorage.getInventory(), [])
        XCTAssertEqual(httpRequestRunnerStub.requestCallsCount, 1)
    }

    func test_givenRunQueueAndFailWith400_expectNon400TasksNotToBeDeleted() {
        let givenIdentifier = String.random

        let givenIdentifyGroupForTasks = QueueTaskGroup.identifiedProfile(identifier: givenIdentifier)

        _ = queue.addTask(
            type: QueueTaskType.identifyProfile.rawValue,
            data: IdentifyProfileQueueTaskData(identifier: givenIdentifier, attributesJsonString: nil),
            groupStart: givenIdentifyGroupForTasks
        )
        httpRequestRunnerStub.queueSuccessfulResponse()

        _ = queue.addTask(
            type: QueueTaskType.trackEvent.rawValue,
            data: TrackEventQueueTaskData(
                identifier: givenIdentifier,
                attributesJsonString: ""
            ),
            blockingGroups: [givenIdentifyGroupForTasks]
        )
        httpRequestRunnerStub.queueResponse(code: 400, data: "".data)

        _ = queue.addTask(
            type: QueueTaskType.trackEvent.rawValue,
            data: TrackEventQueueTaskData(
                identifier: givenIdentifier,
                attributesJsonString: ""
            ),
            blockingGroups: [givenIdentifyGroupForTasks]
        )
        httpRequestRunnerStub.queueResponse(code: 404, data: "".data)

        let expectedTasksToNotDelete = queueStorage.getInventory().last

        waitForQueueToFinishRunningTasks(queue)

        XCTAssertEqual(queueStorage.getInventory(), [expectedTasksToNotDelete])
        XCTAssertEqual(httpRequestRunnerStub.requestCallsCount, 3)
    }
    #endif
}

// MARK: BQ migration to CDP tests

extension QueueIntegrationTest {
    func test_givenExistingBQTasks_expectMigrateToCdp() {
        class ComplexEncodableCustomAttributes: Encodable {
            let nested: Nested
            
            class Nested: Encodable {
                let foo: String
                let bar: String
                
                init(foo: String, bar: String) {
                    self.foo = foo
                    self.bar = bar
                }
            }
            
            init(nested: Nested) {
                self.nested = nested
            }
        }
        
        let complexAttributes = ComplexEncodableCustomAttributes(nested: ComplexEncodableCustomAttributes.Nested(foo: .random, bar: .random))
        let complexAttributesString = jsonAdapter.toJsonString(complexAttributes)!
        
        _ = queue.addTask(type: QueueTaskType.identifyProfile.rawValue, data: IdentifyProfileQueueTaskData(identifier: .random, attributesJsonString: complexAttributesString))
        
        // Imagine that this is the migration code that has been written inside of the SDK:
        queueStorage.getInventory().forEach { inventoryTask in
            let existingQueueTaskToMigrate = queueStorage.get(storageId: inventoryTask.taskPersistedId)!
            
            switch existingQueueTaskToMigrate.type {
                case QueueTaskType.identifyProfile.rawValue:
                let queueTaskData: IdentifyProfileQueueTaskData = jsonAdapter.fromJson(existingQueueTaskToMigrate.data)!
                
                /**
                 Here is where the problem lies. 
                 
                 Profile attributes are a JSON *string*. The CDP module expects that attributes are either a Codable data type or [String: Any] data type. So simply forwarding the atributes string to the CDP module is not as straightforward.
                 
                 The profile attributes JSON string is in a format that the CIO Track API expects. The CIO CDP API may expect the HTTP request body for attributes to be in a different format. That means that we might need to modify the attributes before forwarding the request to the CDP API.
                 
                 Possible solutions I can think of to fix this problem:
                 1. Maybe the CDP API's HTTP request body format for attributes is identical to the CIO Track API? So, we can simply keep the attibutes as a JSON string and send that string unmodified to the CDP API. My knowledge of the CDP API is limited so I am not sure if this is true.
                 
                 2. Swift does allow you to easily convert a JSON string into a [AnyHashable: Any] dictionary. Our JsonAdapter already has the code to do that. Then, we can convert [AnyHashable: Any] into [String: Any] easily because String is a Hashable. Once we convert the JSON into [String: Any] data type, we can provide that data type to the CDP module.
                                                   
                 The code sample below is an example of option 2 above.
                 */
                let profileAttributes: [AnyHashable: Any] = jsonAdapter.toDictionary(queueTaskData.attributesJsonString!.data)!
                
                DataPipelines.shared.identify(identifier: queueTaskData.identifier, attributes: convertToDictionary(profileAttributes))
                
            default: // not adding any more cases since to keep this example brief
                break
        }
    }
}


    // Function to convert [AnyHashable: Any] to [String: Any]
    func convertToDictionary(_ inputDict: [AnyHashable: Any]) -> [String: Any] {
        var stringKeyDict: [String: Any] = [:]

        for (key, value) in inputDict {
            if let keyString = key as? String {
                stringKeyDict[keyString] = value
            }
        }

        return stringKeyDict
    }
