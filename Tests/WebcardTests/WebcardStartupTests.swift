import AppKit
import XCTest
@testable import Webcard

final class WebcardStartupTests: XCTestCase {
    func testSingleDocumentWindowDefaultsTo550PointSquare() {
        XCTAssertEqual(WebcardDocumentWindowMetrics.defaultWidth, 550)
        XCTAssertEqual(WebcardDocumentWindowMetrics.defaultHeight, 550)
        XCTAssertEqual(WebcardDocumentWindowMetrics.minimumWidth, 360)
        XCTAssertEqual(WebcardDocumentWindowMetrics.minimumHeight, 420)
    }

    @MainActor
    func testStartWindowIsOnlyEligibleForDirectAppLaunch() {
        let directLaunch = Notification(
            name: NSApplication.didFinishLaunchingNotification,
            userInfo: [NSApplication.launchIsDefaultUserInfoKey: true]
        )
        let documentLaunch = Notification(
            name: NSApplication.didFinishLaunchingNotification,
            userInfo: [NSApplication.launchIsDefaultUserInfoKey: false]
        )

        XCTAssertTrue(WebcardAppDelegate.isDefaultLaunch(directLaunch))
        XCTAssertFalse(WebcardAppDelegate.isDefaultLaunch(documentLaunch))
    }

    @MainActor
    func testUntitledRequestIsHandledByReusingStartWindowWithoutCreatingDocument() {
        let application = NSApplication.shared
        let delegate = WebcardAppDelegate()
        let existingWindows = Set(application.windows.map(ObjectIdentifier.init))
        let existingDocuments = NSDocumentController.shared.documents
        defer {
            application.windows
                .filter { !existingWindows.contains(ObjectIdentifier($0)) }
                .forEach { $0.close() }
        }

        XCTAssertFalse(delegate.applicationShouldOpenUntitledFile(application))
        XCTAssertTrue(delegate.applicationOpenUntitledFile(application))

        let startWindows = application.windows.filter {
            !existingWindows.contains(ObjectIdentifier($0)) && $0.isVisible
        }
        XCTAssertEqual(startWindows.count, 1)
        XCTAssertEqual(startWindows.first?.title, "Webcard")

        XCTAssertTrue(delegate.applicationOpenUntitledFile(application))
        XCTAssertEqual(
            application.windows.filter {
                !existingWindows.contains(ObjectIdentifier($0)) && $0.isVisible
            },
            startWindows
        )
        XCTAssertEqual(NSDocumentController.shared.documents, existingDocuments)
    }
}
