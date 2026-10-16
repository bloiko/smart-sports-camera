import XCTest

/// UI checks on the simulator (stage 0 of docs/youtube-signin-and-ui-test-plan.md). The app runs the m2 test video
/// instead of the camera; `ios/ui_test.sh` copies it into the app before the run. Every step leaves a screenshot.
/// Each test guards a bug or an owner rule that was found by hand.
final class FolloUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--autostart", "--video", "m2.mp4", "--streamer", "follo"]
        app.launch()
        let ok = app.buttons["Зрозуміло"]                                   // "before the match" advice, first run only
        if ok.waitForExistence(timeout: 5) { ok.tap() }
    }

    func shot(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    var title: String { app.staticTexts["title"].label }
    func wait(_ what: String, timeout: Double, _ cond: @escaping () -> Bool) {
        let end = Date().addingTimeInterval(timeout)
        while !cond() { if Date() > end { shot("timeout " + what); XCTFail("timeout: \(what)"); return }; RunLoop.current.run(until: Date().addingTimeInterval(0.5)) }
    }
    /// The title must keep `text` for `seconds` (catches a broadcast that restarts on its own).
    func stays(_ text: String, _ seconds: Double) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { XCTAssertEqual(title, text); RunLoop.current.run(until: Date().addingTimeInterval(0.5)) }
    }

    /// Owner's rules: no broadcast before the pitch is found; sound off in tests. Bugs: STOP restarted the broadcast
    /// (2026-10-16), a tap on STOP must do nothing, every control must be reachable by scrolling.
    func test1_GoLiveAndStop() {
        let go = app.buttons["goLive"]
        XCTAssertTrue(go.waitForExistence(timeout: 10))
        // the simulator has no camera: without the test video the position check would wait forever
        let source = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Тестове відео'")).firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 15), "no test video in the app: run through ios/ui_test.sh")
        XCTAssertEqual(title, "Готово до гри")
        if !go.isEnabled {                                                   // position check still running
            shot("01 waiting for the pitch")
            go.tap(); stays("Готово до гри", 3)                              // disabled: no broadcast
        }
        wait("pitch found", timeout: 300) { go.isEnabled }
        shot("02 pitch found")
        go.tap()
        wait("LIVE", timeout: 20) { self.title == "LIVE" }
        let mute = app.buttons["mute"]
        XCTAssertTrue(mute.waitForExistence(timeout: 5))
        XCTAssertEqual(mute.label, "Звук вимкнено", "test run: the stream must start muted")
        shot("03 live, muted")
        mute.tap(); XCTAssertEqual(mute.label, "Звук")
        mute.tap(); XCTAssertEqual(mute.label, "Звук вимкнено")

        app.swipeUp(); shot("04 scrolled down")
        let stop = app.descendants(matching: .any)["stop"]
        XCTAssertTrue(stop.isHittable, "STOP must stay reachable")
        app.swipeDown(); shot("05 scrolled up")

        stop.tap(); stays("LIVE", 3)                                         // a tap is not a stop
        stop.press(forDuration: 1.5)
        let done = app.buttons["resultDone"]
        XCTAssertTrue(done.waitForExistence(timeout: 10), "the result sheet must open after STOP")
        shot("06 result")
        done.tap()
        wait("ready after STOP", timeout: 5) { self.title == "Готово до гри" }
        stays("Готово до гри", 6)                                            // the old bug: GO LIVE fired on release
        shot("07 stopped, not restarted")
    }

    /// Bug (2026-10-16): matches could not be deleted, only their 4K files.
    func test2_DeleteMatch() {
        let back = app.buttons["back"]
        XCTAssertTrue(back.waitForExistence(timeout: 10)); back.tap()
        let cells = app.descendants(matching: .any).matching(identifier: "match")
        guard cells.firstMatch.waitForExistence(timeout: 5) else { shot("no matches"); XCTFail("no matches to delete (test1 records one)"); return }
        let before = cells.count
        shot("10 matches before")
        cells.firstMatch.swipeLeft()
        app.buttons["Видалити"].tap()
        app.buttons["Видалити матч"].tap()
        wait("match deleted", timeout: 5) { cells.count == before - 1 }
        shot("11 match deleted")
    }
}
