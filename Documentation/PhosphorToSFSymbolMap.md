# Phosphor To SF Symbol Map

**Date:** 2026-05-17
**Phase:** D0 - extracted from every `iconify-icon` `ph:*` reference in the 29 HTML exports.

## Mapping Rules

- Do not ship Iconify, Phosphor, Tailwind, or external icon fonts in the iOS app.
- Prefer SF Symbols with `.symbolVariant(.fill)` when the Phosphor icon requested `-fill`.
- When Phosphor has no clean SF Symbol, use the closest SF Symbol and keep the product meaning in the adjacent label.
- If the closest replacement would mislead users, use text, initials, or a small app-owned custom symbol plan in a later asset phase. Do not fetch remote icon assets.

## Exhaustive Icon Map

| Phosphor icon | Count | HTML refs | SF Symbol replacement | Fit | Notes |
|---|---:|---|---|---|---|
| `activity-bold` | 2 | `form-check-selection.html`, `spicy-theme-preview.html` | `waveform.path.ecg` | Close | Use only for generic activity. Do not imply medical HR tracking |
| `armchair-bold` | 2 | `form-check-selection.html`, `onboarding-objective.html` | `chair.fill` | Close | If unavailable on target OS, use `figure.seated.side` |
| `arrow-down-bold` | 1 | `exercise-swap-sheet-v2.html` | `arrow.down` | Exact | Deferred with AI alternatives UI unless reused elsewhere |
| `arrow-left-bold` | 1 | `workout-evidence.html` | `arrow.left` | Exact | Back action |
| `arrow-right-bold` | 8 | `calibration-1.html`, `hyper-theme-preview-(copy)-(copy)-(copy).html`, `hyper-theme-preview-(copy)-(copy).html`, `liquid-glass-nav-iteration.html`, `onboarding-identity.html`, `onboarding-objective.html`, `onboarding-stats-v2.html`, `welcome-screen.html` | `arrow.right` | Exact | CTA/action arrow |
| `arrows-clockwise-bold` | 1 | `quick-start.html` | `arrow.clockwise` | Close | Use for shuffle/refresh |
| `arrows-out-bold` | 5 | `coach-selector.html`, `exercise-swap-sheet-v1.html`, `exercise-swap-sheet-v2.html`, `workout-detail-sheet.html`, `workout-preview.html` | `arrow.up.left.and.arrow.down.right` | Close | Resize/expand metaphor; for target edit, label must carry meaning |
| `asterisk-fill` | 1 | `trophy-collection---expanded.html` | `asterisk` | Close | Decorative trophy marker |
| `barbell-bold` | 3 | `form-check-selection.html`, `hyper-theme-preview-(copy)-(copy)-(copy).html`, `hyper-theme-preview-(copy)-(copy).html` | `figure.strengthtraining.traditional` | Close | SF has no barbell glyph; this is the clearest training symbol |
| `barbell-fill` | 3 | `liquid-glass-nav-iteration.html`, `profile.html`, `trophies.html` | `figure.strengthtraining.traditional` | Close | Same as bold variant |
| `brain-bold` | 4 | `hyper-theme-preview-(copy).html`, `hyper-theme-preview.html`, `profile.html`, `workout-detail-sheet.html` | `brain.head.profile` | Close | Coach insight/intelligence |
| `brain-fill` | 2 | `workout-evidence.html`, `workout-summary.html` | `brain.head.profile` | Close | No fill variant required |
| `camera-fill` | 8 | `hyper-theme-preview-(copy)-(copy)-(copy).html`, `hyper-theme-preview-(copy)-(copy).html`, `hyper-theme-preview-(copy).html`, `liquid-glass-nav-iteration.html`, `profile.html`, `quick-start.html`, `trophy-collection---expanded.html`, `workout-evidence.html` | `camera.fill` | Exact | Camera/free-analysis |
| `caret-down-fill` | 2 | `workout-evidence.html` | `chevron.down` | Exact | Expand/collapse/detail |
| `caret-left-bold` | 9 | `coach-selector.html`, `live-workout-(copy).html`, `live-workout.html`, `onboarding-identity.html`, `onboarding-objective.html`, `onboarding-stats-v2.html`, `trophies.html`, `trophy-collection---expanded.html`, `workout-preview.html` | `chevron.left` | Exact | Back action |
| `caret-right-bold` | 6 | `hyper-theme-preview-(copy).html`, `profile.html` | `chevron.right` | Exact | Disclosure/action |
| `chart-bar-fill` | 1 | `workout-evidence.html` | `chart.bar.fill` | Exact | Metric card |
| `chart-line-up-bold` | 2 | `hyper-theme-preview-(copy).html`, `hyper-theme-preview.html` | `chart.line.uptrend.xyaxis` | Exact | Trend/insight |
| `chart-line-up-fill` | 4 | `hyper-theme-preview-(copy)-(copy)-(copy).html`, `hyper-theme-preview-(copy)-(copy).html`, `liquid-glass-nav-iteration.html` | `chart.line.uptrend.xyaxis` | Exact | Same as bold variant |
| `check-bold` | 5 | `coach-selector.html`, `rest-screen.html`, `workout-summary.html` | `checkmark` | Exact | Selection/success |
| `check-circle-fill` | 3 | `hyper-theme-preview.html`, `onboarding-objective.html`, `trophy-collection---expanded.html` | `checkmark.circle.fill` | Exact | Completed/selected |
| `circle-half-tilt-fill` | 1 | `trophy-collection---expanded.html` | `circle.lefthalf.filled` | Close | If tilt matters, defer custom trophy mark |
| `clock-bold` | 3 | `coach-selector.html`, `hyper-theme-preview-(copy).html`, `workout-preview.html` | `clock.fill` | Exact | Duration |
| `coffee-fill` | 1 | `trophy-collection---expanded.html` | `cup.and.saucer.fill` | Close | Morning trophy |
| `crown-fill` | 3 | `profile.html`, `trophies.html`, `trophy-collection---expanded.html` | `crown.fill` | Exact | Elite/achievement |
| `crown-simple-fill` | 1 | `hot-girl-theme-preview.html` | `crown.fill` | Exact | Theme accent card |
| `download-simple-bold` | 1 | `workout-evidence.html` | `arrow.down.to.line` | Exact | Export/download |
| `fire-bold` | 1 | `hyper-theme-preview.html` | `flame.fill` | Exact | Streak/intensity |
| `fire-fill` | 10 | `hyper-theme-preview-(copy)-(copy)-(copy).html`, `hyper-theme-preview-(copy)-(copy).html`, `hyper-theme-preview-(copy).html`, `liquid-glass-nav-iteration.html`, `profile.html`, `spicy-theme-preview.html`, `trophies.html`, `trophy-collection---expanded.html`, `workout-detail-sheet.html` | `flame.fill` | Exact | Streak/intensity/trophy |
| `flame-fill` | 1 | `spicy-theme-preview.html` | `flame.fill` | Exact | Same as fire |
| `gauge-fill` | 2 | `hyper-theme-preview-(copy)-(copy)-(copy).html`, `hyper-theme-preview-(copy)-(copy).html` | `gauge.medium` | Close | For form quality/intensity gauge |
| `gender-female-bold` | 1 | `onboarding-identity.html` | `person.fill` | Weak | No clean SF gender glyph. Pair with the visible `Female` label; optionally use a future custom symbol |
| `gender-male-bold` | 1 | `onboarding-identity.html` | `person.fill` | Weak | Pair with `Male` label |
| `gender-neuter-bold` | 1 | `onboarding-identity.html` | `person.crop.circle` | Weak | Pair with `Other` label |
| `hand-fist-fill` | 1 | `trophy-collection---expanded.html` | `hand.raised.fill` | Close | For strength/arms trophy; custom fist asset optional later |
| `heart-fill` | 1 | `hot-girl-theme-preview.html` | `heart.fill` | Exact | Theme accent |
| `heartbeat-fill` | 1 | `trophies.html` | `waveform.path.ecg` | Close | Heart-rate trophy is coming soon; label must indicate unavailable |
| `house-bold` | 2 | `profile.html`, `quick-start.html` | `house.fill` | Exact | Dashboard/home |
| `house-fill` | 4 | `hyper-theme-preview-(copy)-(copy)-(copy).html`, `hyper-theme-preview-(copy)-(copy).html`, `hyper-theme-preview-(copy).html`, `workout-evidence.html` | `house.fill` | Exact | Dashboard/home |
| `infinite-fill` | 1 | `trophy-collection---expanded.html` | `infinity` | Exact | Consistency/endurance |
| `info-bold` | 3 | `calibration-1.html`, `rest-screen.html`, `workout-evidence.html` | `info.circle.fill` | Exact | Help/detail |
| `leaf-bold` | 1 | `onboarding-objective.html` | `leaf.fill` | Exact | Longevity/mobility |
| `leaf-fill` | 1 | `trophy-collection---expanded.html` | `leaf.fill` | Exact | Mobility/longevity |
| `leg-bold` | 1 | `trophy-collection---expanded.html` | `figure.walk` | Close | Lower-body trophy; no clean leg-only SF symbol |
| `lightbulb-fill` | 1 | `warm-theme-preview.html` | `lightbulb.fill` | Exact | Insight/note |
| `lightning-bold` | 6 | `coach-selector.html`, `form-check-selection.html`, `hyper-theme-preview-(copy)-(copy)-(copy).html`, `hyper-theme-preview-(copy)-(copy).html`, `onboarding-objective.html`, `workout-preview.html` | `bolt.fill` | Exact | Performance/intensity |
| `lightning-fill` | 4 | `hyper-theme-preview.html`, `quick-start.html`, `trophies.html`, `trophy-collection---expanded.html` | `bolt.fill` | Exact | Same as bold variant |
| `lock-key-bold` | 1 | `welcome-screen.html` | `lock.fill` | Close | Key detail omitted; privacy copy carries meaning |
| `lock-key-fill` | 2 | `trophies.html`, `trophy-collection---expanded.html` | `lock.fill` | Close | Locked trophy |
| `magic-wand-fill` | 1 | `hot-girl-theme-preview.html` | `wand.and.stars` | Exact | Theme flourish |
| `magnifying-glass-bold` | 1 | `form-check-selection.html` | `magnifyingglass` | Exact | Search |
| `medal-fill` | 2 | `trophy-collection---expanded.html`, `warm-theme-preview.html` | `medal.fill` | Exact | Award |
| `megaphone-fill` | 1 | `workout-evidence.html` | `megaphone.fill` | Exact | Feedback/cue |
| `megaphone-simple-fill` | 1 | `workout-evidence.html` | `megaphone.fill` | Exact | Same as megaphone |
| `microphone-stage-bold` | 1 | `profile.html` | `mic.fill` | Close | Coach style/preference |
| `minus-bold` | 4 | `exercise-swap-sheet-v1.html`, `exercise-swap-sheet-v2.html` | `minus` | Exact | Stepper |
| `moon-stars-fill` | 2 | `trophies.html`, `trophy-collection---expanded.html` | `moon.stars.fill` | Exact | Night trophy |
| `pencil-simple-line-bold` | 5 | `coach-selector.html`, `workout-preview.html` | `pencil` | Exact | Edit/adjust |
| `person-arms-spread-bold` | 1 | `workout-detail-sheet.html` | `figure.stand` | Close | Exercise/body movement |
| `phone-bold` | 1 | `camera-readiness.html` | `iphone` | Exact | Phone orientation |
| `play-fill` | 5 | `coach-selector.html`, `hyper-theme-preview-(copy).html`, `quick-start.html`, `rest-screen.html`, `workout-preview.html` | `play.fill` | Exact | Start |
| `plus-bold` | 7 | `exercise-swap-sheet-v1.html`, `exercise-swap-sheet-v2.html`, `welcome-screen.html` | `plus` | Exact | Stepper/add |
| `pulse-fill` | 1 | `trophy-collection---expanded.html` | `waveform.path.ecg` | Close | Coming-soon heart signal if used for HR |
| `push-pin-bold` | 3 | `coach-selector.html`, `form-check-selection.html`, `workout-preview.html` | `pin.fill` | Exact | Pinned/focus item |
| `quotes-fill` | 1 | `workout-detail-sheet.html` | `quote.opening` | Close | Insight quote |
| `robot-fill` | 2 | `trophies.html`, `trophy-collection---expanded.html` | `cpu.fill` | Close | Machine/automation trophy; no generic robot SF symbol |
| `ruler-fill` | 3 | `profile.html`, `trophies.html`, `trophy-collection---expanded.html` | `ruler.fill` | Exact | Form/range |
| `scan-body-duotone` | 1 | `welcome-screen.html` | `viewfinder` | Close | If body silhouette is needed later, compose with `figure.stand` |
| `scan-bold` | 2 | `quick-start.html`, `welcome-screen.html` | `viewfinder` | Exact enough | Camera scan/form check |
| `share-network-bold` | 2 | `trophies.html`, `trophy-collection---expanded.html` | `square.and.arrow.up` | Close | Use standard iOS share affordance |
| `share-network-fill` | 1 | `profile.html` | `square.and.arrow.up.fill` | Close | Use standard iOS share affordance |
| `shield-chevron-fill` | 1 | `trophy-collection---expanded.html` | `shield.fill` | Close | Achievement/protection |
| `shield-warning-fill` | 1 | `spicy-theme-preview.html` | `exclamationmark.shield.fill` | Exact | Warning/intensity |
| `shooting-star-fill` | 1 | `liquid-glass-nav-iteration.html` | `sparkles` | Close | Milestone/spark |
| `sketch-logo-fill` | 2 | `hyper-theme-preview-(copy)-(copy)-(copy).html`, `hyper-theme-preview-(copy)-(copy).html` | `diamond.fill` | Weak | Avoid brand logo; use diamond/trophy-related visual |
| `skull-fill` | 1 | `trophy-collection---expanded.html` | `skull.fill` | Exact | High-intensity trophy visual |
| `smiley-bold` | 2 | `coach-selector.html`, `workout-preview.html` | `face.smiling` | Exact | Coach vibe |
| `sneaker-move-bold` | 1 | `quick-start.html` | `figure.run` | Close | Running Analysis is coming soon; do not imply active gait flow |
| `sparkle-bold` | 4 | `hyper-theme-preview-(copy)-(copy)-(copy).html`, `hyper-theme-preview-(copy)-(copy).html`, `hyper-theme-preview-(copy).html`, `hyper-theme-preview.html` | `sparkles` | Exact | AI/insight flourish |
| `sparkle-fill` | 5 | `exercise-swap-sheet-v2.html`, `hot-girl-theme-preview.html`, `hyper-theme-preview-(copy)-(copy)-(copy).html`, `hyper-theme-preview-(copy)-(copy).html`, `workout-evidence.html` | `sparkles` | Exact | AI/insight flourish. In swap sheet, UI is deferred |
| `squares-four-fill` | 1 | `liquid-glass-nav-iteration.html` | `square.grid.2x2.fill` | Exact | Dashboard/grid |
| `star-fill` | 2 | `hot-girl-theme-preview.html`, `trophy-collection---expanded.html` | `star.fill` | Exact | Favorite/achievement |
| `sun-dim-fill` | 2 | `trophies.html`, `warm-theme-preview.html` | `sun.min.fill` | Exact | Morning/warm theme |
| `sun-fill` | 1 | `warm-theme-preview.html` | `sun.max.fill` | Exact | Warm theme |
| `target-bold` | 1 | `profile.html` | `target` | Exact | Goal |
| `target-fill` | 1 | `trophy-collection---expanded.html` | `target` | Exact | Goal/trophy |
| `timer-fill` | 1 | `warm-theme-preview.html` | `timer` | Exact | Active time |
| `trend-up-bold` | 5 | `exercise-swap-sheet-v2.html`, `hyper-theme-preview-(copy).html`, `profile.html`, `spicy-theme-preview.html`, `workout-preview.html` | `chart.line.uptrend.xyaxis` | Exact | Trend/improvement |
| `trophy-bold` | 1 | `calibration-1.html` | `trophy.fill` | Exact | Calibration trophy |
| `trophy-fill` | 3 | `liquid-glass-nav-iteration.html`, `warm-theme-preview.html`, `workout-summary.html` | `trophy.fill` | Exact | Trophy |
| `user-bold` | 6 | `hyper-theme-preview-(copy)-(copy)-(copy).html`, `hyper-theme-preview-(copy)-(copy).html`, `hyper-theme-preview-(copy).html`, `onboarding-identity.html`, `quick-start.html`, `workout-evidence.html` | `person.fill` | Exact | Profile/user |
| `user-circle-fill` | 1 | `liquid-glass-nav-iteration.html` | `person.circle.fill` | Exact | Profile tab |
| `user-fill` | 1 | `profile.html` | `person.fill` | Exact | Profile |
| `user-focus-bold` | 1 | `camera-readiness.html` | `person.crop.square` | Close | Body visibility/focus; can compose with `viewfinder` later |
| `warning-circle-fill` | 1 | `spicy-theme-preview.html` | `exclamationmark.circle.fill` | Exact | Warning |
| `warning-octagon-fill` | 1 | `workout-evidence.html` | `exclamationmark.octagon.fill` | Exact | Warning cue |
| `waves-bold` | 1 | `hot-girl-theme-preview.html` | `water.waves` | Close | Theme vibe |
| `wind-fill` | 1 | `trophies.html` | `wind` | Exact | Mobility/breathing |
| `x-bold` | 1 | `camera-readiness.html` | `xmark` | Exact | Close/cancel |

## Custom Or Weak Replacement Follow-Ups

- Gender icons: rely on visible text labels in D3; optional custom symbol later if product wants distinct gender glyphs.
- Barbell: `figure.strengthtraining.traditional` is acceptable and avoids custom asset work.
- Body scan/user focus: use `viewfinder`, `person.crop.square`, or a composed view with both symbols.
- Robot/machine: `cpu.fill` is the closest neutral SF replacement.
- Sketch logo: do not use a third-party brand mark; use `diamond.fill` or trophy art.
- Running shoe: use `figure.run` while Running Analysis remains coming soon.
