import XCTest
@testable import VoiceApp

final class SessionStateFormatterTests: XCTestCase {
    func testIdleMapsToIdleCopy() {
        let line = SessionStateFormatter.statusLine(for: ConversationViewModel.SessionState.idle)
        XCTAssertEqual(line, VoiceStrings.UI.statusIdle)
    }

    func testConnectingMapsToConnectingCopy() {
        let line = SessionStateFormatter.statusLine(for: ConversationViewModel.SessionState.connecting)
        XCTAssertEqual(line, VoiceStrings.UI.statusConnecting)
    }

    func testErrorMapsToLocalizedDescription() {
        let err = AppError.tokenExpired
        let line = SessionStateFormatter.statusLine(for: ConversationViewModel.SessionState.error(err))
        XCTAssertEqual(line, err.localizedDescription)
    }
}
