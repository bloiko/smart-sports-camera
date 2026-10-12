# Smart Sports Camera: context for Claude

A phone-only "smart sports camera": a static wide video of a game becomes a broadcast-style video that follows play; later a live stream to YouTube from an iPhone or Android phone. The owner is a senior Java developer in Ukraine building this solo with Claude, about 1 hour a day, on a zero budget until the prototype convinces.

## Start of every session

1. Read `specs/status.md` (where each phase stands) and `specs/backlog.md` (what to do next).
2. Read the relevant stable docs in `docs/` only when needed: `phases.md` for a phase's requirements and exit criteria, `architecture.md` for the pipeline, `testing-strategy.md` before evaluating anything.
3. The owner talks in Ukrainian; answer in Ukrainian. **All repository documentation is written in English.**

## End of every session (or after any meaningful result)

Follow `.claude/skills/project-docs/SKILL.md`: update `specs/` (status, results, backlog, datasets), add new commands to `README.md`, append decisions to `docs/decisions.md`, then commit and push.

## Working rules learned so far

- Test every model change on a match it has never seen and on the held-out last 20% of each video.
- Look at the output, not just metrics: contact sheets of detections and labels, frames from rendered videos.
- Long steps must be resumable (append output, restart from the last frame): commands can be killed after ~10 minutes and sessions can restart.
- Never commit videos or intermediate data; `.gitignore` covers them.
- Ultralytics YOLO is AGPL; plan for an Apache-2.0 detector before any closed release.
- Shots and goals must never leave the frame: run `src/check_goals.py` on every checklist in `specs/checklists/` and compare frames of old and new versions with `src/compare_crops.py`. Add every moment the owner reports to the checklist.
- Owner's product rules: the user never marks anything by hand (find it automatically); prefer our own computation over third-party models or services with their own licences.
- Compare camera versions on identical inputs; use `follow.py --no-render` for metrics and `--range` for quick renders.
- The pipeline runs on the owner's M1 Mac (MPS); videos are in `~/Downloads`, working data in `work/mN/` (git-ignored).
- Live is the main product line (phase 3 = Follo iOS app). The live camera is validated on recorded videos with `src/live_sim.py` (buffer 2 s); the Swift port must match it. Edge-case checklist with status: `docs/live-edge-cases.md`; mark items there when done.
- Swift code in `ios/` is written without Xcode on this Mac; the owner compiles it. Keep files small and plain so build errors are easy to fix from a pasted message.
