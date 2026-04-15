# VRM Animation Spec

> Last updated: 2026-04-14

## Current State

The VRM animation system is functional for **VRM 1.0** models. VRM 0.x is marked as unsupported due to unresolvable coordinate system issues.

### What Works

- **VRM 1.0 rendering** via `VRMRealityKit` (RealityKit)
- **Facial expressions:** Neutral, Smiling, Sad, Angry, Happy, Surprised + custom VRM blendshapes
- **Smooth blinking** with happy-blink reduction
- **Lip sync** driven by `speechLevel` from TTS audio (all backends)
- **Procedural idle:** breathing, body sway, head/neck cursor look-at, drag tilt, thinking/listening bias
- **VRMA body animation playback** — rest-pose aware retargeting, convention-aware axis correction
- **VRoid poses (.vroidpose)** — smooth transition, auto-discovered from `Assets/Poses/`
- **Layering:** facial expressions + blink + lip sync continue during body clips; procedural idle disabled during clip

### What Doesn't Work

- **VRM 0.x animations/poses** — Z-axis reflection convention causes torso rotation artifacts. Mathematically unresolvable without breaking limb rotations. These models are marked as unsupported in the UI.
- **Some VRMA clips** produce unnatural motion depending on source rig compatibility
- **Foot grounding** is basic; some clips still cause minor floating

## Architecture

### Files

| File | Role |
|------|------|
| `CompanionViews.swift` | `CompanionVRMRealityKit` — RealityKit view, loads VRM, manages camera, applies blendshapes, runs idle loop, triggers VRMA/pose playback |
| `VRMAPlayer.swift` | `VRMAPlayer` — parses GLB VRMA, samples keyframes, retargets to humanoid bones. `VRoidPosePlayer` — parses `.vroidpose` JSON, applies as target pose with interpolation |
| `CompanionViewModel.swift` | Discovers VRMA/pose files, exposes UI actions, sends requests to view layer |
| `Models.swift` | `CompanionModelOption.isVRM0x` — identifies unsupported VRM 0.x models |

### Coordinate Conventions (`VRMCoordinateConvention`)

```swift
enum VRMCoordinateConvention {
    case v0  // VRM 0.x: Z-reflection, 180° Y root rotation
    case v1  // VRM 1.0: X-reflection, identity root rotation
}
```

**VRM 1.0 (`.v1`):**
- Model faces +Z natively, no root rotation
- Pose quaternion conversion (Unity → VRM 1.0): `(qx, -qy, -qz, qw)`
- HipsPosition: `(-x, y, z)`
- VRMA retarget: clip delta applied directly (no axis correction needed)

**VRM 0.x (`.v0`):** (unsupported)
- Model faces -Z, rotated 180° around Y at load time
- Pose quaternion: `(-qx, -qy, qz, qw)`
- HipsPosition: `(x, y, -z)`
- VRMA retarget: `vrm10toVRM0x` axis correction applied

### VRMA Playback Pipeline

1. Parse `.vrma` file as GLB (custom binary glTF reader in `VRMAPlayer`)
2. Extract animation channels: node index → bone name mapping
3. Map bone names to `Humanoid.Bones` enum (handles both plain names and `J_Bip_*` prefixed)
4. Sample keyframes (rotation quaternions + hips translation) at current time
5. Retarget: `targetRest * convention_correct(sourceRest.inverse * clipRotation)`
6. Apply to VRM entity bones
7. Foot grounding: adjust Y position to prevent floating

### VRoid Pose Pipeline

1. Parse `.vroidpose` JSON: `BoneDefinition` dictionary with quaternion rotations + `HipsPosition`
2. Convert from Unity left-handed convention per VRM version
3. Map bone names to `Humanoid.Bones`
4. Interpolate from current pose to target over configurable duration

### Layering Rules

| Layer | During idle | During VRMA/pose |
|-------|-------------|-----------------|
| Facial expressions | Active | Active |
| Blink | Active | Active |
| Lip sync (mouth) | Active | Active |
| Procedural body (breathing, sway, look-at) | Active | **Disabled** |
| Body clip/pose | — | Active |

## Asset Locations

- VRM models: `Assets/VRM/` (`.vrm`, `.vroid`)
- VRMA clips: `Assets/VRMA/` (`.vrma`)
- VRoid poses: `Assets/Poses/` (`.vroidpose`)

All auto-discovered at runtime by `VRMACatalog` and `PoseCatalog`.

## Future Improvements

- Better VRMA clip compatibility across different source rigs
- Clip tagging (idle, greeting, thinking, happy) for LLM-driven animation selection
- Framing modes: full body, half body, portrait
- Improved foot grounding / root motion filtering
- Blend between multiple simultaneous animations
