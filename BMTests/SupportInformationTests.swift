import XCTest
@testable import BM

final class SupportInformationTests: XCTestCase {
    func testSupportContactOpensEmailComposerForConfiguredAddress() {
        XCTAssertEqual(SupportInformation.contactURL.scheme, "mailto")
        XCTAssertEqual(SupportInformation.contactURL.absoluteString, "mailto:" + SupportInformation.contactEmail)
        XCTAssertNil(SupportInformation.contactURL.query)
    }

    func testBundledFontLicenseCanBeReadInSupport() throws {
        let license = try XCTUnwrap(SupportInformation.fontLicense())
        XCTAssertTrue(license.contains("Eunbin Jeong"))
        XCTAssertTrue(license.contains("SIL OPEN FONT LICENSE Version 1.1"))
        XCTAssertTrue(license.contains("PERMISSION & CONDITIONS"))
        XCTAssertTrue(license.contains("DISCLAIMER"))
        XCTAssertGreaterThan(license.count, 4000)
    }
}
