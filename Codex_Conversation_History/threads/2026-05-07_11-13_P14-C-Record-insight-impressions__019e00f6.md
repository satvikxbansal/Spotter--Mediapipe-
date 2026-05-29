# P14_C: Record insight impressions

- Thread ID: 019e00f6-dc64-7dc0-b187-322ca213a651
- Created: 2026-05-07 11:13:58 (Asia/Kolkata)
- Updated: 2026-05-07 11:29:16 (Asia/Kolkata)
- Archived: no
- Workspace: /Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe
- Source rollout: /Users/satvik.bansal/.codex/sessions/2026/05/07/rollout-2026-05-07T11-13-58-019e00f6-dc64-7dc0-b187-322ca213a651.jsonl
- Git branch at thread start: main
- Git SHA at thread start: a8305d617f2abab60b3b8df7bd7426bfdc252375
- Exported visible messages: 19
- Extracted input images: 0

## Conversation

### User - 2026-05-07 11:14:23

Before changing code:
1. Deeply inspect the current repo structure.
2. Read the relevant files before editing.
3. Treat this prompt as the implementation reference, not a blind spec. If the codebase reveals a better engineering decision, make it and explain why.
4. Do not rewrite MediaPipe, CameraManager, PoseEstimator, UniversalRepCounter, FormFeedbackEngine, HandGestureDetector, ExertionAnalyzer, or the core live camera pipeline unless absolutely necessary.
5. Preserve both live flows:
   - Camera tab free analysis
   - Planned workout sessions
6. Keep UI functional and simple for now. Do not do the final visual design-system revamp unless explicitly requested.
7. Keep business logic out of SwiftUI views wherever practical.
8. Keep existing local-first behavior.
9. Do not store or upload raw camera frames, raw video, face images, raw pose streams, or raw biometric face data.
10. Do not print or expose secret values.
11. Keep the app compiling after the phase.
12. Run available tests/build commands and summarize results.
13. Summarize changed files, key decisions, and known follow-up items.
14. Share an end to end manual testing plan of the changes done
15. Post building, Review the implementation and suggest ways to expand and deepen this coaching engine. Implement the highest leverage ones ensuring the code is stable and does not break existing functionalities. 
TASK
In the Spotter AI iOS codebase, the AI Coach Insight cooldown is currently consumed at
data-load time, not when the insight is actually shown to the user. This silently hides
high-value insights on Dashboard and Profile because `selectInsights(..., markPresented: true)`
runs every time the surface refreshes, even if the user never sees the result.

GOAL
1. Stop marking insights as "presented" inside `InsightStore.selectInsights`. Add a
   separate `recordImpression(_ insight: AIInsight, on surface: InsightSurface, now:)`
   method that the UI calls from each insight card's `onAppear`.
2. Bypass the cooldown for `severity == .important` insights so safety-tier alerts
   always re-surface on the relevant screen.
3. Add a tap signal: `recordEngagement(_ insight: AIInsight, kind: InsightEngagementKind)`
   where `InsightEngagementKind` ∈ {.opened, .dismissed, .helpful, .notHelpful}. Persist
   per-insight engagement counts in the JSON snapshot (extend
   `PersistedInsightStoreSnapshot` with backward-compatible decoding).
4. Boost ranking by engagement: in `InsightRanker.score`, add +6 if the candidate's
   dedupeKey has at least one `.helpful` engagement, −12 if `.notHelpful`,
   −20 if `.dismissed` within the last 7 days.

WHERE
- Models/InsightStore.swift  (split selectInsights → fetchCandidates + recordImpression)
- Services/InsightRanker.swift  (new engagement-aware scoring)
- UI/HomeDashboardView.swift, UI/ProfileView.swift, UI/WorkoutSummaryView.swift,
  UI/WorkoutPreviewView.swift  (call recordImpression on .onAppear of each insight card,
  add a discreet "Was this helpful?" pair on the long-form variants)
- Tests/InsightStoreTests.swift, InsightEngineTests.swift
  (add tests proving cooldown advances on impression, important severity bypasses
  cooldown, engagement is persisted)

CONSTRAINTS
- Do NOT change any rule strictness or cue thresholds.
- Backward-compatible JSON: old snapshot must still decode.
- Keep `nonisolated` annotations.

ACCEPTANCE
- A test that calls selectInsights 5 times on the dashboard surface (without onAppear)
  must still return the same insight 5 times.
- A test that records an impression then calls selectInsights within 18h must return a
  different insight (or empty if none qualify).
- A test that creates an `.important` severity insight, records an impression, and
  immediately re-fetches the same surface returns the same insight again.

### Assistant - 2026-05-07 11:14:30

I’ll inspect the repo first and trace the insight flow before touching anything. I’ll keep the existing camera/workout pipeline out of scope and focus this phase around store/ranking/UI call sites plus tests.

### Assistant - 2026-05-07 11:14:40

The repo is a native iOS app with a clean separation already: `Models`, `Services`, `UI`, plus test coverage under `VirtualTrainerTests`. I also see one untracked markdown file already present; I’ll leave that alone unless it becomes relevant.

### Assistant - 2026-05-07 11:14:53

I’ve found the current coupling: `selectInsights` both filters/ranks and writes delivery records. The better split is exactly around the store boundary, with UI impression calls as the write trigger and ranking receiving read-only engagement history.

### Assistant - 2026-05-07 11:17:56

I’m going to make a narrow model/service change first: keep `selectInsights` as a read/select operation, move delivery writes into `recordImpression`, and add a compact local engagement record keyed by `dedupeKey`. Then I’ll wire the four UI surfaces to impression/helpfulness callbacks.

### Assistant - 2026-05-07 11:18:45

The store split is in place now, including backward-compatible snapshot decoding. Next I’m updating the ranker so engagement history is just another scoring input, with defaults that preserve existing call sites and tests.

### Assistant - 2026-05-07 11:19:08

I’m threading the engagement snapshot through the insight engine now. That matters because the engine trims candidates before the store sees them, so the ranking signal has to be available at generation time too.

### Assistant - 2026-05-07 11:19:58

I’m adding one small reusable SwiftUI control for the helpful/not-helpful pair so the four screens don’t each grow their own button logic. The actual persistence stays in `InsightStore`.

### Assistant - 2026-05-07 11:20:06

Now I’m wiring impressions at the actual card boundary. Dashboard remains short-form, so it only records an impression when the insight card appears; the helpful prompt stays off that compact card.

### Assistant - 2026-05-07 11:20:47

Profile uses the fuller insight copy, so I’m adding both impression recording and the discreet helpful/not-helpful signal there. The card still owns only UI; the store owns the behavior.

### Assistant - 2026-05-07 11:21:03

I’m doing the same for workout preview. This is a good fit for helpfulness because “why this plan” is explanatory coaching, and the feedback should influence future plan insight ordering.

### Assistant - 2026-05-07 11:21:37

Workout summary is the other long-form surface. I’m adding the same impression and helpfulness hooks there, while keeping the existing fallback summary text untouched for cases without a generated insight.

### Assistant - 2026-05-07 11:22:43

I’m updating the tests to lock the new behavior: selection is repeatable until an actual impression, important insights bypass cooldown, and engagement records survive a reload plus old snapshots still decode.

### Assistant - 2026-05-07 11:25:18

The core wiring is done. I’m going to build/test now; if Swift catches anything from the new Codable model or view wiring, I’ll fix that before doing the final review pass.

### Assistant - 2026-05-07 11:25:52

The test run is still moving through the iOS simulator build. So far it has compiled dependencies and is into the app target; I’m waiting on Swift/test results rather than guessing from partial output.

### Assistant - 2026-05-07 11:27:30

One review pass caught a subtle SwiftUI lifecycle edge: if an insight changes while the card is already visible, `onAppear` may not fire again unless the card identity changes. I’m adding stable `.id(...)` anchors to the non-list cards so impressions track the displayed insight, not just the first mount.

### Assistant - 2026-05-07 11:27:45

That lifecycle fix is tiny but worthwhile. I’m rerunning the suite after it so the final state, not the pre-review state, is what we trust.

### Assistant - 2026-05-07 11:28:50

The rerun passed. I’m doing one last repo diff/status check now so I can give you a precise changed-file summary and a grounded manual test plan.

### Assistant - 2026-05-07 11:29:16

Implemented and verified. I left the MediaPipe/live camera pipeline untouched.

Changed:
- [InsightStore.swift](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/VirtualTrainer/Models/InsightStore.swift): `selectInsights` no longer consumes cooldown. Added `recordImpression`, `recordEngagement`, important-severity cooldown bypass, and backward-compatible engagement persistence.
- [InsightRanker.swift](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/VirtualTrainer/Services/InsightRanker.swift): added engagement-aware scoring: helpful `+6`, notHelpful `-12`, recent dismissed `-20`.
- [InsightEngine.swift](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/VirtualTrainer/Services/InsightEngine.swift): threads engagement records into ranking before candidate trimming.
- Dashboard, Profile, Workout Preview, Workout Summary: insight cards now record impressions on actual appearance. Long-form cards get a discreet helpful/not-helpful prompt.
- Added [InsightEngagementControls.swift](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/VirtualTrainer/UI/InsightEngagementControls.swift).
- Added [InsightStoreTests.swift](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/VirtualTrainerTests/InsightStoreTests.swift) and updated [InsightEngineTests.swift](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/VirtualTrainerTests/InsightEngineTests.swift).

Key decisions:
- Kept selection and presentation separate. This fixes the silent Dashboard/Profile starvation without weakening cooldown once the user actually sees an insight.
- Important safety-tier insights bypass cooldown but still record impressions for history.
- Engagement is local-only JSON metadata keyed by `dedupeKey`; no raw camera, pose stream, face, or biometric data is stored.
- Post-build review improvement implemented: non-list insight cards now use stable `.id(...)` anchors so a changed visible insight gets a fresh `onAppear`.

Verification:
- Ran `xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2'`
- Result: `** TEST SUCCEEDED **`

Manual test plan:
1. Launch app with existing local data and confirm Dashboard/Profile load without persistence errors.
2. Refresh Dashboard repeatedly without scrolling/seeing a new card lifecycle; same eligible insight should not disappear just from refresh.
3. Let a Dashboard insight appear, then refresh within 18h; it should rotate away or go empty unless it is `.important`.
4. Generate/view Profile, Workout Preview, and Workout Summary insights; confirm cards appear and helpful/not-helpful buttons respond.
5. Tap helpful/not-helpful, relaunch app, and verify the app still loads insights normally.
6. Complete a planned workout end to end and confirm Workout Summary still appears, history saves, trophies update, and the planned live flow is intact.
7. Use Camera tab free analysis and confirm the free live flow still starts and summarizes normally.

Good next expansions:
- Add explicit dismiss affordances to long-form insights so `.dismissed` becomes a real user signal.
- Add an “opened” signal via a lightweight insight detail sheet.
- Add per-surface engagement decay so old helpful/not-helpful signals gradually fade instead of staying flat forever.
