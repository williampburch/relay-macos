import XCTest
@testable import Remote

final class KeychainServiceTests: XCTestCase {
    private var service: KeychainService!
    private var references: [String] = []

    override func setUp() {
        super.setUp()
        service = KeychainService(serviceIdentifier: "com.example.Remote.tests.\(UUID().uuidString)")
    }

    override func tearDown() {
        for reference in references {
            try? service.deletePassword(reference: reference)
        }
        service = nil
        references = []
        super.tearDown()
    }

    func testSaveAndRetrievePassword() throws {
        let reference = try service.savePassword("first-test-password")
        references.append(reference)

        XCTAssertFalse(reference.isEmpty)
        XCTAssertEqual(try service.password(reference: reference), "first-test-password")
    }

    func testSavingWithExistingReferenceUpdatesPassword() throws {
        let reference = try service.savePassword("old-test-password")
        references.append(reference)

        let updatedReference = try service.savePassword(
            "new-test-password",
            reference: reference
        )

        XCTAssertEqual(updatedReference, reference)
        XCTAssertEqual(try service.password(reference: reference), "new-test-password")
    }

    func testDeleteRemovesPasswordAndCanBeRepeated() throws {
        let reference = try service.savePassword("temporary-test-password")
        references.append(reference)

        try service.deletePassword(reference: reference)
        XCTAssertNil(try service.password(reference: reference))
        XCTAssertNoThrow(try service.deletePassword(reference: reference))
    }

    func testUnknownReferenceReturnsNil() throws {
        XCTAssertNil(try service.password(reference: UUID().uuidString))
    }
}
