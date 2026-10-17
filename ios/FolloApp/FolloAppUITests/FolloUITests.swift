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
    /// After 60 s without a touch the live screen dims and the first touch only wakes it (on purpose): wake it first.
    func wake() { let d = app.descendants(matching: .any)["dimmed"]; if d.exists { d.tap(); RunLoop.current.run(until: Date().addingTimeInterval(0.7)) } }
    /// Nothing may stick out of the screen (found 2026-10-17: the score panel was wider than an iPhone in portrait).
    func allInsideScreen(_ what: String) {
        let w = app.windows.firstMatch.frame
        for b in app.buttons.allElementsBoundByIndex where b.exists && b.frame.width > 0 && b.frame.minY < w.maxY && b.frame.maxY > w.minY {
            XCTAssertLessThanOrEqual(b.frame.maxX, w.maxX + 1, "\(what): '\(b.label)' sticks out on the right (\(b.frame))")
            XCTAssertGreaterThanOrEqual(b.frame.minX, w.minX - 1, "\(what): '\(b.label)' sticks out on the left (\(b.frame))")
        }
    }
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
        if !go.isEnabled {                                                   // position check still running: grey, no action
            shot("01 waiting for the pitch")
            XCTAssertEqual(go.label, "Перевіряю поле…")
        }
        wait("pitch found", timeout: 300) { go.isEnabled }
        shot("02 pitch found")
        go.tap()
        wait("LIVE", timeout: 20) { self.title == "LIVE" }
        let mute = app.buttons["mute"]
        XCTAssertTrue(mute.waitForExistence(timeout: 5))
        XCTAssertEqual(mute.label, "Звук вимкнено", "test run: the stream must start muted")
        shot("03 live, muted")
        allInsideScreen("live screen")
        mute.tap(); XCTAssertEqual(mute.label, "Звук")
        mute.tap(); XCTAssertEqual(mute.label, "Звук вимкнено")

        app.swipeUp(); shot("04 scrolled down")
        let stop = app.descendants(matching: .any)["stop"]
        XCTAssertTrue(stop.isHittable, "STOP must stay reachable")
        app.swipeDown(); shot("05 scrolled up")

        wake(); stop.tap(); stays("LIVE", 3)                                 // a tap is not a stop
        wake(); stop.press(forDuration: 1.5)
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
        let which = cells.firstMatch.label                                // date, duration, clips: this match
        shot("10 matches before")
        // swipe the list cell itself, slowly, up to 3 times (a fast swipe on the link inside sometimes did nothing)
        let cell = app.cells.containing(.button, identifier: "match").firstMatch, del = app.buttons["Видалити"]
        for _ in 0..<3 where !del.exists { cell.swipeLeft(velocity: .slow); _ = del.waitForExistence(timeout: 2) }
        shot("10b swipe actions")
        del.tap()
        app.buttons["Видалити матч"].tap()
        // the list loads rows lazily, so the count of visible rows can stay the same: check this match is gone
        wait("match deleted", timeout: 5) { !self.app.buttons.matching(NSPredicate(format: "label == %@", which)).firstMatch.exists }
        shot("11 match deleted")
    }

    // ---------------------------------------------------------------- YouTube (src/fake_youtube.py on 127.0.0.1:8765)

    let fake = "http://127.0.0.1:8765"
    func fakeLog() -> [[String: Any]] {
        let d = try? Data(contentsOf: URL(string: fake + "/_log")!)
        return (d.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] }) ?? []
    }
    func relaunchWithFakeYouTube() {
        app.terminate()
        app.launchArguments = ["--autostart", "--video", "m2.mp4", "--streamer", "follo", "--youtube-api", fake]
        app.launch()
    }
    func goLiveWhenReady() {
        let go = app.buttons["goLive"]
        wait("pitch found", timeout: 300) { go.exists && go.isEnabled }
        go.tap()
        wait("LIVE", timeout: 30) { self.title == "LIVE" }
    }

    /// Stage 1: broadcasts start unlisted with a link; a debug build cannot go public; visibility switches during the
    /// match; a restart of the app mid-match keeps the same broadcast (same link); STOP ends it.
    func test3_YouTubeUnlistedSameLink() throws {
        var r = URLRequest(url: URL(string: fake + "/_reset")!); r.httpMethod = "POST"
        _ = try? Data(contentsOf: URL(string: fake + "/_log")!)                      // server is up?
        let sem = DispatchSemaphore(value: 0); URLSession.shared.dataTask(with: r) { _, _, _ in sem.signal() }.resume(); sem.wait()
        relaunchWithFakeYouTube()

        XCTAssertTrue(app.staticTexts["YouTube: Test channel"].waitForExistence(timeout: 15), "signed in, channel shown")
        let picker = app.segmentedControls["privacyPicker"]
        XCTAssertTrue(picker.exists)
        XCTAssertTrue(picker.buttons["Не для всіх"].isSelected, "default: unlisted")
        XCTAssertFalse(app.buttons["Для всіх"].exists, "a test build offers no public option")
        shot("20 signed in, unlisted")

        goLiveWhenReady()
        let link = app.staticTexts["watchURL"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        let url1 = link.label
        XCTAssertTrue(url1.hasPrefix("https://youtu.be/"), url1)
        XCTAssertEqual(app.staticTexts["privacy"].label, "Не для всіх")
        shot("21 live unlisted with link")
        app.buttons["Зробити приватним"].tap()
        wait("private", timeout: 10) { self.app.staticTexts["privacy"].label == "Приватне" }
        app.buttons["Зробити «Не для всіх»"].tap()
        wait("unlisted again", timeout: 10) { self.app.staticTexts["privacy"].label == "Не для всіх" }
        XCTAssertFalse(app.buttons.containing(NSPredicate(format: "label CONTAINS 'Для всіх»…'")).firstMatch.exists, "no public switch in a test build")

        // the app is killed mid-match (crash, iOS, owner): GO LIVE again must continue the same broadcast
        relaunchWithFakeYouTube()
        goLiveWhenReady()
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        XCTAssertEqual(link.label, url1, "same link after a restart")
        shot("22 after restart, same link")

        wake(); app.descendants(matching: .any)["stop"].press(forDuration: 1.5)
        let done = app.buttons["resultDone"]
        XCTAssertTrue(done.waitForExistence(timeout: 10)); done.tap()

        let id = String(url1.dropFirst("https://youtu.be/".count))
        wait("broadcast ended", timeout: 10) {
            self.fakeLog().contains { ($0["path"] as? String) == "/youtube/v3/liveBroadcasts/transition" && (($0["query"] as? [String: String])?["id"]) == id }
        }
        let log = fakeLog()
        let inserts = log.filter { ($0["path"] as? String) == "/youtube/v3/liveBroadcasts" && ($0["method"] as? String) == "POST" }
        XCTAssertEqual(inserts.count, 1, "one broadcast for the whole match")
        let body = String(data: try JSONSerialization.data(withJSONObject: log), encoding: .utf8)!
        XCTAssertFalse(body.contains("\"public\""), "a test build never sends public")
        XCTAssertTrue(body.contains("\"enableAutoStop\":false"), "auto stop off: a drop does not end the broadcast")
        shot("23 stopped")
    }

    func fakePost(_ path: String) {
        var r = URLRequest(url: URL(string: fake + path)!); r.httpMethod = "POST"
        let sem = DispatchSemaphore(value: 0); URLSession.shared.dataTask(with: r) { _, _, _ in sem.signal() }.resume(); sem.wait()
    }

    /// Owner (2026-10-17): a YouTube error must never stop the recording. YouTube fails 3 times: recording and the
    /// camera start at once, the stream connects by itself on a later attempt. The broadcast is named after the match.
    func test4_RecordingDoesNotWaitForYouTube() {
        fakePost("/_reset"); fakePost("/_fail?n=3")
        relaunchWithFakeYouTube()
        goLiveWhenReady()                                                   // LIVE = recording started, before YouTube answered
        let status = app.staticTexts["status"]
        wait("retry message", timeout: 15) { status.label.contains("пробую ще раз") }
        shot("30 recording, YouTube failing")
        let link = app.staticTexts["watchURL"]
        XCTAssertTrue(link.waitForExistence(timeout: 60), "the stream connects by itself after YouTube recovers")
        shot("31 connected after retries")
        let inserts = fakeLog().filter { ($0["path"] as? String) == "/youtube/v3/liveBroadcasts" && ($0["method"] as? String) == "POST" }
        let title = ((inserts.last?["body"] as? [String: Any])?["snippet"] as? [String: Any])?["title"] as? String ?? ""
        XCTAssertTrue(title.hasPrefix("Матч ") || title.contains(" – "), "title from the match, not 'Follo …': \(title)")
        wake(); app.descendants(matching: .any)["stop"].press(forDuration: 1.5)
        let done = app.buttons["resultDone"]
        XCTAssertTrue(done.waitForExistence(timeout: 10)); done.tap()
    }

    /// Owner (2026-10-17): find out at home, not at GO LIVE, that the Google sign-in ran out (7 days in Testing).
    func test5_SignInExpiredBanner() {
        fakePost("/_reset"); fakePost("/_revoke")
        app.terminate()
        app.launchArguments = ["--skip-onboarding", "--video", "m2.mp4", "--streamer", "follo", "--youtube-api", fake]   // no --autostart: "Мої матчі"
        app.launch()
        XCTAssertTrue(app.staticTexts["signInBanner"].waitForExistence(timeout: 15), "expired sign-in shown on launch")
        XCTAssertTrue(app.buttons["signInAgain"].exists)
        XCTAssertTrue(app.staticTexts["build"].exists, "build time shown")
        shot("40 sign-in expired banner")
    }

    /// On the tripod the phone is horizontal (owner, 2026-10-17): preview on the left, controls on the right; GO LIVE,
    /// STOP, mute and the score must all be reachable without rotating the phone.
    func test6_Landscape() {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let go = app.buttons["goLive"]
        XCTAssertTrue(go.waitForExistence(timeout: 10))
        let win = app.windows.firstMatch.frame
        XCTAssertGreaterThan(win.width, win.height, "the app must rotate to landscape (window \(win.size))")
        shot("50 landscape, checking")
        wait("pitch found", timeout: 300) { go.isEnabled }
        XCTAssertTrue(go.isHittable, "GO LIVE visible in landscape")
        shot("51 landscape, ready")
        go.tap()
        wait("LIVE", timeout: 20) { self.title == "LIVE" }
        let stop = app.descendants(matching: .any)["stop"], mute = app.buttons["mute"]
        XCTAssertTrue(stop.isHittable, "STOP visible in landscape")
        XCTAssertTrue(mute.waitForExistence(timeout: 5) && mute.isHittable, "mute visible in landscape")
        shot("52 landscape, live")
        allInsideScreen("landscape live")
        let plus = app.buttons.matching(identifier: "plus").firstMatch
        if !plus.isHittable { app.swipeUp() }
        shot("53 landscape, live, scrolled")
        wake(); stop.press(forDuration: 1.5)
        let done = app.buttons["resultDone"]
        XCTAssertTrue(done.waitForExistence(timeout: 10)); shot("54 landscape, result"); done.tap()
        wait("ready after STOP", timeout: 5) { self.title == "Готово до гри" }
    }

    /// Owner (2026-10-17): half-time card in the stream; camera, recording and detection off; second half resumes all.
    func test7_HalfTime() {
        fakePost("/_reset")
        relaunchWithFakeYouTube()
        goLiveWhenReady()
        let start = app.buttons["breakStart"]
        if !start.isHittable { app.swipeUp() }
        XCTAssertTrue(start.waitForExistence(timeout: 5)); start.tap()
        XCTAssertTrue(app.staticTexts["breakOn"].waitForExistence(timeout: 5), "break panel shown")
        XCTAssertEqual(title, "LIVE", "still live during the break")
        shot("60 half-time")
        allInsideScreen("half-time")
        RunLoop.current.run(until: Date().addingTimeInterval(8))           // ~80 card frames into the stream
        let end = app.buttons["breakEnd"]
        if !end.isHittable { app.swipeUp() }
        end.tap()
        wait("break over", timeout: 5) { !self.app.staticTexts["breakOn"].exists }
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH '2Т'")).firstMatch.waitForExistence(timeout: 5), "second half on the clock")
        shot("61 second half")
        RunLoop.current.run(until: Date().addingTimeInterval(5))
        wake(); app.descendants(matching: .any)["stop"].press(forDuration: 1.5)
        let done = app.buttons["resultDone"]
        XCTAssertTrue(done.waitForExistence(timeout: 10)); done.tap()
    }
}
