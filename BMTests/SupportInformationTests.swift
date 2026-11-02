import XCTest
@testable import BM

final class SupportInformationTests: XCTestCase {
    func testBundledFontLicenseCanBeReadInSupport() throws {
        let license = try XCTUnwrap(SupportInformation.fontLicense())
        XCTAssertTrue(license.contains("Eunbin Jeong"))
        XCTAssertTrue(license.contains("SIL OPEN FONT LICENSE Version 1.1"))
        XCTAssertTrue(license.contains("PERMISSION & CONDITIONS"))
        XCTAssertTrue(license.contains("DISCLAIMER"))
        XCTAssertGreaterThan(license.count, 4000)
    }
}
