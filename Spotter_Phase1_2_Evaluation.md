# Spotter AI — Phase 1 & 2 Deep Evaluation

**Author:** Founder coach review
**Scope:** Phase 1 = Trends / Signals / AI Coach Insight Engine. Phase 2 = Trophies + Workout History.
**Method:** Read the entire engine code (TrendEngine, SignalExtractor, InsightEngine, InsightCandidateBuilder, InsightRanker, InsightNarrativeBuilder, InsightStore, StatsEngine, TrophyEngine, TrophyStore, WorkoutHistoryStore, all relevant Models + Views). Cross-checked against the GPT-5.5-Pro plan doc for intent.
**Bias:** Founder-PM-engineer hat. The bar is "best fitness app in the world." Strict-rules constraint respected — none of the changes below tighten the form-rule numbers.

---

## Part 1 — Trends, Signals & AI Coach Insights

### 1.1 How it's currently wired (one-paragraph mental model)

```
WorkoutHistoryStore (file-persisted [WorkoutSessionSummary])
        │
        ▼
TrendEngine.buildSnapshot(history, profile, trophies, now)
        │  → UserTrainingTrendSnapshot
        │      • streak, weeklyConsistencyStatus
        │      • overall form/volume/fatigue trend (3-vs-3 deltas)
        │      • per-exercise trends (sessions, avg form, mostCommonCue, breakdown rep, friction counts)
        │      • mostRepeatedCue, trophyNearMisses, cameraFrictionCount
        ▼
SignalExtractor.extractSignals(snapshot, history, profile, trophies)
        │  → [UserTrainingSignal]   (25 typed signals, each has evidenceRefs + confidence)
        │      consistency, formImprovement, formDropOff, exerciseMastery, exerciseStruggle,
        │      planFit, repeatedCue, fatigue, restBehavior, skippedExercise, cameraFriction,
        │      qualityCapacity, targetFit, movementBalance, cueCluster, restResponse,
        │      progressionReadiness, sessionFit, exerciseReacquisition, exercisePreference,
        │      qualityPR, trophyProximity, volumeIncrease/Drop, completion
        ▼
InsightCandidateBuilder.build{Plan|Workout|Dashboard|Profile|DayOverDay}Candidates(...)
        │  → [InsightCandidate]
        │      every signal → mappedInsight() (type+headline+action+severity+intent+rawScore+expirationDays)
        │      plus workout-level: form breakdown, form growth, repeated cue, completion quality, rest extended, rest skipped
        │      plus plan-level:    limitation conflict, smart-start protect-restart
        │      plus trophy:        nearest-in-progress
        │      every candidate carries `evidence`, `dedupeKey`, `context` dict, expiry, surfaces[]
        ▼
InsightRanker.rank(candidates, surface)
        │  score = rawScore + confidence*18 + specificity + actionability + emotional + severity + surface fit
        │  −36 penalty if dedupeKey was recently shown (passed in via store)
        ▼
InsightNarrativeBuilder.buildInsight(candidate)
        │  headline + long message + shortMessage from `context` dict; sanitize() blocks HR/calorie/weight-loss terms
        ▼
InsightStore (file-persisted, capped at 80 insights)
   • dedupes by key, keeps highest userValueScore
   • per-surface cooldowns: dashboard 18h, profile 22h, workoutPreview 6h, workoutSummary 10min, trophyScreen 18h
   • surfaces: HomeDashboardView (dashboard, limit 1), ProfileView (profile, limit 2),
              WorkoutPreviewView (workoutPreview), WorkoutSummaryView (workoutSummary)
```

Every render path on Home, Profile, Preview and Summary calls the full pipeline freshly with the latest history. Insights filtered to require `!evidence.isEmpty`, `recommendedAction != .noActionNeeded`, and not expired.

### 1.2 What's genuinely strong (credit before critique)

1. **Evidence is a first-class citizen.** `InsightEvidence` carries workoutId, exerciseType, setIndex, repIndex, signalId, confidence. Insights without evidence are dropped. This is exactly the right shape for a future LLM rewrite layer.
2. **Three-tier separation** (Trend snapshot → Signal → Insight candidate → Narrative). Each layer is independently testable and the seams are clean.
3. **25 distinct signal types** is a thorough surface — the derived ones (qualityCapacity, targetFit, restResponse, progressionReadiness, sessionFit, exerciseReacquisition, qualityPR) are real coaching judgments, not just stats restated.
4. **Set-level evidence model** is excellent: `SetQualitySummary.firstHalf/secondHalfAverageFormScore`, `breakdownRepIndex`, `improvementRepIndex`, `qualityTrend`, `excellentFormReps`. This is the granularity needed for "you broke down after rep 8".
5. **`sourcePolicyVersion` gating** lets you ship a new policy and invalidate all old persisted insights cleanly.
6. **Per-surface cooldowns** prevent re-showing the same insight everywhere on the same day. Architecture is right.
7. **`nonisolated` everywhere on the engines** — Swift 6 concurrency-ready, ready to move off main thread.

### 1.3 Issues found (severity-tagged)

> Numbering matches the Codex prompt blocks below. **C** = Critical, **H** = High, **M** = Medium.

#### Wiring / data integrity

**[C-1] Cooldowns fire on data load, not on impression.**
`HomeDashboardView.makeDashboardInsight` and `ProfileView.refreshProfileInsights` both call `insightStore.selectInsights(..., markPresented: true)`. That records a presentation regardless of whether the user actually looked. With dashboard 18h / profile 22h cooldowns, a high-value insight can be silenced after a single navigation that the user might never have seen. **This is the single biggest bug in the engine** — it makes good signals invisible to real users.

**[C-2] `WorkoutSummaryBuilder.placeholderInsight()` is still wired into `WorkoutSummaryView`.**
When `coachInsight: AIInsight?` is nil (no eligible candidate, or InsightEngine drops because no evidence / action == noActionNeeded), the view falls back to `summary.coachInsight` which is the literal string *"Coach insight will use form, cue, rest, and completion trends once workout history is live."* That message is a developer placeholder shipped to production users who DO have history. The user gets the worst possible insight — a future-tense apology.

**[C-3] Cue normalization is inconsistent across the engine.**
- `SignalExtractor.normalizedCueText`: lowercase + collapse whitespace.
- `InsightCandidateBuilder.normalizedCue`: lowercase + replace `"  "` with `" "` + trim.
- `TrendEngine.cueCounts`: only trims, **case-sensitive**.

Result: `mostRepeatedCue` undercounts cues like *"Drive your hips back"* vs *"drive your hips back"*. The repeated-cue signal misses real repetition; cue clusters can split. This silently weakens your strongest "specific" insights.

**[H-4] Form/volume trend signals require ≥6 sessions** (`history.count >= count*2` with count=3). The user with 1–5 workouts gets zero `formImprovement`, `formDropOff`, `volumeIncrease`, `volumeDrop`, `qualityPR`, `progressionReadiness`. That's the cohort with the fragilest retention. They need *specific* feedback, not silence.

**[H-5] `most-repeated cue` is across all-time history with no time decay.** A user who fixed "knee tracking" two months ago will keep seeing the cue resurface as the "most repeated" because old set events still dominate the count. Same for `cameraFrictionCount` (no window).

**[H-6] `appendTargetFitSignal` only fires on `latestSummary`.** If the latest summary is a quick free-analysis or noisy data, no targetFit signal at all — even though the prior workout had clear targetFit evidence. No graceful fallback.

**[M-7] `recordPresented` happens inside `selectInsights` for any caller.** Tied to C-1 but worth noting separately: when `selectInsights` is exposed for non-display uses (testing, internal preview), the cooldown gets dirty.

**[M-8] `InsightCandidate.evidence.first` is the only thing surfaced to users.** Insights have rich evidence arrays (often 3-6 items) but the dashboard / profile / summary cards never let the user drill in. Engagement loop is closed.

**[M-9] No coach-personality awareness in narrative.** The `summary.coach` field is captured but `InsightNarrativeBuilder` produces identical text for the Drill Sergeant and the Good Coach. The personality picker is the most distinctive piece of the product positioning — it has zero downstream effect.

**[M-10] `sanitize()` rewrites the whole insight if any blocked term appears.** The blocklist includes `"weight loss"`. If a user's `goal` text is *"sustainable weight loss"* (a totally legitimate goal), every relevant insight collapses into the generic disclaimer. Sanitizer should clean fields, not nuke the whole insight.

**[M-11] `severity == .important` insights are cooled like any other.** A safety-tier insight ("squats overlap with your saved knee limitation") should reset its cooldown when the surface that needs it appears, not be hidden because it was shown 22h ago.

**[M-12] `appendCueClusterSignal` substring matching is too coarse.** `shoulder|elbow|wrist|stack` all map to the *same* cluster `"upper-stack"`. A wrist-pain cue gets clustered with a shoulder-shrug cue. `"depth"|"range"|"lower"` all map to range-of-motion (lower can mean "lower the bar," "lower body," "lower back").

**[M-13] `WorkoutDetailSheetView` shows only `set.cueEvents.first`.** All the rich evidence persisted (`qualitySummary.firstHalf/secondHalf`, `breakdownRepIndex`, `improvementRepIndex`, `excellentFormReps`, `qualityTrend`, `repQualityEvents`) is computed, persisted, and never shown. The richest data layer is invisible.

**[M-14] No goal-aware boost in ranking.** `InsightRanker.score` adds a flat +4 if `relatedGoal != nil`, but never compares to `profile.primaryGoal`. A "performance" user and a "longevity" user see the same ranking even though their goals call for different priorities (performance → progressionReadiness > recovery; longevity → recovery > targetFit-aggressive).

**[M-15] No engagement signal collected.** `InsightStore` has no concept of taps, dismissals, or "useful/not useful". Without it, ranking can never learn.

**[M-16] Profile only renders 2 insights but the profile is the natural deep-dive surface.** Users come here to see "what's going on with my training." Two insights is too thin given the engine generates many more. (And the limit cap inside `InsightStore.selectInsights` is enforced after cooldown filtering — combined with C-1 the user typically sees 0–1.)

**[M-17] No per-week "story" insight bundle.** The engine produces atoms; users want a narrative.

**[M-18] No drill-down "evidence" sheet** ("based on these 3 workouts"). The data exists; the UI is absent.

**[M-19] No explanation of trend pills.** Profile WorkoutSnapshotCard shows "Form Trend = Up" with no way to understand "compared to what?" The data (`threeWorkoutComparison`) is right there.

**[M-20] No LLM hand-off seam.** The plan doc explicitly contemplates an `LLMInsightRewriter` after deterministic insights are good. Right now there's no `AIInsight.toLLMContext()` or feature flag. Cleanly retrofitting later is harder than designing the seam now.

### 1.4 What I'd ship next, in priority order

A "best fitness app in the world" pass would do these in roughly this order. Each item below maps to a Codex prompt in §1.5.

1. **Fix presentation tracking + bypass cooldowns for safety insights** (C-1, M-11) — unblocks the single biggest "why doesn't the user see good insights" issue.
2. **Replace the placeholder with an evidence-derived 1-liner** (C-2) — user-visible quality bug.
3. **Single CueNormalizer used everywhere + cluster keyword cleanup** (C-3, M-12) — quality compounds across all cue-driven signals.
4. **Bootstrap signals for sessions 1–5** (H-4) — fix the most fragile retention cohort.
5. **Window-decay all "all-time" counts** (H-5).
6. **Make WorkoutDetailSheetView honor the rich evidence** (M-13) — gives users access to the work the engine already does.
7. **Coach-personality-aware narrative variants** (M-9) — the personality picker actually changes the experience.
8. **Goal-aware ranking + drill-down evidence sheet + engagement tracking** (M-14, M-15, M-18).
9. **Insight v2: weekly "story" surface, trend explanations, LLM-ready context** (M-17, M-19, M-20).

### 1.5 Codex prompts — Phase 1

Paste each block as a separate task. Each is self-contained.

---

#### Codex Prompt 1.A — Fix cooldown / impression tracking + safety bypass

```
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
```

---

#### Codex Prompt 1.B — Kill the placeholder; ship a real per-workout 1-liner

```
TASK
After every workout, the WorkoutSummaryView's coach insight card currently falls back to
the literal placeholder string "Coach insight will use form, cue, rest, and completion
trends once workout history is live." That fallback ships to users who do have history.

GOAL
Replace the placeholder with a deterministic, evidence-driven 1-liner computed from the
WorkoutSessionSummary itself, so the card always says something specific even when
InsightEngine yields nothing.

NEW MODULE
Create `Services/WorkoutRecapBuilder.swift` (`nonisolated struct WorkoutRecapBuilder`)
with `func build(summary: WorkoutSessionSummary) -> WorkoutRecap`, where:

  struct WorkoutRecap {
      let headline: String          // e.g. "Squat day held the line."
      let bodyMessage: String       // 1–2 sentences of evidence-derived narrative
      let highlightStat: String?    // e.g. "Best set: rep 8 hit 92%"
      let nextStep: String?         // single forward-looking nudge
  }

LOGIC (deterministic, no LLM)
- Pick the dominant exercise of the session (most achievedReps + holdSeconds).
- Pull `qualitySummary.firstHalfAverageFormScore` vs `secondHalfAverageFormScore` and
  describe the trajectory: "form held", "form climbed", "form faded".
- Mention the breakdownRepIndex if present and within the dominant exercise's set.
- Mention completionPercent if not nil.
- Forward step prefers (in order): `qualityTrend == .faded` → "lock the cue early next time";
  `excellentFormReps >= 3` → "earn a small rep bump";
  `restExtended` → "give yourself 15s more rest next set";
  default → "keep the same target, deepen quality".

WIRING
- Update `WorkoutSummaryBuilder.placeholderInsight` so it is never used as a fallback;
  instead `WorkoutSummaryView` should always have a `WorkoutRecap` (passed in alongside
  the optional AIInsight).
- The AIInsight, when present, sits BELOW the recap, not in place of it.

CONSTRAINTS
- Recap must always render (zero-evidence path returns generic-but-honest fallback like
  "Logged a session. Save a few more to unlock specific coaching.")
- Use the existing `sanitize()` blocklist defensively when injecting `summary.goal`.

ACCEPTANCE
- New WorkoutRecapBuilderTests cover: clean session, faded set, partial completion,
  free-analysis save, zero-rep hold-only set.
- WorkoutSummaryView preview shows a real recap with no placeholder text.
```

---

#### Codex Prompt 1.C — One CueNormalizer + tighter cluster taxonomy

```
TASK
Cue normalization is forked across SignalExtractor, InsightCandidateBuilder, and
TrendEngine. TrendEngine.cueCounts is case-sensitive. This makes mostRepeatedCue,
repeatedCue signals, and cueCluster signals undercount real repetition.

GOAL
1. Create `Services/CueNormalizer.swift` with one canonical normalizer:
     static func normalize(_ cue: String) -> String
   Steps: trim, lowercase, collapse internal whitespace, strip trailing punctuation,
   strip leading "the/a/an/your/keep/lock/drive". Return the canonical key.

2. Create `Services/CueClusterTaxonomy.swift` with a single source of truth for cue
   families. Replace InsightCandidateBuilder + SignalExtractor inline cluster maps with:
     enum CueCluster: String, CaseIterable {
        case kneeTracking, hipHinge, trunkBrace, shoulderStack, elbowAlign,
             wristNeutral, depthRange, tempoControl, balanceStability,
             headNeck, footPlacement, breathing, other
     }
     static func cluster(for normalized: String) -> CueCluster

   Differentiate `shoulder/elbow/wrist` (currently merged into "upper-stack").
   Differentiate `depth` (squat depth) from `range of motion` from `lower` (verb).
   Add `breathing`, `head/neck`, `foot placement` clusters since the exercise library
   includes those cues.

3. Refactor TrendEngine.cueCounts, SignalExtractor.cueCounts and cueCluster, and
   InsightCandidateBuilder.normalizedCue and grouped-cue logic to use CueNormalizer
   and CueClusterTaxonomy.

CONSTRAINTS
- Behavior: cues that already produced the same `mostRepeatedCue` must still group;
  cues that previously failed to group due to case/whitespace must now group.
- No test should regress. Update existing tests to assert the new normalization.

ACCEPTANCE
- New CueNormalizerTests: 20+ pairs of input → normalized key, including
  punctuation/casing.
- New CueClusterTaxonomyTests: 20+ inputs → cluster, including the wrist/elbow/shoulder
  separation.
- Existing TrendEngineTests, SignalExtractorTests, InsightEngineTests pass.
```

---

#### Codex Prompt 1.D — Bootstrap signals for the first 1–5 sessions

```
TASK
Today, formImprovement / formDropOff / volumeIncrease / volumeDrop / qualityPR /
progressionReadiness / targetFit signals all require ≥6 sessions in history. New users
(the cohort with the fragilest retention) get silence on the most useful signals.

GOAL
Add bootstrap branches in SignalExtractor that produce informative signals for sessions
1–5 using single-session evidence:
- After session 1: `firstSession` consistency signal + `setupQuality` signal driven by
  cameraFrictionCueCount and bodyVisibility events. Also a `repCleanlinessIntro` signal:
  "75% of your reps were good-form on your first set" (uses qualitySummary.goodFormReps).
- After session 2 with at least one repeated exercise: `repeatExerciseProgress` signal
  comparing the two sessions' set-1 form averages on that exercise.
- After session 3: enable the existing trend signals using `count = 1` window
  (latest-vs-previous) instead of `count = 3` when totalWorkouts < 6.
- After any session: `personalBaseline` signal showing the user's running median form
  score for their dominant exercise so far.

DESIGN
- Add a new `SignalGenerationContext` struct passed to SignalExtractor that includes
  `historySessionCount`. Branch into a "warmup mode" inside extractSignals() when
  `historySessionCount < 6`.
- Bootstrap signals must still produce `evidenceRefs` and a confidence — keep them at
  `.medium` (never `.high`) to communicate "we're early".
- Cap bootstrap signals at 2 per surface to avoid drowning the real signals once
  history grows.

CONSTRAINTS
- Do not change any thresholds inside form rules or cue severity.
- All new signals must have unique TrainingSignalType raw values; extend the enum
  conservatively (`firstSession`, `setupQuality`, `repeatExerciseProgress`,
  `personalBaseline`).
- Update InsightCandidateBuilder.mappedInsight to map every new signal to a sensible
  InsightAction (mostly `.continuePlan` and `.focusCue`).

ACCEPTANCE
- New tests cover: history of 1, 2, 3, 5, 6 sessions and assert the right signals
  surface.
- Manually run the engine with 1 session and confirm the dashboard shows a relevant
  bootstrap insight (no longer empty).
```

---

#### Codex Prompt 1.E — Time-decay every "all-time" count

```
TASK
TrendEngine.mostRepeatedCue, cameraFrictionCount, ExerciseTrendSummary.cueCounts, and
several SignalExtractor counts use the entire history with no time decay. Once a user
fixes a problem, the signal keeps re-firing because old events dominate the count.

GOAL
Introduce a `TrendWindowPolicy` that, by default, restricts cue counts and friction
counts to the most recent N sessions OR most recent K days, whichever is shorter:
- mostRepeatedCue: last 7 sessions.
- cameraFrictionCount: last 14 days.
- ExerciseTrendSummary.cueCounts: last 5 sessions of that exercise type.
- repeatedCue evidenceRefs: only count cue events whose timestamp is within the window.

DESIGN
- Add `TrendWindowPolicy` struct with named static defaults
  (.recentCues, .recentSetup, .recentExerciseFriction). Make them tunable via
  init parameters so tests can pin the window.
- TrendEngine, SignalExtractor: thread the policy through; existing call sites use
  defaults so behavior changes uniformly.

CONSTRAINTS
- Must preserve the existing interfaces externally (default windows applied if not
  supplied).
- Persisted snapshot need not change.

ACCEPTANCE
- New tests: a user with 3 cue-X events in summaries 12 sessions ago and 1 cue-Y event
  this week → mostRepeatedCue == "Y" with default window.
- cameraFrictionCount > 0 only if events occurred within last 14 days.
- All existing TrendEngineTests pass (or are updated to pass appropriate windows where
  intentional).
```

---

#### Codex Prompt 1.F — Make WorkoutDetailSheetView show the rich evidence

```
TASK
The WorkoutDetailSheetView currently displays only `summary.cueEvents.first` per set,
yet the SetQualitySummary (firstHalf/secondHalf, breakdownRepIndex, improvementRepIndex,
qualityTrend, excellentFormReps, mostRepeatedCue) is computed and persisted. Users
never see the engine's best work.

GOAL
For each ExerciseSetSummary in the set list, render a rich evidence block:
- Mini per-rep form bar (sparkline) using `repQualityEvents.formScore` (drop missing).
- Pill row showing: avg form, excellent reps, good reps, total scored reps.
- A "drop after rep N" or "improved after rep N" badge if those indices exist.
- The set's mostRepeatedCue at top, the worstCue/bestCue inline below.
- Rest extended / skipped indicators with the rationale ("rest extended after this set").

Add an "Evidence" expand-to-detail sheet from the existing top-of-summary cards
(Effort, Top Cue) that lists the underlying CueEvents and RepQualityEvents in
chronological order — this becomes the user's "show your work" loop.

CONSTRAINTS
- Use existing Theme tokens. No new dependencies.
- Sparkline must be SwiftUI-native (Path inside a Canvas or custom Shape; do not pull
  in Charts framework dependency unless the project already uses it).

ACCEPTANCE
- A workout with at least 5 scored reps shows the sparkline in the detail sheet.
- A workout with breakdownRepIndex shows the breakdown badge in the right set.
- A workout with no rep events still renders cleanly without the sparkline section.
- Snapshot/preview tests for the detail sheet on a clean session and on a faded session.
```

---

#### Codex Prompt 1.G — Coach-personality-aware narratives

```
TASK
The coach personality (Drill Sergeant Fletcher vs Good Coach Bennet) is captured per
session but produces zero downstream variance. The InsightNarrativeBuilder generates
identical text for both. This kills the differentiation of the coach picker.

GOAL
Make every insight narrative coach-aware while keeping the same evidence/action.

DESIGN
1. Extend AIInsight to carry `coach: CoachPersonality` (default to current personality
   from profile when generated).
2. Refactor InsightNarrativeBuilder so each narrative method returns one of:
     CoachNarrative {
        let goodCoach: String
        let drillSergeant: String
        // future: let zenMaster, let dataNerd, ...
     }
   Pick by `candidate.coach`.
3. Build a `CoachVoice` helper that wraps tone snippets:
     - Good coach: warm, second-person, "let's", "nice", "you've earned", "we'll".
     - Drill sergeant: clipped, imperative, no "we", short sentences, occasional all-caps
       emphasis on a single word ("LOCK that knee"). Never insulting, never demeaning.
4. Headlines should also vary (Good: "Squat form held the line." Drill: "Squats. Locked.").
5. Sanitize() must run after narrative selection so the blocklist still applies.

CONSTRAINTS
- Never produce insulting, demeaning, body-shaming, or mental-health-triggering content,
  regardless of personality.
- Default to good coach when personality is missing.

ACCEPTANCE
- New InsightNarrativeBuilderTests parameterized on CoachPersonality with golden strings.
- WorkoutSummaryView preview can be flipped between coaches to show the difference.
```

---

#### Codex Prompt 1.H — Goal-aware ranking, drill-down evidence sheet, weekly story

```
TASK
Three related upgrades that compound into the engine feeling "smart":

1. GOAL-AWARE RANKING
   In InsightRanker.score, replace the flat `relatedGoal != nil → +4` with:
   - +10 if `candidate.relatedGoal == profile.primaryGoal`
   - +3 if `candidate.relatedGoal != nil` but mismatched
   - additionally, per-goal type weights:
       .strength    → boost progressionReadiness, qualityPR, exerciseMastery (+6)
       .longevity   → boost recovery, planFit, sessionFit, restResponse (+8)
       .performance → boost progressionReadiness, qualityCapacity, formImprovement (+6)
   Pass `profile: UserProfile` into ranker.score (call sites already have it).

2. DRILL-DOWN EVIDENCE SHEET
   Add `InsightEvidenceSheetView` that opens from any insight card. It shows:
   - The headline + long message.
   - "Based on" list: each evidenceRef rendered as a tappable row (workout date,
     exercise, set, rep) that opens the relevant WorkoutDetailSheetView.
   - "Confidence: high/medium" pill.
   - "Was this helpful?" engagement (👍 / 👎) wired to InsightStore.recordEngagement
     from prompt 1.A.

3. WEEKLY STORY
   Add `Services/WeeklyRecapBuilder.swift` that produces one composite insight per ISO
   week:
     WeeklyRecap {
        let weekStart, weekEnd
        let headline, narrative
        let stats: [LabeledStat]   // sessions, avg form, total reps, hold seconds, trophies earned
        let topMoment, biggestSurprise, nextWeekFocus
     }
   Surface it on Profile and on Dashboard once per week (Sunday evening or Monday
   morning depending on user's timezone). Persist its dedupeKey so it appears once
   per week per surface.

CONSTRAINTS
- Existing tests must still pass.
- WeeklyRecap must include at least one piece of evidence and a forward-looking nudge.

ACCEPTANCE
- InsightRankerTests cover all four goal × signal-type combinations.
- New EvidenceSheet snapshot test.
- New WeeklyRecapBuilderTests cover empty week, normal week, and "all rest week"
  (no sessions). The empty-week recap should still acknowledge the rest.
```

---

#### Codex Prompt 1.I — LLM rewrite seam (zero behavior change, future-ready)

```
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
```

---

## Part 2 — Trophies + Workout History (stickiness & virality)

### 2.1 How it's currently wired

```
WorkoutHistoryStore (file-persisted [WorkoutSessionSummary])
        │
        ▼
TrophyEngine.updateAll(history, calibrationStatus, previousSnapshot, now)
        │  → TrophyEngineResult { snapshot, newlyEarnedEvents }
        │      • iterates TrophyDefinitionCatalog.all (22 trophies)
        │      • for each: computeProgress() → metricValue() per UnlockRuleKind
        │      • merges with previous (preserves earnedAt, ratchets currentValue)
        │      • computes capstone (Apex/Alpha) from regular progress
        │      • emits TrophyUnlockEvents for newly-earned
        ▼
TrophyStore (file-persisted snapshot, latestUnlockEvents in-memory)
        │
        ├──→ WorkoutSummaryView (trophyEvents = newlyEarned, nearestTrophyProgress)
        ├──→ HomeDashboardView.refreshDashboard() → trophyTeaserText
        ├──→ ProfileView (TrophyShowcaseSection: earned tiles + nearest)
        └──→ TrophiesView (Featured + In Progress + Coming Soon, "Share" disabled)

StatsEngine.makeStats(history, trophySnapshot) → UserStats { xp, level, ... }
        • XP rule: 100/50/40 per session + 1/rep + 1/10s hold + 1/good rep + 2/excellent +
          25 per 90%+ session + 25*currentStreak + 10*longestStreak + 50*trophiesEarned
        • Level = xp / 500 + 1, infinite ladder, no level naming
```

### 2.2 What's strong

1. **Idempotent recompute from history.** Trophy state is derived, not stored stateful — bulletproof.
2. **`progressLabel` is human-readable** ("3/7 days") and confidence-aware ("Estimated").
3. **`TrophyDataRequirement` enum** (workoutHistory, repQualityEvents, calibration, heartRate, externalLoad, unsupportedExercise, none) cleanly marks which trophies are gated by missing inputs.
4. **Capstone trophies** auto-derived from eligible set. No manual recount needed when you add a new trophy.
5. **Newly-earned event is emitted at unlock moment** with celebration-style hint.
6. **WorkoutHistoryStore is pure derived stats** + safe save-and-rollback persistence.

### 2.3 Issues found (severity-tagged)

**[C-21] Sharing is disabled.** TrophiesView and TrophyCollectionView both have a "Share Collection" button that's `.disabled(true).opacity(0.45)`. Trophy unlocks have no share affordance either. **A trophy app without sharing has no virality engine.** This is the single highest-leverage improvement in the entire app for growth.

**[C-22] Trophy unlocks are visually flat.** The TrophyUnlockEventCard inside WorkoutSummaryView is a static card. No confetti, no haptic ladder, no sound, no replay clip. The biggest emotional moment in the entire app is currently a list item.

**[H-23] Trophy catalog is uniformly quantitative.** Every active trophy is "do X amount of Y" (uniqueDays, totalReps, holdSeconds, lowCueSets, mobilitySessions). Missing the trophy archetypes that drive deep engagement:
- **Skill PRs** ("Hit 5 consecutive reps at 90%+ form on any exercise").
- **Comeback** ("Returned after a 7-day gap and held 80%+ form").
- **Variety** ("Trained 5+ different movement patterns this week").
- **Anti-burnout wisdom** ("Took a mobility day after 3 hard sessions").
- **The Perfect Set** ("100% completion + 90%+ form + zero high-severity cues in a single session").
- **Coach loyalty / variety** ("Trained with both coach personalities").
- **Time-of-day pair** (Morning Glory exists — needs Sunset Stretch / Late Night Lift for symmetric play).
- **Multi-week consistency** ("3 weeks in a row hitting weekly target").
- **Kindness-to-self** ("Modified an exercise to a safer variant when the engine recommended it").

**[H-24] No personal records system.** The user has no PR page. PRs are the deepest emotional hook in any fitness product (longest plank, most squats in a session, highest single-set form score, longest streak ever, fastest workout completion at form ≥85%). Currently the only "personal best" surfaced anywhere is `longestStreak` in stats and `bestFormScore` per ExerciseTrendSummary (also not surfaced in UI).

**[H-25] No streak-saver / streak-freeze mechanic.** The dashboard shows the streak but offers no way to protect it. Duolingo's streak freeze is the textbook example of a mechanic that *measurably* moves D7+ retention. Spotter has Smart Start (short workouts) but doesn't sell it as "use this to keep your streak alive on a tough day."

**[H-26] Apex Spotter and Alpha Spotter are duplicates of the same rule.** Both fire on `allEligibleNonComingSoonTrophies`. They unlock together. The user sees two trophies at once for the same achievement — feels like a glitch. Either name them as distinct titles for the same achievement (one private, one shareable), or make them genuinely different (Alpha = first to unlock, Apex = unlock + maintain a 30-day streak afterward).

**[H-27] Generic unlock reason text.** `TrophyEngine.unlockReason` returns `"You reached 1000 reps."` for every quantity trophy. Coach-personality voice + trophy-specific narrative is the cheapest, highest-leverage emotional polish you can do.

**[H-28] No celebration of stacked unlocks.** If a session unlocks 3 trophies (totally possible — Spark + Calibrated + first morning workout = 3 at session #1), the summary lists three separate cards with no acknowledgment of the streak. Stack-bonus moments are some of the most viral content in mobile games.

**[H-29] Trophy data in summary is shown only on the post-workout screen.** If the user closes the summary, they may never see which trophies they just earned. Persist a `TrophyUnlockHistory` and surface "since last visit" on dashboard.

**[H-30] CalendarSnapshotView is a single month with single dot per day.** GitHub-style 12-week heatmap with intensity-by-volume would be vastly more emotional (and shareable). The day data (workoutCount, totalReps, averageFormScore) is computed but only `isCompleted` is used.

**[H-31] No streak milestones surfaced as events.** 3, 7, 14, 21, 30, 50, 100, 365 — each should fire a celebration the day it's hit. Currently only the current streak count is shown as a chip.

**[H-32] WorkoutHistoryStore has no edit/delete.** A misclicked free-analysis save (e.g., 3 seconds, 0 reps) pollutes streaks and stats forever. Users with months of data have no way to clean up. This silently degrades stats trust.

**[M-33] Workout history list doesn't filter or group.** With 100+ sessions the list becomes unbrowsable. No filter by exercise, coach, goal, mode (planned/free), or date range.

**[M-34] No "redo this session" CTA.** Users will *want* to repeat a clean session. The detail sheet should have "Restart this plan" and "Save as favorite."

**[M-35] No "compare to last time" view for the same plan.** Side-by-side: today's reps/form vs the last time you did the same plan. Feels obvious to a fitness user, missing in Spotter.

**[M-36] StatsEngine XP curve is flat and somewhat opaque.**
- Trophy XP is uniformly 50 per trophy. Iron Will (30 unique days) and The Spark (1 workout) both grant 50 XP. Ladder missing.
- `currentStreak * 25` re-counts every day so cumulative XP shifts daily based on whether the user worked out today — mathematically clean, but mentally confusing if the user notices their XP "go up" without a workout.
- Levels have no names. Spotter's brand voice would lend itself to titles like Recruit → Operator → Specialist → Apex → Alpha. A named level is way more shareable than "Level 23".
- XP per rep doesn't reward quality. A 20-rep set with 50% form scores the same as a 20-rep set with 95% form for the rep-volume portion.

**[M-37] Trophies are hard-coded in Swift.** Adding a seasonal/event trophy (Halloween, Spring Reset, Beach Body Summer Series) requires a code release. Should be a versioned JSON catalog with remote refresh later.

**[M-38] Trophy progress doesn't persist a "history of earned" list with date.** Showing the user "you earned 7-Day Inferno on April 12, 2026" is high-emotion. Currently `earnedAt` is on TrophyProgress but it's never surfaced in the UI.

**[M-39] No "Best of you" snapshot on Profile.** Users want a single tile that shows their proudest moments: PRs, top trophy, longest streak ever, highest single-session form. This is the screenshot-and-share card.

**[M-40] No referral / friend system entrypoint.** Even without backend, the app could accept a friend's "challenge code" pasted from a share, then surface "you and X are on day 7 together." Most fitness apps with social are sticky; Spotter has zero social hook.

**[M-41] `weekendBothDays` rule uses TrophyEngine's Calendar, not user's timezone.** A traveling user gets misclassified weekends. Same for `workoutsBeforeHour` / `workoutsAtOrAfterHour`.

**[M-42] `WorkoutHistoryStore.persist` blocks the main actor.** With 200+ summaries that's a noticeable stutter on save.

### 2.4 Priority order for stickiness/virality

1. **Trophy share artifacts + share button enabled** (C-21) — single biggest growth lever.
2. **Trophy unlock celebration: confetti, sound, haptics, replay** (C-22) — biggest emotional moment in the app.
3. **Personal Records system + "Best of you" tile on Profile** (H-24, M-39).
4. **Streak Freeze mechanic + streak milestones** (H-25, H-31).
5. **Trophy library expansion** (H-23): skill PR, comeback, variety, anti-burnout, perfect set.
6. **GitHub-style heatmap + day drill-in** (H-30).
7. **Personality-voice unlock copy + stacked-unlock multiplier** (H-27, H-28).
8. **Workout history edit/delete + filtering + redo** (H-32, M-33, M-34, M-35).
9. **Named levels + better XP curve** (M-36).
10. **Remote-loadable trophy catalog + seasonal events** (M-37).
11. **Friend challenge code (no backend required)** (M-40).
12. **Timezone fixes + off-main persistence** (M-41, M-42).

### 2.5 Codex prompts — Phase 2

---

#### Codex Prompt 2.A — Trophy share artifacts + enabled share UX

```
TASK
The Share buttons on TrophiesView and TrophyCollectionView are currently
.disabled(true).opacity(0.45). The app has zero virality vector. Build the share system.

GOAL
Generate three share artifacts as PNGs (rendered from SwiftUI views) and surface them
through the iOS share sheet:

1. SINGLE TROPHY UNLOCK CARD
   - Square (1080x1080) and 9:16 (1080x1920) variants.
   - Trophy icon + title + rarity + "Unlocked April 12, 2026" + Spotter wordmark.
   - Coach-personality color theme (Drill = red/black, Good = teal/black).
   - Subtle particle / glyph background.

2. WORKOUT RECAP CARD
   - 1080x1920.
   - Plan title + date + duration + reps + avg form + completion %.
   - Trophy unlock badge if applicable.
   - One quote-style coach insight headline (sanitized).
   - "Train with me on Spotter" call-to-action footer.

3. TROPHY COLLECTION POSTER
   - 1080x1920.
   - Grid of all earned trophies with names and unlocked dates.
   - Headline: "[Name]'s Trophy Case — N/22 earned".
   - Streak chip if current streak >= 3.

DESIGN
- Implement `Sharing/ShareCardRenderer.swift`:
    func renderTrophyUnlockCard(event: TrophyUnlockEvent, profile: UserProfile,
        coach: CoachPersonality, aspect: ShareAspect) -> UIImage
    func renderWorkoutRecapCard(summary: WorkoutSessionSummary, recap: WorkoutRecap,
        trophyEvents: [TrophyUnlockEvent]) -> UIImage
    func renderCollectionPoster(snapshot: TrophyProgressSnapshot, profile: UserProfile)
        -> UIImage
  Use SwiftUI `ImageRenderer` (iOS 16+). Render off-main inside a Task.

- Add `Sharing/ShareCoordinator.swift` to wrap UIActivityViewController presentation
  with the rendered image.

WIRING
- TrophyUnlockEventCard inside WorkoutSummaryView gets a "Share" affordance
  (icon + text). Tapping opens the share sheet with the rendered single-trophy card.
- TrophiesView and TrophyCollectionView "Share Collection" buttons enable, render the
  collection poster, present the share sheet.
- WorkoutSummaryView gets a "Share Recap" button next to "Done" for completed sessions.

CONSTRAINTS
- Pure SwiftUI rendering; do not pull in third-party share frameworks.
- Cards must be readable at 100% zoom on Instagram and X (large numerals, high
  contrast).
- All copy passes through the existing `sanitize()` blocklist.

ACCEPTANCE
- New ShareCardRendererTests use ImageRenderer to produce a PNG and assert dimensions
  and non-empty pixels.
- Tapping share on a freshly-unlocked trophy presents UIActivityViewController with
  a non-nil UIImage.
```

---

#### Codex Prompt 2.B — Trophy unlock celebration: confetti, haptics, sound, replay

```
TASK
Trophy unlocks currently render as a static list item on the post-workout summary.
Make the unlock moment feel like the proudest moment in the app.

GOAL
1. CONFETTI / PARTICLE BURST
   - Add `UI/Effects/ConfettiBurstView.swift` (SwiftUI Canvas + TimelineView).
   - Trigger on .onAppear of each TrophyUnlockEventCard inside the summary screen.
   - Color palette pulled from the trophy's `designThemeHint`.
   - Auto-dismiss after 1.8 seconds.

2. HAPTIC LADDER
   - Use `HapticsEngine` (already exists). Sequence: prepare → impact (heavy) →
     short pause → notification (.success).
   - Multiple stacked unlocks within the same summary play a rising pitch ladder
     (3 unlocks: 0.6 → 0.8 → 1.0 intensity).

3. SOUND
   - Add `Coaching/CoachVoiceAudio.swift` to play a coach-line on unlock:
     - Good Coach Bennet: warm "Yes! [Trophy title] unlocked. Earned, not given."
     - Drill Sergeant Fletcher: clipped "TROPHY. [Trophy title]. KEEP MOVING."
   - Use AVAudioPlayer with a bundled short MP3 per coach × per rarity tier.
   - Respect mute + AVAudioSession.ambient category so it ducks under user music.

4. REPLAY CAPTURE (foundation only)
   - Add `Camera/SessionReplayBuffer.swift`: ring buffer holding the last 6 seconds
     of pose-overlay frames during a session. On a trophy unlock, snapshot the buffer
     into a file (mp4 export from CIImage frames or store frame data for later).
   - On the workout summary, surface "Save replay" button per unlocked trophy that
     writes to camera roll (with PHPhotoLibrary auth). If replay capture isn't ready
     (auth denied, buffer not available), hide the button gracefully.

5. STACKED UNLOCK MULTIPLIER
   - If `trophyEvents.count >= 2` show a "TRIPLE / DOUBLE" banner above the cards.
   - Award a bonus XP (50 per stacked trophy beyond the first) and surface it in
     the celebration.

CONSTRAINTS
- Confetti must respect Reduce Motion (no animation, just a static gold ribbon).
- Sound respects system mute and silent-switch.
- Bonus XP must be reproducible from history (compute the bonus when StatsEngine sees
  N >= 2 unlocks attached to the same workout summary; persist `bonusUnlockEvents`
  alongside the regular ones).

ACCEPTANCE
- New tests: ConfettiBurstView renders with a known palette; SessionReplayBuffer
  retains exactly the last N frames; double-unlock produces correct bonus XP in
  StatsEngine.
- Manual: trigger a trophy unlock and observe confetti + haptic + audio.
```

---

#### Codex Prompt 2.C — Personal Records system + "Best of you" Profile tile

```
TASK
Spotter has zero PR system. Personal records are the deepest emotional hook in any
fitness product. Add a deterministic PR engine that derives PRs from existing history.

GOAL
1. NEW MODULE: Services/PersonalRecordEngine.swift
     enum PersonalRecordKind: String, Codable {
        case mostRepsInSession, longestHoldInSession, highestSetFormScore,
             longestStreak, fastestPlanCompletion, bestSessionAvgForm,
             cleanestSet  // 100% form rep streak length within a set
     }
     struct PersonalRecord: Identifiable, Codable {
        let id: String
        let kind: PersonalRecordKind
        let exerciseType: ExerciseType?
        let value: Double
        let unit: String
        let achievedAt: Date
        let workoutId: UUID
     }
     struct PersonalRecordEngine {
        func compute(from history: [WorkoutSessionSummary]) -> [PersonalRecord]
     }

   PR rules:
   - mostRepsInSession: per ExerciseType. Earned the moment a session sets a new high.
   - longestHoldInSession: per ExerciseType for hold-targeted exercises.
   - highestSetFormScore: per ExerciseType, requires totalScoredReps >= 5.
   - bestSessionAvgForm: highest averageFormScore for any session with completion >= 80%.
   - longestStreak: derived from uniqueWorkoutDays (single global PR).
   - fastestPlanCompletion: per planId where completion == 100% and avg form >= 85%.
   - cleanestSet: longest run of consecutive repQualityEvents.formScore >= 95.

2. NEW STORE: PersonalRecordStore (file-persisted, derived but cached for diff
   detection so we know which PR is new).

3. PR EVENT FIRE: when adding a workout summary, run PersonalRecordEngine on
   `previous + new` vs `previous`, emit `[PersonalRecordEvent]` for any newly-set PRs.
   Surface them next to TrophyUnlockEvents in the workout summary.

4. UI: Profile gets a "Personal Records" section above Workout Snapshot. Tap a PR
   to open the originating workout detail.

5. "Best of You" tile: above the trophy showcase on Profile, render a single composite
   card showing the user's top trophy, top PR, longest streak ever, and a CTA to share
   it (uses ShareCardRenderer from prompt 2.A).

CONSTRAINTS
- PRs are derived; never out of sync with history. Recomputed on every history change.
- Free-analysis sessions count for per-exercise PRs but not for fastestPlanCompletion.
- A PR can be tied to exactly one workoutId.

ACCEPTANCE
- New PersonalRecordEngineTests cover each kind with golden inputs.
- Profile preview shows the new section with at least 3 sample PRs.
- Saving a workout that beats a PR triggers a PersonalRecordEvent visible in the
  summary screen alongside trophy events.
```

---

#### Codex Prompt 2.D — Streak Freeze + Streak Milestones

```
TASK
Spotter's streak is shown but not protected and not celebrated at milestones. Add the
two mechanics that drive D7+ retention.

GOAL
1. STREAK FREEZE
   - StatsEngine grants 1 streak-freeze token per N (default 7) clean days
     (max bank = 3). A "clean day" = workoutDay with averageFormScore >= 70 OR a
     mobility-tagged session.
   - WorkoutHistoryStore exposes `currentStreakFreezeBalance`.
   - When the engine detects a streak break risk (now's local startOfDay - lastWorkoutDay
     == 1 day and no workout yet today), Dashboard shows a "Use Streak Freeze" CTA on
     the Smart Start card and on the streak chip.
   - Using a freeze writes a `StreakFreezeUsage` record with date; the streak
     calculation treats that day as if a workout happened.
   - Display freeze balance on Dashboard and Profile as a small icon row.

2. STREAK MILESTONES
   - Define `StreakMilestone` set: 3, 7, 14, 21, 30, 50, 100, 200, 365.
   - On every history change, detect newly-crossed milestones and fire a
     `StreakMilestoneEvent` with celebration style (rare for 3/7, epic for 30/50, legendary
     for 100/365).
   - Surface milestone events the same way trophies are surfaced (post-workout summary,
     dashboard banner that auto-dismisses after acknowledgment).
   - Each milestone has its own coach-voice copy line ("30 days. You don't break.").

3. PERSISTENCE
   - Add a `Models/StreakProtectionStore.swift` for freeze tokens + usage history +
     milestone-acknowledged set. File-persisted.

CONSTRAINTS
- Streak freezes never push the user past a "cheat" perception. Cap at 3 banked, never
  more than 1 used per week.
- Milestones must idempotently re-fire only on first crossing — store the
  acknowledged set keyed by milestone value.

ACCEPTANCE
- New tests: a user with 6 days streak who skips a day sees freeze offered tomorrow;
  using freeze preserves streak.
- A 30-day streak fires the 30 milestone exactly once.
- StatsEngine XP gives streak-freeze events 0 XP (so freezing isn't itself rewarded with
  XP, only with retention).
```

---

#### Codex Prompt 2.E — Expand the trophy library (skill PRs, comeback, variety, perfect set)

```
TASK
Today every active trophy is "do X amount of Y". Add the trophy archetypes that drive
deeper engagement and emotional resonance, while keeping the strict-rule constraint
respected.

GOAL
Add the following trophies to TrophyDefinitionCatalog.all (new
TrophyUnlockRuleKind cases as needed). Each must come with a TrophyDefinition,
unlock rule, progress logic in TrophyEngine.metricValue, and unit tests.

1. THE PERFECT SET — single-session: completion >= 100%, averageFormScore >= 90,
   totalHighSeverityCues == 0, totalReps + totalHoldSeconds > 0. Rare.
2. CLEAN SLATE — 5 sessions in a row with 0 high-severity cues. Epic.
3. COMEBACK KID — first session after a gap of 7+ days that ends with averageFormScore
   >= 80 and completion >= 90%. Rare.
4. EXPLORER — Trained 10+ different ExerciseTypes across all history. Common.
5. PATTERN MASTER — Trained at least 5 different MovementPatterns within any rolling
   7-day window. Rare.
6. BALANCED ATHLETE — At least one session in each of upper/lower/core regions within
   any rolling 14-day window. Epic.
7. WISE REST — Took a mobility-tagged session within 24 hours of a high-strain session
   (peakEffort >= 0.65). Rare.
8. WEEKLY CONQUEROR — Hit weekly target days for 3 consecutive ISO weeks. Epic.
9. COACH SWITCH — Completed at least one session with each available CoachPersonality.
   Common.
10. SUNSET STRETCH — 5 sessions started between 18:00 and 21:59 (paired with the
    existing Morning Glory). Rare.
11. SKILL PR: CLEAN STREAK — A single set with 5 consecutive reps each scoring
    formScore >= 90. Epic.
12. PROGRESS, NOT PERFECTION — 3 different sessions where the second-half formScore
    average exceeded the first-half by >= 8 points (the "I improved during the set"
    trophy). Rare.

REQUIREMENTS
- Each new trophy has a distinct iconName, rarity, designThemeHint, sortOrder.
- TrophyEngine.metricValue extended with the new computations using helpers that work
  off existing summary structures (no changes to form rules or thresholds).
- Coach-voice unlock copy in TrophyEngine.unlockReason — switch on trophyId for the
  new ones.

CONSTRAINTS
- Do NOT introduce trophies that depend on heart rate, weight, or external load.
- Mobility detection reuses TrophyEngine.isMobilitySession.
- Skip sessions with empty exerciseSummaries from inference.

ACCEPTANCE
- TrophyEngineTests gain at least one test per new trophy with a positive and negative
  case.
- Existing capstone trophy (Apex/Alpha) auto-includes the new trophies in its denominator.
```

---

#### Codex Prompt 2.F — GitHub-style heatmap + day drill-in

```
TASK
CalendarSnapshotView shows one month with a single dot per day. The day data has
workoutCount, totalReps, totalHoldSeconds, averageFormScore — all unused for intensity.

GOAL
1. NEW VIEW: UI/TrainingHeatmapView.swift
   - 12-week (84-day) horizontal grid, 7 rows × 12 columns.
   - Each cell tinted by intensity (0 = empty bg, 1 = light accent, 2 = mid, 3 = full
     accent, 4 = full + glow). Intensity = clamp(workoutCount + (averageFormScore?? >=
     85 ? 1 : 0) + (totalReps + totalHoldSeconds/10 > 100 ? 1 : 0), 0, 4).
   - Tap a cell opens a `DayDrillInSheet` showing each session that day with quick
     stats and a "Open detail" link to WorkoutDetailSheetView.

2. INTEGRATE
   - Replace CalendarSnapshotView in Profile's WorkoutSnapshotCard with the heatmap
     while keeping the existing month grid available below as "This Month" (collapsed).
   - Heatmap sources data from existing TrendEngine.daily* helpers. Add
     `TrendEngine.dailyIntensitySummary(history:profile:days:)` returning a
     `[Date: DayIntensitySummary]` for the heatmap window.

3. SHARE AFFORDANCE
   - Add a "Share Heatmap" button below the heatmap that uses ShareCardRenderer (from
     prompt 2.A) to render a poster of the heatmap.

CONSTRAINTS
- Heatmap respects the user's profile timezone (TrendEngine.calendar(for: profile)).
- Reduce Motion: no glow animation; static intensity tints only.
- Accessibility: each cell has accessibilityLabel "April 12, 2 workouts, 88% form".

ACCEPTANCE
- TrendEngineTests: dailyIntensitySummary returns 84 entries for a 12-week window.
- Profile preview renders the heatmap; tapping a populated cell opens DayDrillInSheet.
```

---

#### Codex Prompt 2.G — Workout history edit/delete + filtering + "redo this plan"

```
TASK
WorkoutHistoryStore has no edit/delete. Misclicked free-analysis saves pollute streaks
and stats forever. The "View All" history list has no filter or grouping.

GOAL
1. EDIT/DELETE
   - Add `WorkoutHistoryStore.removeSummary(id:)` and `updateSummary(_:)` with the
     same save-and-rollback pattern.
   - In WorkoutDetailSheetView, add an overflow menu with "Delete workout" (destructive
     confirmation). Deleting recomputes stats, trophies (on next refresh — already
     idempotent), insight cooldowns (drop dedupeKeys whose evidence references the
     deleted workoutId).
   - Optional fields to edit: title, goal text, mode (planned/free conversion). No
     editing of computed metrics.

2. FILTERING / GROUPING
   - WorkoutHistoryListView gets a header filter row: Mode (all/planned/free), Coach,
     Goal, Date range chips (last 7 days / 30 / 90 / all).
   - Group rows by ISO week with a sticky header showing week start date and that
     week's session count.

3. REDO THIS PLAN
   - WorkoutDetailSheetView gets a "Restart this plan" CTA visible when
     `summary.mode == .plannedWorkout` and `summary.planId != nil`. Tapping resolves the
     plan from PlanService (or stores the persisted plan snapshot if PlanService no
     longer has it) and pushes WorkoutPreviewView.
   - Add a "Save as favorite" star toggle that persists into a new
     `Models/FavoritePlanStore.swift`. Favorites surface on Dashboard as a small chip
     row above Smart Start.

CONSTRAINTS
- Deletion of a workout cascades to: PR engine recomputes (PR may revert), trophy
  recomputes (trophy that was earned only because of the deleted workout reverts to
  in-progress unless an `earnedAt` already locked it — the current merge() preserves
  earned). Decision: a deleted workout DOES revert PRs but does NOT revert
  already-earned trophies (consistent with how the merge() function works today).
- Insight dedupeKeys whose evidence references the deleted workoutId must be expired
  immediately (not cooled).

ACCEPTANCE
- WorkoutHistoryStoreTests cover delete + recomputation.
- WorkoutHistoryListView preview shows filter chips + week groupings.
- Tapping "Restart this plan" navigates to WorkoutPreviewView with the right plan.
```

---

#### Codex Prompt 2.H — Named levels + better XP curve + remote-loadable trophy catalog

```
TASK
Two related polish upgrades plus an architectural unlock:

1. NAMED LEVELS
   - Replace "Level N" with named ranks. Define
     `enum SpotterRank { case recruit, rookie, operator_, specialist, athlete, alpha,
                         apex, mythic }` with `range: ClosedRange<Int>` per rank.
   - Add `SpotterRank.forXP(_ xp: Int) -> SpotterRank` and
     `next: SpotterRank?`, `progressFraction: Double`.
   - Display rank name everywhere the level is shown (Profile header, share cards).

2. BETTER XP CURVE
   - Replace flat 50-XP-per-trophy with rarity-weighted XP:
       common → 25, rare → 60, epic → 120, legendary → 250.
   - Add session-quality bonus: for any session with averageFormScore >= 90 and
     completion >= 95, +75 XP "Quality Bonus".
   - Cap streak XP contribution per day so revisiting the app doesn't inflate XP
     mentally: streak XP frozen daily once awarded.

3. REMOTE-LOADABLE TROPHY CATALOG
   - Move TrophyDefinitionCatalog.all to JSON, bundled in app resources at
     `Resources/Trophies/catalog.json`.
   - Add `TrophyCatalogLoader` that:
       a) Loads the bundled JSON at startup.
       b) Optionally hydrates from a remote URL behind FeatureFlag
          `trophyCatalogRemote` (default off). On success, validate against schema and
          atomically swap.
   - Existing code reads through `TrophyDefinitionCatalog` which now wraps the loader.

CONSTRAINTS
- Backwards-compatible JSON serialization for already-persisted TrophyProgressSnapshot.
- Catalog version bump invalidates non-earned in-progress on schema change but preserves
  earnedAt by trophyId.

ACCEPTANCE
- StatsEngineTests for the new XP rules.
- TrophyCatalogLoaderTests load the bundled JSON and parse all definitions.
- Profile preview shows the rank name (e.g. "ATHLETE / 3,420 XP").
```

---

## Closing thoughts

Your engine architecture is unusually disciplined for this stage — three-tier separation, evidence-first, deterministic, sanitized, persisted, surface-aware. That's the hardest 70% of the work. The next 30% is what makes a fitness app the *best* one:

- **Trust** comes from showing your work — evidence drill-down sheets and rich detail sheets surface what your engine already knows.
- **Stickiness** comes from the streak-freeze + milestones + heatmap loop and PRs that grow with the user.
- **Virality** comes from beautiful share artifacts you currently have no UI for.
- **Personality** comes from coach-aware narratives you currently overwrite with generic copy.
- **Early-user retention** comes from bootstrap signals before session 6.
- **Long-term defensibility** comes from the LLM rewrite seam you can land *now* without behavior change.

Ship the **Critical** items first (presentation tracking C-1, kill the placeholder C-2, normalize cues C-3, share cards C-21, unlock celebration C-22). They are independently shippable, low-risk, and each one moves a real metric. Then layer the High items in the order above. The Mediums are polish — important polish, but they compound after the foundation lands.

If I had to pick the single highest ROI prompt to send to Codex tomorrow: **2.A (share artifacts)**. Without it, every other improvement only benefits the users you already have.
