# Streaming to YouTube from the Mac (test of the live mode)

`src/golive.py` imitates what the app will do: sign in with Google once, create a broadcast through the YouTube Live API, stream the live-camera crop over RTMPS, close the broadcast at the end. The user sees only the Google consent window and the broadcast link; stream keys are never shown or committed.

## One-time setup (about 5 minutes, free)

1. Open https://console.cloud.google.com and create a project (any name).
2. APIs & Services → Library → **YouTube Data API v3** → Enable.
3. APIs & Services → OAuth consent screen → External; app name and your e-mail; under **Test users** add the Google account that owns the YouTube channel.
4. Credentials → Create credentials → **OAuth client ID** → application type **Desktop app** → Create → Download JSON.
5. Save the file as `secrets/client_secret.json` (the `secrets/` folder is git-ignored).
6. Live streaming must be enabled on the channel (https://www.youtube.com/livestreaming); the first activation can take up to 24 hours.

## Run

```bash
python src/golive.py work/m1/game.mp4 work/m1/live/live_B2.npz --title "Smart camera test" --from 150
```

- First run opens the browser for consent; the token is stored in `secrets/token.json`.
- The script prints the `youtu.be` link; open it on a phone to see the delay and quality. The broadcast is unlisted by default (`--privacy public|private|unlisted`), starts automatically when data arrives and is closed when the script ends.
- `CAMERA_PATH.npz` comes from `src/live_sim.py` (buffer 2 s); `--from` is the start second of the video.
- Encoding: H.264 via VideoToolbox, 4.5 Mbit/s, keyframe every 2 s, AAC 128 kbit/s — YouTube's recommendations for 1080p30.

## In the app (phase 5)

The same flow on iOS: Google sign-in (OAuth), `liveBroadcasts.insert` + `liveStreams.insert` + `bind`, RTMPS via HaishinKit, broadcast link shared to the team chat. Requires the same Google Cloud project with the iOS OAuth client type.
