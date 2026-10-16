#!/bin/sh
# Stage 0 UI tests on the simulator (docs/youtube-signin-and-ui-test-plan.md): build, install, copy the m2 test video,
# run FolloAppUITests, export the screenshots to work/ui/shots and the app log to work/ui/app_log.txt, shut the
# simulator down (it keeps the Mac's CPU busy while it runs). Never streams: the debug stream target and key are removed.
# Usage: ios/ui_test.sh [-only-testing:FolloAppUITests/FolloUITests/test1_GoLiveAndStop]
cd "$(dirname "$0")/FolloApp" || exit 1
SIM="${SIM:-iPhone 17}"
ROOT=$(cd ../.. && pwd); DD="$ROOT/work/sim-dd"; OUT="$ROOT/work/ui"
DEST="platform=iOS Simulator,name=$SIM"
xcrun simctl boot "$SIM" 2>/dev/null
xcodebuild -project FolloApp.xcodeproj -scheme FolloAppUITests -destination "$DEST" -derivedDataPath "$DD" build-for-testing -quiet || exit 1
xcrun simctl install "$SIM" "$DD/Build/Products/Debug-iphonesimulator/FolloApp.app" || exit 1
C=$(xcrun simctl get_app_container "$SIM" com.bohdanloiko.follo data)
mkdir -p "$C/Documents/testvideo" "$C/Documents/debug"
[ -f "$C/Documents/testvideo/m2.mp4" ] || cp "${M2:-$HOME/Downloads/132877.mp4}" "$C/Documents/testvideo/m2.mp4"
rm -f "$C/Documents/debug/rtmp_target.txt" "$C/Documents/debug/youtube_key.txt"
rm -rf "$OUT"; mkdir -p "$OUT"
# fake Google + YouTube for test3 (Apple's python: the firewall blocks Homebrew's)
/usr/bin/python3 "$ROOT/src/fake_youtube.py" --port 8765 > "$OUT/fake_youtube.txt" 2>&1 &
FAKE=$!
xcodebuild -project FolloApp.xcodeproj -scheme FolloAppUITests -destination "$DEST" -derivedDataPath "$DD" \
  -parallel-testing-enabled NO -resultBundlePath "$OUT/result.xcresult" test-without-building "$@" > "$OUT/xcodebuild.txt" 2>&1
grep -E "Test Case .*(passed|failed)|error:|XCTAssert" "$OUT/xcodebuild.txt"
xcrun xcresulttool export attachments --path "$OUT/result.xcresult" --output-path "$OUT/shots" >/dev/null 2>&1
C=$(xcrun simctl get_app_container "$SIM" com.bohdanloiko.follo data); cp "$C/Documents/debug/log.txt" "$OUT/app_log.txt" 2>/dev/null
kill $FAKE 2>/dev/null
xcrun simctl shutdown "$SIM"
if grep -q "TEST EXECUTE SUCCEEDED\|TEST SUCCEEDED" "$OUT/xcodebuild.txt"; then echo "UI TESTS PASSED (screenshots: work/ui/shots)"; else echo "UI TESTS FAILED (see work/ui/xcodebuild.txt, work/ui/shots)"; exit 1; fi
