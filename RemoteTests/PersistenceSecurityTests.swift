import SwiftData
import XCTest
@testable import Remote

final class PersistenceSecurityTests: XCTestCase {
    func testPersistentSchemaContainsOnlyAKeychainReferenceForCredentialSecrets() throws {
        let schema = Schema([
            Connection.self,
            ConnectionGroup.self,
            CredentialProfile.self
        ])
        let credentialEntity = try XCTUnwrap(
            schema.entities.first { $0.name == String(describing: CredentialProfile.self) }
        )
        let propertyNames = Set(credentialEntity.properties.map { $0.name })

        XCTAssertTrue(propertyNames.contains("keychainReference"))
        XCTAssertFalse(propertyNames.contains("password"))
        XCTAssertFalse(propertyNames.contains("secret"))
        XCTAssertFalse(propertyNames.contains("authenticationMaterial"))
        XCTAssertFalse(propertyNames.contains("privateKey"))
    }

    func testEveryPersistentEntityAvoidsSecretBearingPropertyNames() {
        let schema = Schema([
            Connection.self,
            ConnectionGroup.self,
            CredentialProfile.self
        ])
        let forbiddenTerms = ["password", "passphrase", "secret", "privatekey", "token"]

        for entity in schema.entities {
            for property in entity.properties {
                let normalizedName = property.name
                    .replacingOccurrences(of: "_", with: "")
                    .lowercased()
                XCTAssertFalse(
                    forbiddenTerms.contains { normalizedName.contains($0) },
                    "\(entity.name).\(property.name) must not persist authentication material"
                )
            }
        }
    }
}
