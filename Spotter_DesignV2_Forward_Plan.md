# Spotter — Backend Hardening + Design System V2 Forward Plan

**Purpose.** Single source of truth from "Phase 17 complete" through the design-system revamp.

**Inputs read.** README.md, DEBUG_LOG.md (entries DL-001 through DL-066), every file in `Documentation/*`, every file under `VirtualTrainer/Repositories/Firebase/*` and `VirtualTrainer/Repositories/*`, `VirtualTrainer/DesignSystem/LiquidGlass.swift`, `VirtualTrainer/DesignSystem/Theme.swift`, `VirtualTrainer/UI/MainTabView.swift`, `VirtualTrainer/VirtualTrainerApp.swift`, `VirtualTrainer/Services/FeatureFlags.swift`, `VirtualTrainer/Services/RemoteFeatureFlagService.swift`, `VirtualTrainer/Models/ThemeStore.swift`, the 29 HTML files in `NEW_DESIGN/export-html/`, the 29 screenshots in `NEW_DESIGN/screenshots/`, GPT 5.5 Pro's uploaded plan in full, and `git log` (recent 30 commits).

**Author.** Founder-coach review (deep audit, not file-presence check).

---

## Part 1 — Backend state of the union

### 1.1 What's shipped (verified file-by-file, not by README alone)

| Phase | Status | Verified by |
|---|---|---|
| 16.0 – Firebase resource hardening + config audit | ✅ Done | DL-046 + DL-047 |
| 16A – BackendStatusStore + mode-aware bootstrap | ✅ Done | DL-048 + `BackendStatusStore.swift` reads desired mode and falls back to local |
| 16B – `FirebaseAuthRepository` + anonymous sign-in + claim coordinator | ✅ Done | DL-049 + `FirebaseAuthRepository.swift` + `AccountClaimCoordinator` wiring in `VirtualTrainerApp.swift` |
| 16C – Firestore DTOs / mappers / path / privacy validator | ✅ Done | DL-050 + 16 files under `Repositories/Firebase/` |
| 16D – Firestore profile / theme / calibration / plans repos | ✅ Done | DL-051 |
| 16E – Firestore workout repo, Option B (compact doc + sets subcollection) | ✅ Done | DL-052 + `FirestoreWorkoutRepository.swift` writes one workout doc + N set docs |
| 16F – Firestore trophy + insight repos | ✅ Done | DL-053 + DL-054 |
| 16G – `SyncOrchestrator` activation (pull / push / listeners) | ✅ Done | DL-055 + DL-056 |
| 16H – Firestore rules + App Check debug provider + privacy assertion tests | ✅ Done | DL-057 + DL-058 + `Documentation/firestore.rules` + `Documentation/AppCheckRollout.md` |
| 16I – Backend account deletion + remote export + Cloud Functions plan | ✅ Done | DL-059 + DL-060 + DL-061 + DL-062 + `Documentation/FirebaseFunctionsPlan.md` |
| 16J – Remote Config + Analytics + Crashlytics + App Check enforcement readiness | ✅ Done | DL-063 + DL-064 + `RemoteFeatureFlagService.swift` |
| 17 – Backend QA, emulator setup, cost tracking, backpressure | ✅ Done | DL-065 + DL-066 + `Documentation/FirebaseCostBudget.md`, `Documentation/FirebaseEmulatorSetup.md`, `Documentation/BackendQAChecklist.md` |

Test count is now in the 335+ range (from `BackendRepositoryTests`, `SyncMetadataTests`, `LocalWriteJournalTests`, `PersistenceActorTests`, `ComplianceServicesTests`, `AccountOwnershipTests`, plus the original 28 product tests). Repository layer is clean, `nonisolated`, `async throws` everywhere, observe methods return `AsyncStream`, conflicts surface explicitly.

### 1.2 What I found that needs hardening before the design revamp

GPT 5.5 Pro flagged three real backend gaps. I verified all three are real, plus I added two more from my own audit.

**Gap H-1 (Critical) — Firestore root `users/{uid}` document allows arbitrary owner writes.** Confirmed in `Documentation/firestore.rules` line 39:

```js
match /users/{uid} {
  allow read, write: if owns(uid);  // ← too permissive
  match /profile/{doc} { ... }
  match /workouts/{workoutId} { ... }
  ...
}
```

The subcollections (`profile`, `workouts`, `trophyEvents`, `insights`, etc.) are tight, but the root user doc is wide open. An authenticated client could push any shape — including forbidden raw fields — to the root doc since the `noRawData()` guard is only applied to subcollection writes. The app currently never writes to the root doc directly (all writes go through DTOs into subcollections), so this is a latent vulnerability, not a live bug, but it must be closed before opening the app to anonymous external testers.

**Gap H-2 (Critical) — `FirestoreWorkoutRepository.deleteWorkout` is not idempotent against offline-then-deleted workouts.** Confirmed in `FirestoreWorkoutRepository.swift` line 142–149:

```swift
func deleteWorkout(accountId: String, id: UUID, operationId: UUID) async throws {
    let uid = try FirestoreRepositorySupport.requiredAccountId(accountId)
    let path = try FirestorePathBuilder.workoutDocument(uid: uid, workoutId: id)
    let payload = try Self.deletePayload(operationId: operationId)

    try await database.commitBatch { batch in
        try batch.updateData(payload, path: path)   // ← fails NOT_FOUND if doc never existed
    }
}
```

The `deletePayload` only contains `deletedAt`, `operationId`, and `syncMetadata` — a partial update. Firestore's `updateData` requires the document to exist. Scenario:
1. User saves workout while offline → local-only.
2. User deletes the workout while still offline.
3. Connectivity returns. `SyncOrchestrator.pushPendingLocal` calls `deleteWorkout`.
4. Firestore responds NOT_FOUND. The push fails; the tombstone never propagates.
5. If the user opens the app on a second device that has the original local copy, the delete will never reach it.

Fix: switch to `batch.setData(payload, merge: true)` so the call creates a minimal tombstone if the doc doesn't yet exist, or updates it if it does. The merged tombstone must include the minimum readable fields (`accountId`, `schemaVersion`, `workoutId`, plus `deletedAt`/`operationId`/`syncMetadata`).

**Gap H-3 (High) — Privacy validator allows Data fields ≤ 4 KB.** Confirmed in `FirestorePrivacyValidator.swift`:

```swift
private static let maxAllowedDataBytes = 4 * 1_024
```

DTOs in `FirestoreDTOs.swift` never emit `Data` fields. Therefore any `Data` value reaching the validator is, by definition, anomalous — it's either a future bug or a tampered payload. The right stance is **zero `Data` allowed unless an explicit allowlist key opts in**. Today's "small `Data` OK" path silently passes through anomalies.

**Gap H-4 (Medium) — Sign in with Apple linking is a no-op.** Confirmed in `FirebaseAuthRepository.swift`:

```swift
func linkAnonymousAccountWithApple(idToken: String, nonce: String) async throws -> String {
    throw RepositoryError.backendUnavailable
}
```

This is fine for the internal anonymous-only beta. But the welcome screen in `NEW_DESIGN/export-html/welcome-screen.html` shows *"Already have an account? Log in"* — and Apple's App Store requires that any app exposing account creation (including anonymous) must support deletion AND, if you offer third-party login, support [Apple's REVOKE_TOKEN propagation](https://developer.apple.com/documentation/sign_in_with_apple). The design revamp should hide / disable this link until SIWA + revocation handler are ready in a future phase. Not a hardening fix; it's a design-vs-code delta that must be respected during the V2 revamp.

**Gap H-5 (Medium) — No emulator-backed rules tests yet.** `Documentation/FirebaseEmulatorSetup.md` documents how to spin up the emulator, but there are no automated tests that prove the rules deny what they should. GPT flagged this as Gap 4. Without these tests, rules-change regressions slip through silently. Manual checklist in `BackendQAChecklist.md` is helpful but not sufficient for a fast-moving design phase.

### 1.3 Backend hardening prompt (run before any design code)

Treat this as **P17.5**. It's small (1–2 days) but it closes the critical bugs and gives the design phase a quiet backend.

```
TASK
P17.5 — Backend hardening before design revamp.

Use the Spotter universal preflight block. Before changing code, inspect:
- Documentation/firestore.rules
- Documentation/SyncConflictResolution.md
- Documentation/BackendQAChecklist.md
- Documentation/FirebaseEmulatorSetup.md
- VirtualTrainer/Repositories/Firebase/FirestoreWorkoutRepository.swift
- VirtualTrainer/Repositories/Firebase/FirestorePrivacyValidator.swift
- VirtualTrainer/Repositories/Firebase/FirestoreDocumentDatabase.swift
- VirtualTrainer/Repositories/SyncOrchestrator.swift
- DEBUG_LOG entries DL-052, DL-056, DL-057, DL-058

Do NOT touch the live camera pipeline. Do NOT change product UI. Do NOT
add new repositories.

GOAL
Close the four backend hardening gaps:
H-1 root users/{uid} document is owner-writable but unschemaed.
H-2 deleteWorkout is not idempotent against offline-then-deleted workouts.
H-3 privacy validator allows any Data field <= 4 KB.
H-5 no automated rules tests.

TASKS

1. Tighten Documentation/firestore.rules.

Replace `match /users/{uid} { allow read, write: if owns(uid); ... }`
with an explicit, narrow root-doc rule:

  match /users/{uid} {
    // Root doc is reserved metadata only. Schema:
    //   accountId: string == uid
    //   schemaVersion: integer
    //   createdAt: timestamp
    //   updatedAt: timestamp
    //   lastSeenAt: timestamp (optional)
    // Anything else is denied.
    allow read: if owns(uid);
    allow create, update: if owns(uid)
      && request.resource.data.accountId == uid
      && request.resource.data.keys().hasOnly([
        "accountId", "schemaVersion", "createdAt", "updatedAt", "lastSeenAt"
      ])
      && noRawData();
    allow delete: if false;

    match /profile/{doc} { ... existing ... }
    match /workouts/{workoutId} { ... existing ... }
    ...
  }

If the app never writes the root doc today (verify by grepping for
FirestorePathBuilder.users(_:) in repos), keep create/update behind the
narrow schema so future code cannot accidentally bypass it. Also publish
the updated rules in the Firebase Console after merging.

2. Patch FirestoreWorkoutRepository.deleteWorkout tombstone idempotency.

Replace `batch.updateData(payload, path: path)` with
`batch.setData(payload, path: path, merge: true)`.

Extend deletePayload to include the minimum readable fields needed for
a default-hidden tombstone document:

  - accountId (current uid)
  - schemaVersion (current workout schema)
  - workoutId (== id.uuidString.lowercased())
  - deletedAt: FieldValue.serverTimestamp()
  - operationId: deterministic
  - syncMetadata: pending-upload shape

Behavior matrix:
  - doc exists: merge tombstone in place.
  - doc missing: minimal tombstone is created.
  - same operationId retried: setData(merge:true) is idempotent.
  - workout has sets subcollection: untouched (filter at read time via
    workout deletedAt).

Add tests:
  - delete-before-upload writes a minimal tombstone via setData merge.
  - normal delete after upload merges deletedAt.
  - retry with same operationId is a no-op (no duplicate writes).
  - loadRecentWorkouts hides tombstoned workouts.
  - loadRecentWorkoutTombstones returns them.

3. Strengthen FirestorePrivacyValidator.

Add a small allowlist of fields that may carry Data (currently: none).

Change the Data branch:

  if let data = value as? Data {
    let key = path.last ?? ""
    guard Self.allowedDataFieldPaths.contains(key.lowercased()) else {
      throw RepositoryError.invalidPayload(
        "Payload contains a Data value at key \"\(key)\"; no Data fields are allowlisted today."
      )
    }
    guard data.count <= maxAllowedDataBytes else {
      throw RepositoryError.invalidPayload("Payload contains a large binary value.")
    }
    return
  }

Default allowedDataFieldPaths = empty set. Document the policy at the
top of the file. Existing forbidden-key + secret-regex checks stay.

Add tests:
  - any Data of any size at any path throws.
  - allowlisting a key explicitly lets it pass.
  - forbidden keys still rejected case-insensitively.
  - existing fully-populated DTO payloads still pass.

4. Add emulator-backed rules tests.

Documentation/FirestoreRulesEmulatorTests.md describes how to run
@firebase/rules-unit-testing against Documentation/firestore.rules.

Create scripts/test-firestore-rules.sh that:
  - Spawns the Firestore emulator (firebase emulators:start
    --only firestore --import=tmp/empty --export-on-exit).
  - Runs a Node test file at scripts/firestore-rules-tests/index.test.js
    asserting:
      a) wrong uid cannot read or write users/otherUid/profile/current.
      b) authenticated owner CAN write profile/current with hasAccountId.
      c) authenticated owner CANNOT write users/uid (root) with arbitrary
         fields beyond the new schema.
      d) authenticated owner CAN write a root doc with allowlisted keys.
      e) rawVideo / cameraFrame / rawPoseStream in any subcollection
         denied.
      f) workout tombstone-via-setData-merge with deletedAt allowed.
      g) workout normal write allowed.
      h) trophy event create allowed; update denied (append-only).
      i) insight create+update allowed; delete denied.
  - Exits non-zero on failure.

Add a CI / pre-commit hook stub so this is runnable locally even if not
wired into Xcode tests.

5. Update README, BackendQAChecklist, and Documentation/firestore.rules
   header to reflect the tightened rules. Update DEBUG_LOG with a new
   DL-067 entry describing the four fixes.

ACCEPTANCE
- Updated firestore.rules denies arbitrary root-doc writes; profile,
  workouts, trophies, insights, calibration, plans subcollections still
  work.
- Offline-create-then-delete-then-sync of a workout produces a tombstone
  doc in Firestore.
- Privacy validator rejects every Data field; existing DTO writes pass.
- Emulator test suite passes.
- Existing 335+ XCTest count holds or grows.
- DEBUG_LOG DL-067 entry recorded.
```

After this lands, **publish the new `firestore.rules` to the Firebase Console** (`Firestore Database → Rules → Edit → Publish`) before starting any design work. The console paste is the only step that's not in code.

---

## Part 2 — Design System V2: the strategy

### 2.1 What I learned reading every HTML file and screenshot

**Design tokens (from `:root` in every screen):**

```
--background:          #0D0D0D    near-black
--foreground:          #F2F0EB    warm cream
--primary:             #C8FF00    electric lime
--primary-foreground:  #000000    black on lime
--secondary:           #262626    dark grey
--secondary-foreground:#F2F0EB
--muted:               #262626
--muted-foreground:    #A3A3A3    medium grey for captions
--accent:              #C8FF00    same as primary in base theme
--destructive:         #FF5C3A    orange-red
--card:                #0D0D0D    cards bleed into background
--popover:             #0D0D0D
--border:              #F2F0EB    cream borders, THICK (2 px or 4 px)
--ring:                #C8FF00    focus ring
--chart-1:             #00D1FF    cyan (form-quality, stats)
--chart-2:             #C8FF00    lime
--chart-3:             #FF5C3A    orange-red
--chart-4:             #525252    grey
--chart-5:             #262626    near black

--font-sans:    "DM Sans"           body
--font-heading: "Space Grotesk"     all-caps display
--font-serif:   "Playfair Display"  occasional accent text
--font-mono:    "JetBrains Mono"    metric numerals

--radius:       1rem                base; multiplied for xs/sm/md/lg/xl/2xl/3xl/4xl
```

**Critical observation about themes.** The four "theme preview" HTML files (`hyper-theme-preview`, `hot-girl-theme-preview`, `warm-theme-preview`, `spicy-theme-preview`) **share identical `:root` token values**. The themes differ only by **content variations and a few hand-picked accent colors used inside cards** (e.g., hot-girl uses `#FF00FF`, warm uses `#7C3AED`, spicy uses `#00FFC2`). The base palette is constant: black background, cream borders, lime primary, cyan chart-1, orange-red destructive. The **existing `SpotterThemeOption` enum already maps to per-theme accent + secondary accent colors** in `Theme.swift`. The V2 implementation should keep that pattern: one constant palette for surface chrome (black/cream/grey), and per-theme accent overrides (lime/cyan/orange-red/etc).

**Design language summary:**

- Aggressive editorial typography. All-caps, tight tracking, italic on headings.
- Thick (2–4 px) cream borders on cards — the "brutalist" outline aesthetic.
- Drop-shadows in `4px 4px 0px 0px #C8FF00` style (offset, no blur, primary color).
- Bottom-anchored primary CTAs (full-width, 64 pt tall, square-ish 24 pt radius, primary fill, black text).
- Monospaced metric numerals (form scores, rep counts, durations).
- Icon library is Phosphor (iconify `ph-*` names). **Not** available on iOS without bundling — must be mapped to SF Symbols.
- Lots of large `5xl/6xl` numeric typography. Numbers are heroes.
- Cards bleed into background; the border defines the card, not a fill color.
- Animations: subtle (active:scale-95 on press), pulsing dots, occasional gradient masks for hero imagery.

**Liquid glass nav (the second nav variant).** `liquid-glass-nav-iteration.html` shows a **floating bottom pill nav** ~92 pt tall, ~92% screen width, fixed 10 pt from bottom, `border-radius: 46 pt`, `backdrop-blur-3xl`, `bg-black/40`, cream border at 20% opacity, dual shadow (outer 25 pt drop + inset 1 pt highlight). Four tab buttons: Dashboard (house), Camera (camera), Trophies (trophy), Profile (person). Selected tab gets `bg-white/10` chip with primary-tint border.

**Existing `LiquidGlass.swift` is the right foundation.** It already exposes `.glassCard()`, `.glassSurface()`, `.glassPopup()`, `.glassInteractive()`, `GlassCTAStyle`, `GlassContainer` — with iOS 26+ native `.glassEffect` and iOS 17–25 fallback. The V2 liquid glass nav can sit on top of these primitives.

### 2.2 Design-vs-code delta map

This is the most important section. The new design system is not a 1:1 representation of the implemented product. Two delta directions:

#### A. Design shows features the code does NOT yet support → **call out, do NOT build**

| Design element | Code reality | Action in V2 |
|---|---|---|
| **"Already have an account? Log in"** link on welcome | `FirebaseAuthRepository.linkAnonymousAccountWithApple` throws `.backendUnavailable`. SIWA + revocation handler are deferred. | Hide the link entirely OR show as disabled with subtle "Coming soon" affordance. Do not stub a fake login flow. |
| **Smart exercise swaps / "AI alternatives"** in workout preview and `exercise-swap-sheet-v2.html` | Product decision (DL-026, DL-032): plan-detail swap is intentionally hidden; only target volume editing is exposed. `PlanSwapService` exists but is not wired to UI. | Use only the V1 swap sheet visual language for the target-volume edit sheet. Do not expose v2 "AI alternatives" UI. |
| **"Swap All"** plan-level swap button | Same decision. Not supported. | Omit from V2. |
| **BPM / heart-rate trophies** (e.g., Neon Pulse) | No HR sensor integration. Already marked Coming Soon in `TrophyDefinitionCatalog`. | Render as Coming Soon tile in V2; do not collect BPM. |
| **KG total volume** (Heavy Metal trophy) | No external load tracking. | Render as Coming Soon. |
| **Burpees** in any exercise library shown in the design | `ExerciseLibrary` does not implement burpees. Already marked Coming Soon. | If a category list in V2 includes burpees, omit. |
| **Calorie / KCAL / MET-style metrics** | Not robustly supported. | Do not surface in V2 unless a future phase ships an estimation model. |
| **Running Analysis active flow** | Phase 20 stub; still research. | Render dashboard card as Coming Soon. |
| **Trophy collection sharing artifacts** (collection poster, trophy unlock card) | Today only the heatmap poster ships in `ShareCardRenderer.swift`. Trophy + workout-recap cards are deferred. | Style the existing share buttons; show trophy/collection share affordances as disabled with "Coming soon" subtitle. |
| **Real account management UI** beyond export / delete | `AccountDeletionService` + `DataExportService` are wired; no edit profile / linked accounts surface. | Style existing export + delete; do not add new account management surfaces. |
| **`workout-evidence.html` rich evidence panels** with metrics like "Range/Depth %", "Quality breakdown by rep", visual rep-by-rep timeline | The data exists (`RepQualityEvent`, `SetQualitySummary.firstHalfAverageFormScore`, etc.) and `WorkoutDetailEvidenceModel.swift` exposes some of it. Some visualizations (range/depth %) are not computed yet. | Implement the evidence views that have data. Stub the ones without data (placeholder card "Coming with the next form-tracking update"). Call them out. |

#### B. Code has features the design does NOT show → **build with same V2 language, also call out**

| Existing code feature | Where it lives | How to style in V2 |
|---|---|---|
| Backend mode debug switch | `ProfileView` Debug section | Profile / settings card; cream border; "DEBUG" eyebrow text |
| Backend status banner (Firebase config missing fallback) | `BackendStatusStore` | Muted card with warning accent (`#FF5C3A` 12% tint border) at top of Profile in firebase mode |
| Sync diagnostics screen (run smoke / push / pull / listeners / pending count / conflicts / lastError) | `SyncOrchestrator` exposes state | DEBUG-only Profile section, card pattern |
| Local + remote data export | `DataExportService` | Settings card with `share.and.arrow.up` icon, destructive-adjacent grouping |
| Delete account/data destructive flow | `AccountDeletionService` | Destructive card with thick `#FF5C3A` border, typed-DELETE confirmation modal |
| Firebase emulator launch arg | DEBUG only | No UI; documented in `DEVELOPMENT_SETUP.md` |
| Insight evidence sheet | `InsightEvidenceSheetView` | Same visual language as `workout-evidence.html`; lime accent on key signals, cream borders, mono metrics |
| Weekly recap composite card | `WeeklyRecapBuilder` produces it | Profile card with `chart-line-up-bold` Phosphor → SF Symbol `chart.line.uptrend.xyaxis`, mono number eyebrow, body copy, "View week" CTA |
| 12-week heatmap drill-in (existing `TrainingHeatmapView` + `DayDrillInSheet`) | Profile section | Heatmap visuals match `profile.html` heatmap section; cells use chart-1 cyan at intensity 1, lime at intensity ≥4, glow on intensity 4 |
| Free-Analysis summary screen | `WorkoutSummaryView` reused for free-analysis | Use workout-summary visual language but eyebrow `FREE ANALYSIS` (not `MISSION COMPLETE`); no trophy stack |
| Camera permission denied state | `BodyVisibilityBannerView` / camera entry | Use `camera-readiness.html` visual language for the denied state too — same card, different copy + Settings CTA |
| Calibration failed / skipped states | `CalibrationStore` + `CalibrationViews` | Use `calibration-1.html` shell with state-specific copy and CTA |
| Empty states everywhere (no profile, no workouts, no trophies, no insights) | Multiple views | Bold display heading + 1-line muted body + lime CTA, no illustrations needed |
| Insight engagement controls (👍 / 👎) | `InsightEngagementControls.swift` | Two small icon-button pills using `GlassInteractiveModifier`, lime tint when helpful, destructive tint when not helpful |
| Local data export progress / result | `DataExportService` returns a URL | Toast or sheet that previews the archive contents with share-sheet CTA |

#### C. Design has features the code DOES support but design rendering may differ → **build using V2 language, prefer code's truth**

| Design element | Code rendering rule |
|---|---|
| Hero stat numbers like `94%` form score, `14d` streak | Use existing computed values from `StatsEngine` / `TrophyEngine`. Never fake. |
| Quick start deck cards | Use `QuickStartPlanDeckService`'s variants; do not fabricate more than what's generated. |
| Coach selector | Bind to existing `CoachPreference` enum. Bennett + Fletcher only. No new personalities. |
| Trophy in-progress / earned states | Bind to `TrophyProgress.earned` + `progressFraction`. Honest about `.unavailable` confidence. |
| Heatmap intensity | Use existing `DayIntensitySummary` from `TrendEngine.dailyIntensitySummary`. |

### 2.3 Feature flag strategy (what GPT said + what I'd add)

GPT's recommendation is good: use `FeatureFlag.designSystemV2Enabled` plus a DEBUG-only local override. I'd add three refinements:

1. **Root-level switch in `VirtualTrainerApp`** — when V2 is on, route to `V2RootView`; when off, route to current `MainTabView`. Do **not** do per-screen feature gating. Root-level is easier to test and revert (which was your stated goal).

2. **Three-state DEBUG override** — `.systemDefault` / `.forceOff` / `.forceOn`. The `.forceOn` lets you switch to V2 in dev without flipping a remote flag. The `.forceOff` lets you confirm V1 still works even when remote says V2 is on.

3. **State preserved on toggle.** A toggle should never reset onboarding, profile, history, trophies, or insights. Stores stay alive; only the SwiftUI view hierarchy swaps. This is naturally true given the `@StateObject` injection pattern in `VirtualTrainerApp`, but the prompt must call it out.

The toggle lives in Profile → Settings → Debug section. After flipping, the entire root view re-renders. No app restart required (SwiftUI handles the swap via the `.id(...)` modifier).

### 2.4 Translation rules: Tailwind HTML → SwiftUI

This is the rosetta stone every design phase prompt must reference. Without it, Codex will misinterpret Tailwind utilities.

| Tailwind | SwiftUI equivalent (using V2 tokens) |
|---|---|
| `bg-background` | `.background(SpotterV2.Tokens.background)` |
| `text-foreground` | `.foregroundStyle(SpotterV2.Tokens.foreground)` |
| `bg-primary` | `.background(SpotterV2.Tokens.primary)` |
| `text-primary` | `.foregroundStyle(SpotterV2.Tokens.primary)` |
| `text-muted-foreground` | `.foregroundStyle(SpotterV2.Tokens.mutedForeground)` |
| `border-2 border-border` | `.overlay(RoundedRectangle(cornerRadius: r).stroke(SpotterV2.Tokens.border, lineWidth: 2))` |
| `border-2 border-primary` | same with primary; the lime variant |
| `rounded-2xl` | `RoundedRectangle(cornerRadius: 16)` |
| `rounded-[24px]` | `RoundedRectangle(cornerRadius: 24)` |
| `rounded-full` | `Capsule()` or `Circle()` depending on aspect |
| `p-4 / p-5 / p-6` | `.padding(16 / 20 / 24)` — map to `SpotterV2.Spacing` |
| `space-y-3 / space-y-6` | `VStack(spacing: 12 / 24)` |
| `gap-3` | `HStack(spacing: 12)` |
| `font-heading` | `.font(SpotterV2.Typography.heading(weight: .black, size: ...))` |
| `font-mono` | `.font(.system(size: ..., weight: .black, design: .monospaced))` |
| `font-sans` | `.font(.system(size: ..., design: .default))` |
| `text-6xl font-black uppercase` | `.font(.system(size: 60, weight: .black))` + `.textCase(.uppercase)` |
| `tracking-tighter` | `.tracking(-1)` (negative letter spacing) |
| `tracking-widest` | `.tracking(2)` |
| `italic` | `.italic()` |
| `leading-[0.85] / leading-tight` | `.lineSpacing(...)` or `.lineLimit(nil) + tight font metrics` |
| `bg-primary/20` | `SpotterV2.Tokens.primary.opacity(0.20)` |
| `backdrop-blur-3xl` | `.background(.ultraThinMaterial)` OR `LiquidGlass.glassSurface()` for the V2 nav |
| `active:scale-95 transition-transform` | `.scaleEffect(isPressed ? 0.95 : 1)` + spring animation |
| `shadow-[4px_4px_0px_0px_#C8FF00]` | Hard-offset cream/lime drop: `.background(...)` + `RoundedRectangle.offset(x: 4, y: 4).fill(color)` underlay (no SwiftUI native equivalent — use a manual stacked rectangle) |
| `shadow-[0_25px_50px_-12px_rgba(0,0,0,0.8)]` | `.shadow(color: .black.opacity(0.8), radius: 25, y: 12)` |
| `animate-pulse` | `.opacity(isOn ? 1 : 0.4)` + `.animation(.easeInOut(duration: 1).repeatForever(), value: isOn)` |
| `mix-blend-luminosity grayscale` | `.colorEffect(.grayscale)` + careful layering; rarely needed in V2 |
| `iconify-icon icon="ph:scan-bold"` | Map to SF Symbol via a single helper table (see prompt D1) |
| `iconify-icon icon="ph:fire-fill"` | `Image(systemName: "flame.fill")` |
| `iconify-icon icon="ph:trophy-fill"` | `Image(systemName: "trophy.fill")` |
| `iconify-icon icon="ph:barbell-bold"` | `Image(systemName: "figure.strengthtraining.traditional")` (closest SF Symbol) |
| `iconify-icon icon="ph:camera-fill"` | `Image(systemName: "camera.fill")` |
| `iconify-icon icon="ph:scan-bold"` | `Image(systemName: "viewfinder")` |
| `iconify-icon icon="ph:house-fill"` | `Image(systemName: "house.fill")` |
| `iconify-icon icon="ph:user-fill"` | `Image(systemName: "person.fill")` |
| `iconify-icon icon="ph:chart-line-up-fill"` | `Image(systemName: "chart.line.uptrend.xyaxis"`) |
| `iconify-icon icon="ph:arrow-right-bold"` | `Image(systemName: "arrow.right")` |
| `iconify-icon icon="ph:play-fill"` | `Image(systemName: "play.fill")` |
| `iconify-icon icon="ph:lightbulb-fill"` | `Image(systemName: "lightbulb.fill")` |
| `iconify-icon icon="ph:brain-fill"` | `Image(systemName: "brain.head.profile"`) |
| `iconify-icon icon="ph:share-network-fill"` | `Image(systemName: "square.and.arrow.up.fill"`) |
| `iconify-icon icon="ph:lock-key-bold"` | `Image(systemName: "lock.fill"`) |

Custom fonts (DM Sans / Space Grotesk / JetBrains Mono / Playfair Display) are **NOT** to be bundled in the first design pass. Use safe system fallbacks via `.system(..., design: .rounded)` for heading and `.system(..., design: .monospaced)` for mono. Bundle the fonts in a later polish phase after the design lands and licensing is confirmed.

---

## Part 3 — Execution order

```
P17.5    — Backend hardening (rules root-doc + tombstone idempotency + privacy + emulator tests)
D0       — Design inventory + design-vs-code delta document
D1       — V2 design tokens + reusable components + feature flag + DEBUG override
D2       — V2 app shell + liquid glass nav (custom bottom tab bar)
D3       — V2 onboarding + calibration
D4       — V2 dashboard + camera/form-check
D5       — V2 workout flow (preview / target edit / live HUD shell / rest / summary)
D6       — V2 profile + trophies + history + evidence + account surfaces
D7       — Design QA, accessibility, edge cases
Phase 19 — Beta / TestFlight / App Store readiness  (unchanged from earlier plan)
Phase 20 — Running Analysis research stub           (unchanged from earlier plan)
```

Calendar:
- P17.5: **1–2 days**
- D0: **0.5 day**
- D1–D2: **2–3 days each** (foundation work, slow because nav fallback matters)
- D3–D6: **2–4 days each**
- D7: **3 days**

Total design revamp: **2.5–3 weeks** with Codex assist.

---

## Part 4 — Universal V2 design preflight (paste at top of every design prompt)

```
You are working in the Spotter iOS Swift repository on the V2 design
system revamp. Before changing code:

1. Inspect the current tree end-to-end. Read:
   - README.md
   - DEBUG_LOG.md (latest entries, especially DL-045 toolchain trap)
   - Documentation/DEVELOPMENT_SETUP.md
   - Documentation/FirestoreShape.md
   - Documentation/SyncConflictResolution.md
   - Documentation/BackendQAChecklist.md
   - Documentation/firestore.rules
   - Documentation/DesignSystemV2Inventory.md (created in D0)
   - VirtualTrainer/DesignSystem/Theme.swift
   - VirtualTrainer/DesignSystem/LiquidGlass.swift
   - VirtualTrainer/DesignSystem/SpotterV2Tokens.swift   (after D1)
   - VirtualTrainer/DesignSystem/SpotterV2Typography.swift
   - VirtualTrainer/DesignSystem/SpotterV2Components.swift
   - VirtualTrainer/Services/FeatureFlags.swift
   - VirtualTrainer/Services/DesignSystemV2ToggleStore.swift  (after D1)
   - VirtualTrainer/Models/ThemeStore.swift
   - VirtualTrainer/UI/MainTabView.swift
   - The screen(s) under VirtualTrainer/UI/ being revamped in this phase
   - NEW_DESIGN/export-html/<the matching screen>.html
   - NEW_DESIGN/screenshots/<the matching screen>.png

2. Treat NEW_DESIGN HTML as visual/product reference, not production code.
   - Do NOT use WebView.
   - Do NOT embed Tailwind, iconify, Phosphor, or external fonts in this
     phase. Use SF Symbols and system fonts.
   - Translate Tailwind utilities and Phosphor icons using the rosetta
     table in Spotter_DesignV2_Forward_Plan.md Section 2.4.

3. Do NOT change MediaPipe, CameraManager, PoseEstimator, UniversalRepCounter,
   FormFeedbackEngine, HandGestureDetector, ExertionAnalyzer,
   WorkoutReadyCoordinator, FaceLandmarkerService, FramePositionAnalyzer,
   or any live camera pipeline behavior.

4. Do NOT change backend repository behavior, Firestore sync, privacy
   rules, or any backend file, unless the prompt explicitly says so.

5. Preserve both training flows (Camera tab Free Analysis AND Planned
   Workouts) and both backend modes (.local and .firebase).

6. The V2 design MUST be behind the feature flag/toggle introduced in D1.
   When the toggle is OFF or the remote flag is OFF, the app must render
   the current V1 UI unchanged. When ON, V2 renders.

7. The toggle MUST NOT reset onboarding, calibration, profile, history,
   trophies, or insights. Stores stay alive; only the SwiftUI hierarchy
   swaps.

8. Design-vs-code deltas (see Spotter_DesignV2_Forward_Plan.md Section 2.2):
   - If the design shows a feature the code does NOT support today
     (login, smart swaps, BPM trophies, KG volume trophies, calorie
     metrics, running analysis active, burpees, real account management,
     etc.) — do NOT build it. Render as disabled/coming-soon or omit.
     List every such design-only feature you encountered in this phase
     in the PR summary.
   - If the code has a feature the design does NOT show (backend status
     debug, sync diagnostics, export, delete account, free-analysis
     summary, weekly recap, insight evidence sheet, heatmap drill-in,
     calibration failed/skipped states, empty states, engagement
     controls) — STYLE IT using the V2 tokens/components/typography from
     similar design surfaces. List every such code-only feature you
     styled.

9. Do NOT hardcode raw hex colors inside feature screens. Use V2 tokens
   (SpotterV2.Tokens.*) and per-theme accent via SpotterThemeOption.

10. Do NOT assume custom fonts are bundled. Use system fonts via
    .system(size:weight:design:). The design-typography helpers in
    SpotterV2Typography.swift wrap this; use them.

11. Support iPhone SE (small) through Pro Max. Respect safe areas, Dynamic
    Type at least Large, VoiceOver labels on every interactive element,
    Reduce Motion (disable scale/opacity animations when on), Reduce
    Transparency (fall back to solid surfaces when on, especially for the
    liquid glass nav).

12. Toolchain: use the bundled Xcode toolchain (XcodeDefault.xctoolchain).
    See DEBUG_LOG DL-045. Verify with:
        xcrun --find clang
        xcrun --find swiftc
    Both must resolve under
    /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain.

13. Builds: always use VirtualTrainer.xcworkspace, never the bare xcodeproj.
    Do not run parallel xcodebuild test commands against the same
    DerivedData path.

14. After the phase, run:
        xcodebuild build  -workspace VirtualTrainer.xcworkspace \
            -scheme VirtualTrainer \
            -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
            -derivedDataPath /tmp/VirtualTrainerDerivedData
        xcodebuild test   -workspace VirtualTrainer.xcworkspace \
            -scheme VirtualTrainer \
            -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
            -derivedDataPath /tmp/VirtualTrainerDerivedData
    Summarize PASS/FAIL counts.

15. Add SwiftUI previews for every new V2 view across the four themes
    (Hyper, Hot Girl, Warm, Spicy) and at least two device sizes
    (iPhone SE 3rd gen, iPhone 17 Pro Max). Snapshot tests where the
    project convention supports it.

16. Append a DEBUG_LOG.md entry following the existing format if the
    phase changes behavior, adds plumbing, or fixes a failure.

17. PR summary must include:
    - Changed files
    - V2 components introduced
    - V1 surfaces that remain unchanged
    - Feature-flag-off verification screenshot description
    - Feature-flag-on verification screenshot description
    - Design-only features encountered (deferred, listed)
    - Code-only features styled in V2 language (listed)
    - Known follow-ups
```

---

## Part 5 — Design phase prompts (Codex-ready)

### D0 — Design inventory + delta document

```
Use the V2 design preflight block.

D0 goal: produce a single design inventory + delta document. Do NOT
write any UI code in this phase.

TASKS

1. Inventory all 29 HTML files in NEW_DESIGN/export-html/ and the 29
   screenshots in NEW_DESIGN/screenshots/. Group them by feature area.

2. For each HTML screen, record in Documentation/DesignSystemV2Inventory.md:
   - Screen name + filename
   - Matching current SwiftUI screen (or "no equivalent yet")
   - Hero text strings (so we keep them stable)
   - Key components used (cards, CTAs, metrics, lists, sheets)
   - Design-only features the code does not support
   - Implementation phase assignment (D2-D6)

3. Document design tokens extracted from the :root blocks:
   - Colors (verify all four theme previews share the same :root)
   - Typography
   - Radius scale
   - Border widths
   - Spacing scale (from p-3/p-4/p-5/p-6/p-8 and m-* utilities)
   - Shadows (especially the hard-offset cream/lime drop)
   - Motion (active:scale-95, animate-pulse, etc.)

4. Document Phosphor → SF Symbol mapping in
   Documentation/PhosphorToSFSymbolMap.md. Walk every iconify-icon ph-*
   reference in the HTML files. For any Phosphor icon that has no clean
   SF Symbol equivalent, record the choice (closest SF Symbol or custom
   SF Symbol replacement plan).

5. Document the delta tables from Section 2.2 of
   Spotter_DesignV2_Forward_Plan.md inside DesignSystemV2Inventory.md:
   - Design-only features → do not build (list with screen ref).
   - Code-only features → build using V2 language (list with file ref).
   - Design + code parity but rendering differences → align to code's
     truth.

6. List the per-theme accent values that should override the constant
   palette in Swift (Hyper / Hot Girl / Warm / Spicy). Confirm they
   match the existing SpotterThemeOption.accentColor /
   .secondaryAccentColor values in DesignSystem/Theme.swift.

7. Identify any HTML that uses imagery not present in the repo (coach
   portraits, hero images). Decide per image: bundle from existing
   Assets.xcassets, swap for an SF Symbol, or skip.

ACCEPTANCE
- Documentation/DesignSystemV2Inventory.md exists, exhaustive.
- Documentation/PhosphorToSFSymbolMap.md exists, exhaustive.
- No UI code changed.
- DEBUG_LOG entry recorded.
```

---

### D1 — V2 design tokens + components + feature flag + DEBUG override

```
Use the V2 design preflight block.

D1 goal: create the V2 design system foundation behind a feature flag.
Old screens stay rendered by the current code. Build reusable V2
components and a debug-visible gallery to verify them.

TASKS

1. Feature flag wiring.

The existing FeatureFlag.designSystemV2Enabled stays as the remote flag.
Add a DEBUG-only local override stored in UserDefaults:

Models/DesignSystemV2ToggleStore.swift

  enum DesignSystemV2Override: String, Codable, CaseIterable {
      case systemDefault
      case forceOff
      case forceOn
  }

  @MainActor
  final class DesignSystemV2ToggleStore: ObservableObject {
      static let userDefaultsKey = "spotter.designSystemV2Override"

      @Published var override: DesignSystemV2Override
      private let remoteFlagSnapshotProvider: () -> Bool

      init(remoteFlagSnapshotProvider: @escaping () -> Bool,
           userDefaults: UserDefaults = .standard) { ... }

      var isEffectivelyEnabled: Bool {
          #if DEBUG
          switch override {
          case .forceOn: return true
          case .forceOff: return false
          case .systemDefault: return remoteFlagSnapshotProvider()
          }
          #else
          return remoteFlagSnapshotProvider()
          #endif
      }

      func setOverride(_ override: DesignSystemV2Override) { ... }
  }

Inject this as a @StateObject in VirtualTrainerApp. Bind the
remoteFlagSnapshotProvider to RemoteFeatureFlagService.snapshot().
designSystemV2Enabled.

2. Design tokens.

Create DesignSystem/SpotterV2Tokens.swift:

  enum SpotterV2 {
      enum Tokens {
          // Constants across all four themes (verified by inspection of
          // all NEW_DESIGN HTML :root blocks):
          static let background     = Color(hex: 0x0D0D0D)
          static let foreground     = Color(hex: 0xF2F0EB)
          static let secondary      = Color(hex: 0x262626)
          static let muted          = Color(hex: 0x262626)
          static let mutedForeground = Color(hex: 0xA3A3A3)
          static let destructive    = Color(hex: 0xFF5C3A)
          static let card           = Color(hex: 0x0D0D0D)
          static let border         = Color(hex: 0xF2F0EB)
          static let chart1         = Color(hex: 0x00D1FF)   // cyan
          static let chart3         = Color(hex: 0xFF5C3A)   // orange-red
          static let chart4         = Color(hex: 0x525252)
          static let chart5         = Color(hex: 0x262626)

          // Per-theme accent comes from SpotterThemeOption, NOT a constant.
          static func primary(_ theme: SpotterThemeOption) -> Color {
              theme.accentColor
          }
          static func chart2(_ theme: SpotterThemeOption) -> Color {
              theme.accentColor
          }
          static func ring(_ theme: SpotterThemeOption) -> Color {
              theme.accentColor
          }
      }

      enum Spacing {
          static let xxxs: CGFloat = 2
          static let xxs:  CGFloat = 4
          static let xs:   CGFloat = 8
          static let sm:   CGFloat = 12
          static let md:   CGFloat = 16
          static let lg:   CGFloat = 20
          static let xl:   CGFloat = 24
          static let xxl:  CGFloat = 32
          static let xxxl: CGFloat = 48
      }

      enum Radius {
          static let xs:  CGFloat = 8
          static let sm:  CGFloat = 12
          static let md:  CGFloat = 16   // matches rounded-2xl
          static let lg:  CGFloat = 20
          static let xl:  CGFloat = 24
          static let xxl: CGFloat = 32   // matches rounded-[32px]
          static let pill: CGFloat = 999
      }

      enum BorderWidth {
          static let standard: CGFloat = 2
          static let bold: CGFloat = 4   // for hero cards: border-4
      }

      enum Motion {
          static let snappy: Animation = .snappy(duration: 0.22)
          static let press:  Animation = .easeInOut(duration: 0.12)
          static let pulse:  Animation = .easeInOut(duration: 1.2).repeatForever()
      }
  }

  // Hex color helper:
  extension Color {
      init(hex: UInt32) { ... }
  }

3. Typography.

Create DesignSystem/SpotterV2Typography.swift:

  enum SpotterV2Typography {
      static func display(size: CGFloat = 56) -> Font {
          .system(size: size, weight: .black, design: .default)
      }
      static func heading(size: CGFloat, weight: Font.Weight = .black) -> Font {
          .system(size: size, weight: weight, design: .default)
      }
      static func body(size: CGFloat = 16, weight: Font.Weight = .medium) -> Font {
          .system(size: size, weight: weight, design: .default)
      }
      static func mono(size: CGFloat, weight: Font.Weight = .black) -> Font {
          .system(size: size, weight: weight, design: .monospaced)
      }
      static func caption(weight: Font.Weight = .black) -> Font {
          .system(size: 10, weight: weight, design: .default)
      }
  }

Note: do NOT bundle DM Sans / Space Grotesk / JetBrains Mono / Playfair
Display in this phase. Use system fonts. A future polish phase can swap
to bundled fonts once licensing is confirmed.

4. Reusable components.

Create DesignSystem/SpotterV2Components.swift with these views, each
with previews across all four themes and iPhone SE + iPhone 17 Pro Max:

- V2Card           — cream border, near-black fill, configurable radius,
                     optional hard-offset drop shadow
- V2CTAButton      — full-width, 64 pt tall, 24 pt radius, primary fill,
                     black text, all-caps, uppercase tracking, active
                     scale 0.97
- V2SecondaryButton — border-2 cream, transparent fill, cream text
- V2DestructiveButton — destructive fill, white text
- V2MetricPill      — uppercase eyebrow + mono metric value, used for
                     dashboard stat cards
- V2StatusPill      — small uppercase chip, pulsing dot variant
- V2SectionHeader   — uppercase tracked title, optional trailing CTA
- V2ProgressRing    — circular ring with mono center number
- V2HeroNumber      — huge italic mono number for hero stats (5xl-6xl)
- V2InsightCard     — accent-tinted card with eyebrow + headline + body,
                     engagement controls inline
- V2WorkoutHistoryRow — date capsule, title, mode pill, metrics
- V2ExerciseRow      — index circle, name, target chip
- V2TrophyCard       — icon, title, subtitle, rarity badge, progress
- V2ThemeOptionCard  — color swatch grid, name, selected ring
- V2EmptyState       — bold display heading + body + CTA
- V2BottomSheetShell — drag indicator + close button + content slot
- V2BackendStatusChip — DEBUG-only chip showing backend mode

5. Design gallery (DEBUG-only).

Create UI/DesignSystemV2GalleryView.swift listing every component
across all four themes. Reachable from Profile → Settings → Debug →
"V2 Design Gallery" in DEBUG builds only.

6. Tests.

Add tests:
- Hex-color helper round-trip.
- All Spotting tokens distinguish from V1 (no token name collision).
- DesignSystemV2ToggleStore: forceOn returns true even when remote false.
  forceOff returns false even when remote true. systemDefault delegates
  to the provider.
- Snapshot smoke tests for V2Card / V2CTAButton / V2MetricPill across
  Hyper + Hot Girl themes.

7. Wire feature flag in VirtualTrainerApp.

In the @main body, after dependency injection, branch the root:

  if designSystemV2Toggle.isEffectivelyEnabled {
      V2RootView()        // stub in D1: just an empty view with
                          // "V2 Design System — placeholder" text
  } else {
      currentRootSwitch   // onboarding → calibration → MainTabView
  }

This branch should re-render when isEffectivelyEnabled changes via
.id(designSystemV2Toggle.isEffectivelyEnabled) on the Group.

8. Add the DEBUG override picker.

In Profile → Settings → Debug, add a new "Design System V2" section:
- Current effective state (with eyebrow "DEBUG")
- Picker: System default / Force on / Force off
- Live update; no restart required.

ACCEPTANCE
- All V2 token / typography / component files exist with previews.
- Feature flag wired; V1 unchanged when off; V2 placeholder shown when on.
- DEBUG override works.
- DEBUG-only design gallery reachable.
- All existing 335+ tests still pass.
- DEBUG_LOG DL-### entry recorded.
- PR summary lists design-only and code-only features encountered.
```

---

### D2 — V2 app shell + liquid glass nav (custom bottom tab bar)

```
Use the V2 design preflight block.

D2 goal: replace the placeholder V2RootView with the real V2 app shell.
Build a custom liquid glass bottom tab bar that uses LiquidGlass.swift
and falls back gracefully.

TASKS

1. V2RootView.

UI/V2/V2RootView.swift
  - Mirrors the current root logic: onboarding gate → calibration gate →
    main shell.
  - When ready, shows V2MainShellView.
  - Inherits all environment objects from VirtualTrainerApp.
  - Onboarding/calibration screens in V2 ship in D3; until then, render
    the V1 onboarding/calibration but route the post-calibration tab
    container to V2MainShellView. This guarantees the user can still
    onboard with V2 toggled on.

2. V2MainShellView.

UI/V2/V2MainShellView.swift
  - Holds @State private var selectedTab: V2Tab = .dashboard.
  - Renders the selected tab's content full-screen (no SwiftUI TabView
    chrome — implement the tab switch manually so the bottom nav isn't
    constrained by TabView's default bar).
  - Uses ZStack { content; V2LiquidGlassTabBar(...).overlay alignment
    .bottom }.
  - The four tabs route to V2 stub views in this phase
    (V2DashboardPlaceholder, V2CameraPlaceholder, V2TrophiesPlaceholder,
    V2ProfilePlaceholder) that display "Coming in D4 / D6" placeholders.
    These are replaced by real V2 screens in D4–D6.

3. V2LiquidGlassTabBar.

UI/V2/V2LiquidGlassTabBar.swift
  - Floating pill: width 92% of screen, max width 440 pt, height 92 pt,
    cornerRadius 46 pt.
  - Position: 10 pt from bottom safe area inset.
  - 4 icon buttons evenly spaced:
      Dashboard: SF Symbol "house.fill"
      Camera:    SF Symbol "camera.fill"
      Trophies:  SF Symbol "trophy.fill"
      Profile:   SF Symbol "person.fill"
  - Selected tab: white/10 fill chip with primary-tint border, larger
    icon scale (1.1), accent color tint.
  - Unselected tab: muted-foreground icon color, no fill chip.
  - Tap haptic: light impact.
  - VoiceOver: each button has accessibilityLabel ("Dashboard", etc.)
    and accessibilityValue ("Selected" / "Not selected").

  Implementation strategy:
    enum V2NavStyle { case liquidGlass, solid }

    @ViewBuilder
    func navBackground(style: V2NavStyle) -> some View {
        switch style {
        case .liquidGlass:
            EmptyView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassSurface(cornerRadius: 46)  // existing LiquidGlass modifier
                .overlay(
                    RoundedRectangle(cornerRadius: 46)
                        .stroke(Color.white.opacity(0.20), lineWidth: 2)
                )
                .shadow(color: .black.opacity(0.8), radius: 25, y: 12)
        case .solid:
            RoundedRectangle(cornerRadius: 46)
                .fill(Color.black.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 46)
                        .stroke(SpotterV2.Tokens.border, lineWidth: 2)
                )
        }
    }

    // Resolve style at runtime:
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var resolvedNavStyle: V2NavStyle {
        reduceTransparency ? .solid : .liquidGlass
    }

4. Keyboard / safe area / sheet handling.

  - The nav uses .ignoresSafeArea(edges: .bottom) only for its background
    glow; the bar itself respects the safe area inset.
  - When the iOS keyboard is presented, the nav hides via
    @State private var isKeyboardVisible: Bool plus a
    NotificationCenter.publisher binding. SwiftUI's
    .interactiveDismissDisabled() and keyboardAvoidance defaults stay
    untouched on inner views.
  - When a SwiftUI .sheet or .fullScreenCover is presented, the nav
    naturally disappears because it's covered.
  - Live camera session (TrainerSessionView) is full-screen overlay;
    the nav should hide while a workout session is active. Use a shared
    AppLevelPresenterEnvironmentKey (new helper) that the camera tab
    flips when starting a session, and the nav reads from to hide.

5. DEBUG backend status chip.

In V2MainShellView, add a tiny V2BackendStatusChip pinned to the
top-right safe area, visible only in #if DEBUG and only when
BackendStatusStore.activeBackendMode != .local. Tapping it routes to
the V2 sync diagnostics screen (deferred to D6; for now, present a
sheet with the basic status text).

6. Previews + tests.

Previews:
  - iPhone SE 3rd gen
  - iPhone 17 Pro Max
  - Reduce Transparency on/off
  - Each tab selected
  - Each of the four themes

Tests:
  - V2 toggle off renders the existing MainTabView.
  - V2 toggle on renders V2MainShellView.
  - Switching toggle does not reset onboarding, profile, history.
  - reduceTransparency → solid nav style.

ACCEPTANCE
- V1 unchanged with toggle off.
- V2 shell renders with the four tabs and liquid glass nav with toggle
  on.
- Nav respects safe area, keyboard, sheets, and live workouts.
- Reduce Transparency uses solid fallback.
- Tests pass.
- DEBUG_LOG DL-### entry.
- PR summary lists which V2 tab placeholders are wired now vs deferred
  to D4–D6.
```

---

### D3 — V2 onboarding + calibration

```
Use the V2 design preflight block.

D3 goal: rebuild welcome, onboarding identity, onboarding stats,
onboarding objective, calibration intro, and camera readiness screens
in V2 style behind the feature flag.

Reference screens:
- NEW_DESIGN/export-html/welcome-screen.html
- NEW_DESIGN/export-html/onboarding-identity.html
- NEW_DESIGN/export-html/onboarding-stats-v2.html
- NEW_DESIGN/export-html/onboarding-objective.html
- NEW_DESIGN/export-html/calibration-1.html
- NEW_DESIGN/export-html/camera-readiness.html

Current code to bind to (do NOT change behavior):
- VirtualTrainer/UI/OnboardingViews.swift
- VirtualTrainer/UI/CalibrationViews.swift
- VirtualTrainer/Models/OnboardingStore.swift
- VirtualTrainer/Models/CalibrationStore.swift
- VirtualTrainer/Coaching/WorkoutReadyCoordinator.swift

TASKS

1. V2WelcomeView.

UI/V2/Onboarding/V2WelcomeView.swift
  - Match welcome-screen.html: scan-body icon eyebrow, 6xl heading
    "Your\nAI Form\nCoach" with the lime "Coach" word, supporting copy
    "Never train alone again."
  - Two stacked cards (border-primary hero with image masked dark; two
    aspect-square child cards: coach picker preview, lock icon
    "100% LOCAL & SECURE").
  - Bottom-anchored "Get Started" V2CTAButton.
  - "Already have an account? Log in" link:
      DESIGN-ONLY DELTA: SIWA + revocation is not yet implemented.
      Render the link visually but with onTapGesture that presents a
      "Sign in with Apple is coming soon" alert.
      Alternatively: hide entirely behind a future feature flag
      (FeatureFlag.signInWithApple, default false). Pick the alert
      approach for V2 launch — preserves the design's visual rhythm.
      List in the PR as a deferred feature.

2. V2OnboardingIdentityView.

UI/V2/Onboarding/V2OnboardingIdentityView.swift
  - Bind to OnboardingDraft.displayName, .genderIdentity, .age via the
    existing @EnvironmentObject onboardingStore.
  - Mirror onboarding-identity.html layout exactly: tracked uppercase
    eyebrow, large heading per field, V2 selector tiles for gender,
    numeric field for age with validation message.
  - Continue button uses V2CTAButton, disabled until
    onboardingStore.canContinue(from: .identity).

3. V2OnboardingStatsView.

UI/V2/Onboarding/V2OnboardingStatsView.swift
  - Match onboarding-stats-v2.html: height + weight + unit toggle
    (metric / imperial).
  - Reuse OnboardingStore.updateHeightUnit / updateWeightUnit logic;
    do not duplicate.

4. V2OnboardingObjectiveView.

UI/V2/Onboarding/V2OnboardingObjectiveView.swift
  - Match onboarding-objective.html: primary goal selector (Strength /
    Performance / Longevity), fitness level chips, equipment toggle
    grid, limitations toggle list, session length picker, days per
    week stepper.
  - Show subtitle copy from existing FitnessGoal.subtitle / etc.
  - If design omits one of these (e.g., days-per-week), build it
    using the V2 selector pattern from coach-selector.html. Call it
    out in the PR.

5. V2CalibrationIntroView.

UI/V2/Calibration/V2CalibrationIntroView.swift
  - Match calibration-1.html: "Earn your first trophy" eyebrow,
    "Track 3 air squats" headline, illustration card, primary "Start
    Calibration" CTA, secondary "Skip for now" CTA.
  - Wire Start to existing CalibrationStore flow (it routes into the
    live camera; do not change that flow).
  - Wire Skip to CalibrationStore.saveSkipped (only if app config
    permits skipping).

6. V2CameraReadinessView.

UI/V2/Camera/V2CameraReadinessView.swift
  - Match camera-readiness.html for the "Ready" state: viewfinder
    illustration, instructions, primary "Start Tracking" CTA.
  - For permission-denied state: same shell, copy-only swap,
    secondary CTA "Open Settings" via UIApplication.shared.open.
  - For visibility issue state: same shell, copy swap, no CTA
    (auto-recovers).
  - Wire to existing WorkoutReadyCoordinator state via a small
    V2CameraReadinessAdapter that maps coordinator states to UI
    states. Do not change coordinator behavior.

7. Motion.

- Page transitions between onboarding steps: .opacity.combined(with:
  .move(edge: .trailing)) on push, reverse on pop.
- CTA press: .scaleEffect(0.97) on isPressed.
- Calibration starting countdown: respect reduceMotion.

8. Tests.

- V2 onboarding can complete and writes UserProfile via OnboardingStore.
- V2 calibration completion calls CalibrationStore.saveCompleted with
  the same args as V1.
- V2 camera readiness denied state shows Settings CTA.
- "Log in" link presents the coming-soon alert; does NOT call any
  Firebase auth method.
- Snapshot tests for each V2 screen on iPhone SE + iPhone 17 Pro Max,
  Hyper + Hot Girl themes.
- V1 unchanged when toggle off.

ACCEPTANCE
- Six V2 screens render correctly.
- Existing onboarding/calibration data persists unchanged.
- The "Log in" delta is implemented as a coming-soon alert, listed in
  the PR.
- V1 onboarding still works when toggle off.
- DEBUG_LOG entry recorded.
```

---

### D4 — V2 dashboard + camera/form-check

```
Use the V2 design preflight block.

D4 goal: rebuild Dashboard / Quick Start and Camera / Form Check
screens in V2 style.

Reference screens:
- NEW_DESIGN/export-html/quick-start.html
- NEW_DESIGN/export-html/liquid-glass-nav-iteration.html (the dashboard
  body in this variant is also valid reference)
- NEW_DESIGN/export-html/form-check-selection.html

Current code:
- VirtualTrainer/UI/HomeDashboardView.swift
- VirtualTrainer/UI/CameraTabView.swift
- VirtualTrainer/Models/DashboardData.swift
- VirtualTrainer/Services/QuickStartPlanDeckService.swift
- VirtualTrainer/Services/PlanService.swift
- VirtualTrainer/Models/WorkoutHistoryStore.swift
- VirtualTrainer/Services/RemoteFeatureFlagService.swift
- VirtualTrainer/Services/InsightEngine.swift

TASKS

1. V2DashboardView.

UI/V2/Dashboard/V2DashboardView.swift
  - Greeting card top: "Hello, [first name]" all-caps italic 4xl heading,
    pulsing dot + "Status: Training Active" eyebrow.
  - Right side: 14 pt circular avatar (use Image(systemName: "person.fill")
    fallback or the user's initials in a cream-bordered square).
  - Next Milestone card: lime-tinted background, lime border, barbell
    icon, eyebrow "Next Milestone", primary label "Squat Depth: +2cm"
    (use the next-trophy near-miss from TrophyEngine; if none, hide).
  - 2x2 metric grid: Form Score + Consistency Streak + Recent Form
    Trend + Weekly Volume. Use existing computed values from
    StatsEngine / TrendEngine. Each tile: border-4 cream, aspect-square,
    icon top-left, hero mono number bottom, eyebrow caption.
  - Smart Start card: full width, recommended Quick Start plan from
    QuickStartPlanDeckService. Title + duration + reason + lime "Start
    Training" CTA + secondary "Shuffle" icon button.
  - Daily Plan card if profile has a daily plan selected.
  - Coach Insight card: bind to first InsightEngine.generateDashboardInsights
    result for the .dashboard surface; uses V2InsightCard.
  - Trophy Teaser card: bind to TrophyStore.snapshot.nearestInProgress.
  - Recent Workout card: bind to WorkoutHistoryStore.fetchRecentSummaries(limit: 1).
  - Running Analysis card (Coming Soon, design-only delta listed).

2. V2CameraTabView.

UI/V2/Camera/V2CameraTabView.swift
  - Form Check Selection screen as the primary content.
  - Match form-check-selection.html: hero eyebrow + heading, category
    chips at top (Upper / Lower / Core / Cardio / Yoga / Mobility —
    derive from ExerciseMetadataCatalog.bodyRegion + .movementPattern).
  - Exercise list: V2ExerciseRow per supported ExerciseType, with
    difficulty pill and "Train Free" CTA.
  - Tapping an exercise routes into the existing free-analysis camera
    flow via the same CameraTabView state — do NOT duplicate camera
    setup logic.
  - Search field: bind to existing search if present, otherwise
    implement a simple .searchable. Filter by ExerciseType.displayName.

3. Exercise library filtering.

If the design implies categories not in ExerciseMetadataCatalog (e.g.,
"HIIT", "Calisthenics"), use the nearest movement-pattern/body-region
combination. Do NOT add unsupported exercises (no burpees, no pull-ups
if not in the library).

4. Empty / error states.

- No profile → "Complete onboarding to see your dashboard" with
  V2CTAButton routing to V2OnboardingFlow.
- No history yet → Smart Start card stays; metric tiles show "—" with
  caption "Save your first workout to see this".
- Camera permission denied (Camera tab) → V2 empty state with Settings
  CTA.
- Poor visibility from readiness coordinator → muted card with body
  copy from BodyVisibilityBannerView.

5. Backend status banner.

If BackendStatusStore.activeBackendMode != desiredBackendMode (i.e.,
fallback to local), show a thin V2 banner above the dashboard scroll
content with the userFacingMessage. Dismissable. Persist dismissed
state in UserDefaults so it doesn't nag.

6. Tests.

- V2 dashboard starts the selected Quick Start plan when CTA tapped.
- Shuffle cycles the Quick Start deck.
- Coach insight card surfaces when InsightEngine has a candidate.
- V2 camera tab launches free analysis with the same args as V1.
- Backend banner appears only when fallback active.
- V1 dashboard untouched when toggle off.
- Snapshot tests for V2 dashboard with: empty history, rich history,
  Hyper + Hot Girl themes.

ACCEPTANCE
- Dashboard and Camera V2 match the design direction.
- All metric numbers bind to real data (no fabrication).
- Smart Start and free analysis flows work.
- Coming Soon items (Running Analysis) clearly labeled.
- DEBUG_LOG entry.
```

---

### D5 — V2 workout flow

```
Use the V2 design preflight block.

D5 goal: rebuild the workout flow — preview, target edit, live HUD,
rest, summary — in V2 style.

Reference screens:
- NEW_DESIGN/export-html/workout-preview.html
- NEW_DESIGN/export-html/coach-selector.html
- NEW_DESIGN/export-html/exercise-swap-sheet-v1.html
- NEW_DESIGN/export-html/exercise-swap-sheet-v2.html  (do NOT build v2; AI swap is deferred)
- NEW_DESIGN/export-html/live-workout.html
- NEW_DESIGN/export-html/rest-screen.html
- NEW_DESIGN/export-html/workout-summary.html

Current code:
- VirtualTrainer/UI/WorkoutPreviewView.swift
- VirtualTrainer/UI/PlannedWorkoutSessionView.swift
- VirtualTrainer/UI/TrainerSessionView.swift
- VirtualTrainer/UI/TrainerOverlayView.swift
- VirtualTrainer/UI/RestScreenView.swift
- VirtualTrainer/UI/WorkoutSummaryView.swift
- VirtualTrainer/UI/TargetVolumeEditSheetView.swift
- VirtualTrainer/Services/PlanTargetEditService.swift

Product decisions to honor:
- NO plan-level "Swap All" (design-only delta).
- NO AI exercise alternatives (design-only delta).
- ONLY target volume editing.

TASKS

1. V2WorkoutPreviewView.

UI/V2/Workout/V2WorkoutPreviewView.swift
  - Plan title, estimated duration, coach pill, goal/focus chip.
  - Plan-specific insight card from InsightEngine.generatePlanInsights.
  - Exercise list: V2ExerciseRow with target chip ("3 x 12 reps").
  - Each row has an "Adjust" icon button opening V2TargetVolumeEditSheet.
  - Coach selector inline pill (Bennett / Fletcher) bound to existing
    coach preference flow.
  - Bottom-anchored "Start Workout" V2CTAButton.
  - No Swap All. No AI alternatives. Call out in PR.

2. V2TargetVolumeEditSheet.

UI/V2/Workout/V2TargetVolumeEditSheet.swift
  - Uses V2BottomSheetShell.
  - Match exercise-swap-sheet-v1.html visual language: "Adjust Movement"
    title, exercise name, hero target value, sets stepper, reps/seconds
    stepper depending on target type.
  - "Save Changes" V2CTAButton.
  - "Reset to Original Plan" V2SecondaryButton.
  - Bind to existing PlanTargetEditService.

3. V2LiveWorkoutShell.

UI/V2/Workout/V2LiveWorkoutShell.swift
  - This is the HUD layer over the camera. It does NOT own the camera;
    TrainerSessionView/TrainerOverlayView own pose + skeleton.
  - Style match live-workout.html: exercise name eyebrow, set count
    pill top-left, rep count hero mono number center-top, form score
    pill (cyan tint), current cue text bottom-card, effort indicator
    (rising/steady/falling arrow), skip + finish buttons.
  - Place over existing TrainerOverlayView via overlay alignment.
  - Bind to existing trainer session state. Do NOT touch the camera
    pipeline.

4. V2RestScreenView.

UI/V2/Workout/V2RestScreenView.swift
  - Match rest-screen.html: large mono countdown timer, "Skip Rest" +
    "+15 sec" buttons, Last Set summary card with reps/form/range/cue,
    Coach note card with insight one-liner, Up Next preview card,
    "Start Set" V2CTAButton.
  - Bind to existing RestScreenView state / coordinator. Wrap, don't
    replace.

5. V2WorkoutSummaryView.

UI/V2/Workout/V2WorkoutSummaryView.swift
  - Eyebrow "MISSION COMPLETE" for planned workouts; eyebrow
    "FREE ANALYSIS" for free-analysis sessions (code-only delta).
  - Hero stat block: duration, total reps, completion %.
  - Form quality card with cyan chart accent.
  - Exercise list with per-exercise reps + form score.
  - Coach insight card if InsightEngine returns one.
  - Streak card.
  - Newly earned trophies stack (TrophyUnlockEventCard styled in V2).
  - If no trophy earned, show "Closest trophy" V2TrophyCard.
  - "Done" V2CTAButton bottom-anchored.
  - Secondary "View Detail" routes to V2WorkoutDetailSheet (D6).
  - Sync pending banner if syncMetadata.syncState == .pendingUpload
    (a V2StatusPill near the eyebrow): "Saving to cloud…". Auto-dismiss
    when syncMetadata.syncState == .synced.

6. Free-analysis summary support.

Reuse V2WorkoutSummaryView. Pass a flag isFreeAnalysis that flips:
  - eyebrow to "FREE ANALYSIS"
  - hides trophy stack
  - hides plan-completion section
  - shows the single exercise stat block

7. Tests.

- V2 preview starts the workout via the same coordinator path.
- V2 target edit sheet updates plan and persists.
- AI/Swap All UI not exposed.
- V2 live workout HUD renders on top of TrainerSessionView; live
  pose/rep/form pipeline untouched.
- Rest screen actions (skip, +15s, start) work and call the existing
  coordinator.
- Summary save updates history, trophies, insights.
- Free-analysis variant renders without trophy stack.
- Sync pending banner shows in firebase mode when syncMetadata is
  .pendingUpload.
- V1 workout flow unchanged when toggle off.

ACCEPTANCE
- Workout flow V2 matches design direction.
- Camera + pose + rep counter + form feedback unchanged.
- Target editing works; swap UI hidden.
- Free-analysis variant honored.
- DEBUG_LOG entry.
```

---

### D6 — V2 profile + trophies + history + evidence + account surfaces

```
Use the V2 design preflight block.

D6 goal: rebuild profile, trophies, trophy collection, workout detail,
workout evidence, heatmap, account/export/delete, and backend debug
surfaces in V2 style.

Reference screens:
- NEW_DESIGN/export-html/profile.html
- NEW_DESIGN/export-html/trophies.html
- NEW_DESIGN/export-html/trophy-collection---expanded.html
- NEW_DESIGN/export-html/workout-detail-sheet.html
- NEW_DESIGN/export-html/workout-evidence.html
- NEW_DESIGN/export-html/hyper-theme-preview.html
- NEW_DESIGN/export-html/hot-girl-theme-preview.html
- NEW_DESIGN/export-html/warm-theme-preview.html
- NEW_DESIGN/export-html/spicy-theme-preview.html

Current code:
- VirtualTrainer/UI/ProfileView.swift
- VirtualTrainer/UI/TrophiesView.swift
- VirtualTrainer/UI/TrophyCollectionView (if separate)
- VirtualTrainer/UI/WorkoutDetailSheetView.swift
- VirtualTrainer/UI/InsightEvidenceSheetView.swift
- VirtualTrainer/UI/TrainingHeatmapView.swift
- VirtualTrainer/Services/AccountDeletionService.swift
- VirtualTrainer/Services/DataExportService.swift
- VirtualTrainer/Repositories/BackendStatusStore.swift
- VirtualTrainer/Repositories/SyncOrchestrator.swift
- VirtualTrainer/Models/ThemeStore.swift
- VirtualTrainer/Models/StatsEngine.swift
- VirtualTrainer/Models/TrophyModels.swift
- VirtualTrainer/Models/InsightStore.swift

TASKS

1. V2ProfileView.

UI/V2/Profile/V2ProfileView.swift
  - Header: avatar (initials in cream-bordered square if no image),
    name "Satvik Bansal" style, level + XP eyebrow.
  - Trophy strip: horizontal scroll of last 4 earned trophies, lime
    accent.
  - Section: APP THEME → V2ThemeSelector (D6 task 2).
  - Section: TRAINING PREFERENCES → V2 selectors for Main Goal,
    Coach Style, Daily Plan Length. Bind to OnboardingStore updater
    methods.
  - Section: STATS → 2x3 grid of V2MetricPill cards from
    StatsEngine.makeStats.
  - Section: WORKOUT SNAPSHOT → V2TrainingHeatmap (12-week) with
    day-drill-in.
  - Section: COACH INSIGHTS → up to 2 V2InsightCard from
    InsightEngine.generateProfileInsights.
  - Section: WORKOUT HISTORY → V2WorkoutHistoryRow list (recent 5)
    with "View All" CTA routing to V2WorkoutHistoryListView.
  - Section: ACCOUNT (always visible):
      - Export My Data (V2SecondaryButton, calls DataExportService)
      - Delete My Account and Data (V2DestructiveButton, typed-DELETE
        confirmation, calls AccountDeletionService)
  - Section: SETTINGS & DEBUG (collapsed, DEBUG only):
      - V2 Design System toggle (System default / Force on / Force off)
      - Backend mode picker + status chip + run-smoke / push / pull /
        listeners / pending / conflicts / lastError
      - Reset onboarding / reset calibration debug buttons
      - "V2 Design Gallery" link
      - Code-only feature: list in PR.

2. V2ThemeSelector.

UI/V2/Profile/V2ThemeSelector.swift
  - 4 cards horizontally: Hyper, Hot Girl, Warm, Spicy.
  - Each card shows: theme name, color swatch row (accentColor +
    secondaryAccentColor + neutrals), small text style preview.
  - Tap to set theme; bind to ThemeStore.updateSelectedTheme +
    OnboardingStore.updateSelectedTheme. Update propagates to
    UserProfile + (firebase mode) syncs via FirestoreThemeRepository.
  - Use existing per-theme accent values from
    SpotterThemeOption.accentColor.

3. V2TrophiesView.

UI/V2/Trophies/V2TrophiesView.swift
  - Match trophies.html: "HALL OF GAINS" eyebrow + "TROPHIES" hero
    heading + "12/47 EARNED" stat.
  - Featured trophy: largest V2TrophyCard with lime border + glow.
  - In Progress: list of V2TrophyCard with progress bar (chart-1 cyan).
  - Locked / Coming Soon: muted V2TrophyCard with eyebrow "COMING SOON",
    descriptive copy on why ("Heart rate sensor not yet supported").
  - Bind every value to TrophyStore.snapshot. Honor
    progress.confidence == .unavailable as Coming Soon.

4. V2TrophyCollectionView.

UI/V2/Trophies/V2TrophyCollectionView.swift
  - Match trophy-collection---expanded.html.
  - Grid of V2TrophyCard by category (Volume / Consistency / Form /
    Calibration / Time of Day / Muscle Group / Goal / Elite).
  - Earned states: lime border + checkmark.
  - In-progress: cream border + ring progress.
  - Coming Soon: muted, no progress bar.
  - Share Collection: design-only delta. Render disabled with "Coming
    soon" subtitle. List in PR.

5. V2WorkoutDetailSheet.

UI/V2/Workout/V2WorkoutDetailSheet.swift
  - Match workout-detail-sheet.html.
  - Hero: workout title + date, mode pill, duration, total reps.
  - Form quality card with cyan trend arrow.
  - Exercise list: V2ExerciseRow with per-set stats.
  - Top cue + worst cue cards.
  - Top insight card (if any).
  - Delete workout V2DestructiveButton at bottom (typed-DELETE confirm).
    Calls WorkoutHistoryStore.deleteSummary; in firebase mode also calls
    repository.deleteWorkout which uses the hardened tombstone path
    (P17.5).
  - "View Evidence" V2SecondaryButton routes to V2WorkoutEvidenceView.

6. V2WorkoutEvidenceView.

UI/V2/Workout/V2WorkoutEvidenceView.swift
  - Match workout-evidence.html.
  - Per-set sparkline of formScore over reps (existing
    WorkoutDetailEvidenceModel).
  - Quality breakdown pills: avg form, excellent reps, good reps,
    scored reps.
  - Drop-after-rep / improved-after-rep badges (already in data).
  - Cue events timeline.
  - Insight evidence refs that link back to other workouts.
  - DESIGN DELTA: design shows "Range %" and "Depth %" metrics. The
    code does not compute these yet. Render the section title but show
    a single Coming Soon V2 chip in the section. List in PR.

7. V2TrainingHeatmap day drill-in.

UI/V2/Profile/V2TrainingHeatmapView.swift
  - Match the heatmap module from profile.html.
  - 12-week grid (84 cells), tinted by intensity (use
    TrendEngine.dailyIntensitySummary; chart-1 cyan for intensity 1,
    primary lime for intensity ≥3, primary lime + glow for intensity 4).
  - Day cell tap opens V2DayDrillInSheet with the day's sessions.
  - "Share Heatmap" CTA bottom-right that calls ShareCardRenderer
    .renderTrainingHeatmapPoster (existing).

8. Account / sync surfaces.

UI/V2/Profile/V2AccountSection.swift
  - V2SecondaryButton "Export My Data" → DataExportService.
  - V2DestructiveButton "Delete My Account and Data" → confirmation
    sheet → AccountDeletionService.deleteAccountAndData(mode:).
  - In firebase mode, the subtitle reads:
    "Some cloud data may take up to 7 days to fully delete."
  - In local mode, the subtitle reads:
    "Clears all data on this device."
  - Bind copy from the existing services; do not hardcode.

UI/V2/Profile/V2BackendDebugSection.swift (#if DEBUG)
  - Backend mode picker (local / firebase).
  - Status chip: active backend, firebase bootstrap state, last sync,
    pending count, conflict count, last error (sanitized).
  - "Run Full Sync", "Push Pending", "Pull Remote", "Start/Stop
    Listeners" buttons.
  - "Run Firebase Smoke Test" button.

9. Tests.

- V2 theme change updates SpotterThemeOption.accentColor live.
- V2 stats render with empty history AND rich history.
- V2 trophies render Coming Soon honestly (Neon Pulse, Heavy Metal,
  Burpee Beast).
- V2 workout detail delete sets tombstone; in firebase mode calls
  repository.
- V2 export + delete buttons accessible.
- V2 backend debug section hidden in release.
- V1 profile/trophies unchanged when toggle off.
- Snapshot tests across all four themes.

ACCEPTANCE
- Profile / trophy / history / evidence surfaces match design.
- Account export + delete remain available and work in both modes.
- Coming Soon trophies honest.
- Backend debug DEBUG-only.
- DEBUG_LOG entry.
- PR summary lists design-only deltas (share collection, range/depth %)
  and code-only deltas (backend debug, sync diagnostics, smoke verifier,
  export/delete) styled.
```

---

### D7 — Design QA, accessibility, edge cases

```
Use the V2 design preflight block.

D7 goal: hardening pass before broader testing.

TASKS

1. Feature flag safety.

- V2 toggle off → V1 app shell renders fully (every screen).
- V2 toggle on → V2 app shell renders fully.
- Toggle while app is running: stores stay alive, no onboarding/
  calibration reset, theme persists.
- Remote flag default false: a new install never sees V2 by accident.
- Local + Firebase modes both work with V2 on AND V2 off.

2. Navigation.

- Liquid glass nav safe area on iPhone SE, 15, 17 Pro Max.
- Keyboard does not overlap input fields in onboarding.
- CTAs not hidden behind the nav (any bottom-anchored CTA accounts for
  the ~110 pt nav height in its safe area inset).
- Camera session can present full-screen over the nav safely (nav
  hides via AppLevelPresenterEnvironmentKey).
- Workout / rest / summary navigation works without bouncing back to
  V1.

3. Accessibility.

- VoiceOver labels on every interactive: nav tabs, CTAs, metric pills,
  trophy cards, insight engagement.
- Dynamic Type at least up to Large (verify heading line breaks don't
  break at xLarge).
- Reduce Motion: disable scaleEffect, opacity, and pulse animations.
- Reduce Transparency: liquid glass nav uses solid fallback variant.
- Color contrast: primary text on background ≥ 4.5:1; primary CTA text
  on primary fill ≥ 4.5:1 (cream foreground on lime should pass; verify).
  destructive button text on destructive fill (white on #FF5C3A) verify.

4. Device matrix.

Previews:
- iPhone SE (small)
- iPhone 17 (standard)
- iPhone 17 Pro Max (large)
- Each of the four themes
- Large Dynamic Type
- Reduce Motion on/off
- Reduce Transparency on/off
- Local mode
- Firebase mode with sync active

5. Product edge cases.

V2 screens handle:
- No profile
- Onboarding incomplete
- Calibration skipped / failed
- No workout history
- Many workouts (100+)
- Many trophies (32+ shown)
- No insights
- Expired insights
- Insight engagement: already-marked-helpful state
- Sync .pendingUpload banner
- Sync .conflict state
- Deleted workout (tombstoned, hidden by default)
- Camera permission denied
- Poor visibility
- Unsupported design-only features (rendered Coming Soon, never crash)

6. Visual consistency audit.

- No raw hex colors in any V2 feature screen (grep for `Color(red:`
  and `Color(hex:` outside SpotterV2 files).
- No one-off repeated button/card styles (grep for `RoundedRectangle`
  and `Capsule` to confirm all reused V2 components).
- All V2 screens use V2 tokens.
- Old Theme.swift can remain for legacy UI but is not imported by any
  V2 file.

7. Performance.

- Dashboard scroll performance: no jank on iPhone SE.
- Profile heatmap loads under 500 ms even with 100 workouts.
- Trophy collection grid renders under 1 s.
- Workout detail evidence loads under 1.5 s for max set count.
- Live workout HUD: no extra rendering work on the camera frame thread.
- No expensive sync / Firestore computation triggered from main UI
  frame.

8. Documentation.

- Update README design status to "V2 in beta behind feature flag".
- Update Documentation/DesignSystemV2Inventory.md with what's shipped
  vs deferred.
- DEBUG_LOG entry summarizing all V2-related fixes.

9. Tests.

- Build green.
- All core unit tests pass.
- Design token tests.
- Feature flag tests.
- Snapshot tests at this point across the four themes + two devices.
- Backend tests if feasible (smoke verifier + emulator rules).

ACCEPTANCE
- V2 is safe to demo end-to-end.
- V1 remains safe fallback.
- All known design / code deltas documented.
- No product logic regression.
- DEBUG_LOG entry.
```

---

## Part 6 — Differences from GPT 5.5 Pro's plan

GPT's plan is **structurally correct** and I'd ship the overall flow. Two material additions and a few sharper specifics:

| GPT's prompt | What I added or sharpened |
|---|---|
| P17.5 backend hardening | I added explicit Firestore emulator test scripts (`scripts/test-firestore-rules.sh`) and a `Documentation/FirestoreRulesEmulatorTests.md`. GPT noted "if emulator infra is not available, add documentation" — but the emulator infra is already set up (`Documentation/FirebaseEmulatorSetup.md`), so we should ship the rules tests now, not later. |
| P17.5 privacy validator | GPT said "reject any Data field unless allowlisted." I added the explicit allowlist mechanism (`allowedDataFieldPaths`) and made the default an empty set with a documented policy comment. |
| P17.5 deleteWorkout | GPT correctly diagnosed the bug. I specified the exact fields the minimal tombstone must include (`accountId`, `schemaVersion`, `workoutId`, plus tombstone fields) so reads after a delete-before-upload don't crash on missing required fields. |
| D0 design inventory | GPT's prompt is good. I added the explicit Phosphor → SF Symbol mapping document (`PhosphorToSFSymbolMap.md`) and the verification that all four theme previews share the same base palette (so the V2 token implementation doesn't waste effort on four separate palettes). |
| D1 feature flag | GPT mentioned `forceOn/forceOff/systemDefault`. I added the exact `DesignSystemV2ToggleStore` API with `isEffectivelyEnabled`, plus the explicit rule that the toggle must not reset stores (which matters because the toggle lives in Profile, which depends on those stores). |
| D1 tokens | GPT mentioned tokens. I added the critical observation that per-theme accent should come from `SpotterThemeOption.accentColor` (already in code), not from four separate token palettes. This saves significant work and keeps the V2 design consistent with the existing theme system. |
| D2 liquid glass nav | GPT mentioned the nav. I specified the exact dimensions (92 pt height, 92% width / 440 max, 46 pt radius, 10 pt from bottom safe area), the exact fallback (`V2NavStyle.solid` when `accessibilityReduceTransparency`), and the explicit hide-during-workout via `AppLevelPresenterEnvironmentKey`. |
| D3 onboarding | GPT said "show login disabled or omit." I picked one (alert with "Coming soon") and named the future flag (`FeatureFlag.signInWithApple`). |
| D5 workout flow | I added the explicit `isFreeAnalysis` flag on `V2WorkoutSummaryView` and the eyebrow swap, since free-analysis is a code-only flow not in the design. |
| D6 evidence | I called out the specific data gap ("Range %", "Depth %") in `workout-evidence.html` — these metrics are not computed yet and must be rendered as Coming Soon, not skipped silently. |
| D6 backend section | GPT said "style debug surfaces." I specified the exact section heading hierarchy (Account → Settings & Debug → Backend Mode → Sync Diagnostics → Smoke Verifier) and the DEBUG-only gating rule. |
| D7 QA | GPT's QA is comprehensive. I added the explicit color-contrast verification (4.5:1 for primary text on background, cream on lime, white on destructive) and the iOS 26 vs iOS 17 device matrix. |
| Phosphor icons | GPT didn't address this explicitly. The HTML uses `<iconify-icon icon="ph:...">` everywhere. iOS doesn't have iconify. I added the SF Symbol mapping table in Part 2.4 and the `PhosphorToSFSymbolMap.md` deliverable in D0. |
| Tailwind translation | GPT didn't address. I added the rosetta-stone translation table in Part 2.4, which Codex will need to interpret the HTML correctly. |
| Custom fonts | GPT said "use safe fallbacks." I made it explicit: do NOT bundle DM Sans / Space Grotesk / etc. in the design phase. Bundle them in a future polish phase after design lands and licensing is verified. |
| Toolchain | GPT mentioned the preflight; I made it a per-phase requirement and reminded that DL-045 documents the trap. |

GPT's risk register is good. I'd add one more risk:

| Risk | Severity | Mitigation |
|---|---|---|
| User flips V2 toggle mid-session (during onboarding / calibration / live workout) and the view tree rebuilds, losing in-progress state | High | The toggle should be **disabled while a live workout is active** and **show a "Restart required" warning when flipped during onboarding**. State machines for onboarding/calibration are in stores and survive view swaps; live workout state lives in the trainer view and would be lost. Add a guard in `DesignSystemV2ToggleStore.setOverride` that asks for confirmation when `LiveSessionContext.isLive`. |

---

## Part 7 — Immediate next actions

1. **Run the backend hardening prompt (P17.5) now.** It's small. It closes two critical bugs (root rules + tombstone) and one high-priority hygiene (privacy validator). After the rules change, **paste the new `firestore.rules` into the Firebase Console** (`Firestore Database → Rules → Edit → Publish`).

2. **Run D0.** Generate the inventory + delta document + Phosphor map. This is non-coding and takes Codex about an hour.

3. **Run D1.** This establishes V2 tokens, the feature flag, and the component library. After D1, the toggle exists but V2 is just a placeholder screen.

4. **Run D2.** Liquid glass nav + V2 shell. After D2, with the toggle on you see the new nav with tab placeholders.

5. **Run D3 → D4 → D5 → D6 in sequence.** Each ships a section of the V2 app. After D6, all surfaces are V2.

6. **Run D7.** QA pass before turning the remote flag on for testers.

7. **After D7, turn on `designSystemV2Enabled` in Firebase Remote Config for your TestFlight tester group** to push V2 to real users.

8. **Then Phase 19 (Beta / App Store readiness)** as previously planned. SIWA + revocation can land in Phase 19 or a dedicated Phase 19.5.

---

## Closing

You're in unusually good shape going into the design revamp. Backend infrastructure is mostly production-grade — three small but real bugs (rules root permissiveness, tombstone idempotency, validator Data field) are closed by a one-day P17.5 pass. The pre-backend hardening was thorough; the repository abstraction is clean; the sync orchestrator is properly gated against live workouts; the privacy boundary is enforced; and the deletion + export paths satisfy Apple's account-deletion requirement in both local and firebase modes.

The design system revamp is largely a translation exercise from Tailwind/HTML to SwiftUI, with the wrinkle that **the design doesn't show everything the code does, and the code doesn't have everything the design shows**. The delta map in Part 2.2 is the single most important reference for the revamp — it tells Codex exactly which design features to defer (login, AI swaps, BPM trophies, etc.) and exactly which code features to style using V2 language (backend debug, sync diagnostics, free-analysis summary, etc.).

The feature flag strategy lets you flip between V1 and V2 cleanly per session, which preserves your stated goal of easy A/B and revert.

Three things to internalize:

1. **The four "theme previews" in NEW_DESIGN don't actually have different `:root` palettes.** The themes vary by accent, which already exists in `SpotterThemeOption.accentColor`. Don't waste effort building four separate token sets.

2. **Phosphor icons are not on iOS.** You need the SF Symbol mapping table (D0 deliverable). Without it, Codex will either embed iconify (bad) or pick wrong SF Symbols (worse).

3. **The "Log in" link on the welcome screen is a design-only feature today.** Render it as a coming-soon alert; don't stub fake auth. SIWA + revocation handler comes in Phase 19 or later.

Ship P17.5 first, then proceed D0 → D7 in order. Don't batch. Each phase is independently demoable to yourself with the toggle flip.
