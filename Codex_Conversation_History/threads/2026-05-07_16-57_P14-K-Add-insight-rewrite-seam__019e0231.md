# P14_K: Add insight rewrite seam

- Thread ID: 019e0231-acb1-7660-ab93-2e14f23185d3
- Created: 2026-05-07 16:57:50 (Asia/Kolkata)
- Updated: 2026-05-07 17:09:16 (Asia/Kolkata)
- Archived: no
- Workspace: /Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe
- Source rollout: /Users/satvik.bansal/.codex/sessions/2026/05/07/rollout-2026-05-07T16-57-50-019e0231-acb1-7660-ab93-2e14f23185d3.jsonl
- Git branch at thread start: main
- Git SHA at thread start: a8305d617f2abab60b3b8df7bd7426bfdc252375
- Exported visible messages: 14
- Extracted input images: 0

## Conversation

### User - 2026-05-07 16:57:59

TASK
The plan doc envisions an LLM rewrite pass once deterministic insights are good. Today
there is no clean seam, so retrofitting later will be expensive.

GOAL
Add the seam without enabling any LLM call. Behavior is unchanged unless a feature
flag is on.

DESIGN
1. Add `func toLLMContext() -> InsightLLMContext` on AIInsight, returning a Codable
   struct with: dedupeKey, type, severity, action, exerciseDisplayName,
   evidenceRefsJSON, deterministicHeadline, deterministicMessage,
   coachPersonality, profileGoal, profileLimitations, sanitizationBlocklist.
2. Add protocol `InsightRewriter`:
     func rewrite(_ context: InsightLLMContext) async throws -> RewriteResult?
   Default impl is `NoopInsightRewriter` (returns nil). Wire `InsightEngine` to
   optionally take an `InsightRewriter`. If a rewrite returns non-nil, validate it
   through `sanitize()` and fields-must-still-cover-evidence guard before adopting.
3. Add `FeatureFlag.coachInsightLLMRewrite` (default off). When off, the
   NoopInsightRewriter is used and no behavior changes.

CONSTRAINTS
- Zero network calls in the default build.
- Add a `RewriteValidator` that rejects any rewrite that omits the exercise mention,
  the recommended action verb, or the evidence-anchored fact.

ACCEPTANCE
- All existing InsightEngineTests pass.
- A new test plugs in a stub rewriter that returns a sanitized headline, validates the
  insight is rewritten when the flag is on.
- A test asserting the noop path is byte-identical to current behavior.

### Assistant - 2026-05-07 16:58:06

I’ll map the insight pipeline and tests first, then make the seam as narrow as possible around the existing output path. After that I’ll run the relevant test target so we can catch any behavioral drift.

### Assistant - 2026-05-07 16:58:15

The main insight models and narrative builder are where the seam belongs; I’m checking the engine signatures now because the async rewrite protocol has to fit without turning the whole app upside down.

### Assistant - 2026-05-07 16:58:40

There isn’t an existing feature flag type, so this change needs a tiny local flag surface too. I’m also checking whether the Xcode project requires explicit file registration before adding new Swift files.

### Assistant - 2026-05-07 17:02:05

I’ve got the shape now: keep today’s synchronous insight API intact, and add async overloads on the same engine methods for the future rewrite path. That gives the LLM seam a real place to plug in without forcing UI behavior to change while the flag is off.

### Assistant - 2026-05-07 17:03:10

Next I’m wiring the async rewrite overloads into `InsightEngine`. The synchronous methods stay as today’s deterministic path; the async overloads generate the same insights first, then try the rewrite pass only through the configured flag/rewriter pair.

### Assistant - 2026-05-07 17:04:40

I’m adding the acceptance tests now: one proves the flag-on stub can rewrite through the sanitizer/validator, and one compares encoded insight output with the flag-off path so we know the no-op route is byte-identical.

### Assistant - 2026-05-07 17:05:19

The code is in place; I’m going to let Xcode compile it now, then run the insight test suite. If simulator selection gets picky, I’ll adjust to an available destination rather than guessing.

### Assistant - 2026-05-07 17:05:50

The app target compiled; the first failure is in the new tests where Swift picked the async overload in a couple of places that were meant to be deterministic sync calls. I’m tightening those call sites so the compiler has no ambiguity.

### Assistant - 2026-05-07 17:06:51

The build has moved past compilation and is sitting in the simulator test run now. No failures have surfaced in the latest output; I’m waiting for the test runner to flush the actual results.

### Assistant - 2026-05-07 17:07:14

`InsightEngineTests` are green, including the new rewrite tests. I’m doing one last diff pass now to make sure the files read cleanly and there aren’t accidental broad edits.

### Assistant - 2026-05-07 17:07:44

I made one small cleanup after the green run: removed a stored flag copy that was only needed during initialization. I’m rerunning the same test slice once more so the final state is verified.

### Assistant - 2026-05-07 17:08:26

The rerun is again past build and waiting on the simulator. It’s quiet in the usual slightly unnerving Xcode way, but still active.

### Assistant - 2026-05-07 17:09:15

Implemented the rewrite hook with default no-op behavior.

What changed:
- Added `InsightLLMContext` and `AIInsight.toLLMContext()` in [AIInsightModels.swift](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/VirtualTrainer/Models/AIInsightModels.swift:216).
- Added `FeatureFlag.coachInsightLLMRewrite`, default off, in [FeatureFlags.swift](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/VirtualTrainer/Services/FeatureFlags.swift:3).
- Added `InsightRewriter`, `NoopInsightRewriter`, `RewriteResult`, and `RewriteValidator` in [InsightRewriter.swift](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/VirtualTrainer/Services/InsightRewriter.swift:19).
- Wired async `InsightEngine` overloads to attempt rewrite only through the flag-controlled rewriter, with sanitizer plus evidence/action/exercise validation before adopting in [InsightEngine.swift](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/VirtualTrainer/Services/InsightEngine.swift:10).
- Added tests for flag-on rewrite, byte-identical no-op behavior, and rejection when evidence is omitted in [InsightEngineTests.swift](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/VirtualTrainerTests/InsightEngineTests.swift:834).

Verification:
`xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -only-testing:VirtualTrainerTests/InsightEngineTests`

Result: passed. No network calls were added; default build uses `NoopInsightRewriter`.
