# VRM Animation Spec

## Goal

Implement believable VRM avatar animation for the desktop companion app in a way that works reliably with the current macOS Swift app architecture.

The current app already supports:

- VRM rendering via `VRMRealityKit`
- full-body viewport fitting for `VRM 0.x`
- facial expressions
- smooth blinking
- mouth movement driven by TTS speech level
- basic procedural motion:
  - breathing
  - subtle body sway
  - head/neck look-at cursor
  - drag tilt
  - thinking/listening pose bias

What is still missing is **usable body animation playback**. The current `VRMA` experiment technically plays data, but the resulting motion is often incorrect, unnatural, or broken.

This spec is intended as a handoff for improving VRM animation playback properly.

## Project Context

Repository root:

- `/Users/denis_work/projects/Other/Char`

Relevant runtime files:

- `/Users/denis_work/projects/Other/Char/Sources/CharApp/CompanionViews.swift`
- `/Users/denis_work/projects/Other/Char/Sources/CharApp/VRMAPlayer.swift`
- `/Users/denis_work/projects/Other/Char/Sources/CharApp/CompanionViewModel.swift`
- `/Users/denis_work/projects/Other/Char/Sources/CharApp/Models.swift`

Relevant assets:

- VRM avatars:
  - `/Users/denis_work/projects/Other/Char/Assets/VRM`
- VRMA clips:
  - `/Users/denis_work/projects/Other/Char/Assets/VRMA`

Reference repositories already available locally:

- Soul-of-Waifu:
  - `/Users/denis_work/projects/Other/Char/ThirdParty/Soul-of-Waifu`
- VRM assets pack:
  - `/Users/denis_work/projects/Other/Char/ThirdParty/VRM-Assets-Pack-For-Silly-Tavern`

## Current Behavior

### What already works

- `VRM 0.x` avatars render in-app through `VRMRealityKit`
- avatar can be selected from settings
- VRM face expressions work:
  - `Neutral`
  - `Smiling`
  - `Sad`
  - `Angry`
  - `Happy`
  - `Surprised`
- expression transitions are smooth
- blinking is smooth
- happy-blink is reduced rather than fully disabled
- mouth moves with TTS speech level
- Gemini and OpenAI streaming TTS now provide usable speech-level lip-sync
- procedural body life makes the avatar less static

### What is broken

The current `VRMA` pipeline is not production-ready.

Symptoms observed:

- limbs bend in the wrong direction
- body posture can look exorcism-like / broken
- some clips push the avatar out of frame
- motion quality varies heavily between clips
- some clips use different bone naming schemes:
  - plain humanoid names like `Head`, `Hips`, `LeftUpperArm`
  - names like `J_Bip_C_Head`, `J_Bip_L_UpperArm`, `J_Adj_L_FaceEye`

We already tried:

- direct transform application
- applying clip rotation as a delta over the original pose
- disabling translation
- expanding bone-name mapping
- disabling procedural body motion while a clip is playing

This improved debugging, but not animation quality enough.

## Current Technical Implementation

Current experimental player:

- `/Users/denis_work/projects/Other/Char/Sources/CharApp/VRMAPlayer.swift`

Current approach:

- parse `.vrma` as GLB/glTF
- read animation channels
- map node names to `Humanoid.Bones`
- sample translation/rotation over time
- apply sampled values to VRM humanoid entities

This is too naive.

The likely missing pieces are:

- correct rest-pose aware retargeting
- correct local-vs-global transform handling
- correct basis/axis handling
- possible humanoid normalization logic expected by VRMA
- clip/root-motion policy for desktop framing

## Desired Result

We need a **desktop-companion-friendly body animation layer** for VRM avatars.

The result should feel like:

- expressive
- readable
- cute / anime-like
- stable
- not physically perfect, but believable

Animations should support:

- idle variants
- greeting / wave
- thinking pose
- shy pose
- surprise reaction
- happy gesture
- simple body reaction to drag / interaction

## Constraints

- This is a desktop overlay companion, not a full 3D scene viewer.
- Full root locomotion is usually undesirable.
- The avatar should remain framed inside the existing viewport.
- The avatar should not leave the visible panel during animation.
- We currently use `VRMRealityKit`.
- The app is macOS Swift + AppKit/SwiftUI, not web-based.

## Non-Goals

Not required yet:

- VRM 1.0 rendering
- full-body locomotion through world space
- perfect physically accurate retargeting for every arbitrary source rig
- emotion-memory / personality backend
- LLM-driven animation planning

## Required Functional Behavior

### 1. Reliable clip playback

For supported VRM animation clips:

- the avatar stays in frame
- joints do not invert unnaturally
- clip playback starts and ends cleanly
- avatar returns to baseline pose after clip ends

### 2. Safe desktop framing

Body animation should not break viewport composition.

At minimum:

- disable or filter root translation by default
- optionally keep vertical body compression/pose changes if safe
- support “full body” framing as the default mode

### 3. Layering rules

Procedural motion and clip animation must coexist cleanly.

Expected layering:

- facial expressions: can continue during clip playback
- blink: can continue unless clip/expression explicitly overrides it
- lip sync: should continue during speaking
- procedural body motion: should be reduced or disabled while a body clip is active

### 4. Animation library loading

The app should automatically discover `.vrma` files from:

- `/Users/denis_work/projects/Other/Char/Assets/VRMA`

This is already partially implemented. It should remain automatic and robust.

## Likely Correct Direction

The current evidence suggests we should **not** rely on naive per-bone transform assignment.

Possible valid directions:

### Option A: Proper VRMA retargeting

Implement correct rest-pose aware VRMA application for VRM humanoid bones.

Likely required:

- preserving original local bone transforms
- applying clip transforms in the correct local space
- handling humanoid rest orientation differences
- explicit root-motion filtering

### Option B: Switch clip playback strategy

If VRMA support in this stack is too fragile, use a more controlled animation source:

- pre-validated clips only
- another supported format
- custom reduced animation vocabulary

### Option C: Hybrid

Use:

- procedural body motion for idle/live presence
- only a tiny curated set of clips for large gestures

This may be the most realistic desktop-companion approach.

## Existing Findings From Reference Repo

From the local `Soul-of-Waifu` reference repo:

- they do not rely on naive VRMA playback
- they separate:
  - expression layer
  - procedural life layer
  - body clip layer
- their body animations are driven through a more explicit retarget path
- architecture is layered, not “LLM controls bones directly”

That supports the idea that our current player is too low-level and too naive.

## Requested Deliverable

Please improve the VRM body animation system so that:

- the avatar remains stable and framed
- supported clips look natural enough for a desktop anime companion
- the implementation is maintainable
- the result works with the existing facial expression + blink + lip sync system

## Acceptance Criteria

The task is successful if all of the following are true:

1. At least 3 body animation clips play without grotesque limb deformation.
2. The avatar does not jump out of the viewport during those clips.
3. Facial expressions and lip sync still work while idle and while clips are not active.
4. During clip playback, the body no longer fights procedural idle motion.
5. The solution is implemented in the app codebase, not only described.

## Nice-to-Have

- ability to mark clips as:
  - `idle`
  - `greeting`
  - `thinking`
  - `happy`
  - `surprised`
- support future framing modes:
  - `full body`
  - `half body`
  - `portrait`

## Notes

- `VRM 0.x` support is acceptable for now.
- `VRM 1.0` is not the current target for this task.
- It is acceptable to explicitly limit the supported animation set if that produces a much better desktop experience.
