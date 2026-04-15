# Char — Project Specification

> Last updated: 2026-04-14

## Overview

**Char** — нативное macOS-приложение (Swift 6.2, SwiftUI + AppKit), работающее как настольный аниме-компаньон. Прозрачное floating-окно поверх всех приложений с анимированным аватаром, чатом, голосовым вводом/выводом и подключением к LLM.

---

## Architecture

### Tech Stack

| Компонент | Технология |
|-----------|-----------|
| UI framework | SwiftUI + AppKit (`NSPanel`, borderless) |
| 3D rendering (VRM) | RealityKit через `VRMRealityKit` (локальный форк VRMKit) |
| 2D rendering (Live2D) | OpenGL через Live2D Cubism SDK + C++ bridge |
| LLM backends | Ollama, OpenAI-compatible API, LM Studio, Gemini |
| TTS backends | System AVSpeech, Piper (local), XTTS (local Python), OpenAI TTS, Gemini TTS |
| Speech input | `SFSpeechRecognizer` (Apple Speech) |
| Build system | Swift Package Manager |
| Min deployment | macOS 15.0 |

### Module Dependency Graph

```
CharApp (executable)
├── Live2DBridge (C++ target)
│   └── CubismSdkForNative-5-r.5 (static lib + headers)
└── VRMRealityKit (from local ThirdParty/VRMKit)
    ├── VRMKit (VRM 0.x / 1.0 parsing)
    └── VRMKitRuntime (humanoid bone mapping)
```

### Source Files (`Sources/CharApp/`)

| File | Purpose |
|------|---------|
| `CharApp.swift` | `@main` entry point, `AppDelegate`, Settings UI (`CompanionSettingsView`), global hotkey ⌃⌥H |
| `Models.swift` | Domain types: `CompanionProfile`, `ModelCatalog`, LLM/TTS provider enums, Ollama request/response types, emotion/presence state |
| `CompanionViewModel.swift` | Central `ObservableObject`: chat state, profile, model selection, VRMA/pose discovery, message streaming, emotion detection, TTS coordination |
| `CompanionViews.swift` | Avatar panel (`AvatarPanelView`), chat bubble (`BubblePanelView`), Live2D `NSViewRepresentable`, VRM `CompanionVRMRealityKit` (RealityKit ARView subclass), blendshapes, idle animation, VRMA/pose playback |
| `CompanionWindowCoordinator.swift` | Two borderless `NSPanel` windows (avatar + bubble), positioning, `bringCompanionToMouseScreen()` |
| `VRMAPlayer.swift` | `VRMACatalog`, `PoseCatalog`, `VRMAPlayer` (GLB/glTF VRMA playback), `VRoidPosePlayer` (.vroidpose), `VRMCoordinateConvention` |
| `SpeechCoordinator.swift` | TTS playback (all backends), speech recognition, `speechLevel` for mouth animation |
| `OllamaClient.swift` | `OllamaClient`, `OpenAIClient`, `CompanionChatClient` (aggregator), SSE streaming, model listing |
| `PiperSupport.swift` | Piper TTS binary/model resolution, auto-install via venv |
| `XTTSSupport.swift` | XTTS Python path resolution, reference audio discovery |
| `AppEnvironment.swift` | Resource path resolution with 3-level fallback: Bundle → CWD → compile-time `#filePath` |
| `KeychainStore.swift` | Keychain wrapper (currently unused, API keys stored in UserDefaults) |

### C++ Bridge (`Sources/Live2DBridge/`)

Wraps Live2D Cubism SDK for OpenGL rendering on macOS. Provides C-callable functions for loading models, updating, rendering, and setting expression/motion parameters. Public headers in `include/`.

---

## VRM Support

### Supported Versions

| Version | Status | Notes |
|---------|--------|-------|
| **VRM 1.0** | Supported | Primary target. Works correctly with animations and poses. |
| **VRM 0.x** | Unsupported | Marked in UI as "не поддерж." Loads but animations/poses display incorrectly due to coordinate system differences. |

### VRMKit (Local Fork)

Located at `ThirdParty/VRMKit/`. Forked from [tattn/VRMKit](https://github.com/tattn/VRMKit) `main` branch with the following fixes:

**`Sources/VRMKit/VRM/VRM1.swift`:**
- `FirstPerson.meshAnnotations` → Optional
- `LookAt` fields (`offsetFromHeadBone`, `type`, `rangeMap*`) → Optional
- All `Expressions.Preset` expression fields → Optional

**`Sources/VRMKit/VRM/VRM0.swift`:**
- `FirstPerson` fields (`meshAnnotations`, `lookAtTypeName`) → Optional
- `firstPerson` and `secondaryAnimation` parsing wrapped in `try?` with defaults

**`Sources/VRMKit/VRM/VRMMigration.swift`:**
- Safe optional chaining for `meshAnnotations` and preset expressions in VRM1→VRM0 migration

**`Package.swift`:**
- `LICENSE` excluded from VRMKit target resources

### Coordinate Conventions

The app handles two coordinate conventions via `VRMCoordinateConvention`:

- **`.v1` (VRM 1.0):** Model faces +Z natively. No root rotation needed. Pose quaternion conversion: X-axis reflection `(qx, -qy, -qz, qw)`. HipsPosition: X-negation `(-x, y, z)`.
- **`.v0` (VRM 0.x):** Model faces -Z, rotated 180° around Y at load time. Pose quaternion: Z-axis reflection `(-qx, -qy, qz, qw)`. HipsPosition: Z-negation `(x, y, -z)`. Has known torso rotation issues.

### VRM Animation (VRMA)

- Format: GLB/glTF with humanoid animation channels
- Parser: custom GLB reader in `VRMAPlayer.swift`
- Retargeting: rest-pose aware with `sourceRest.inverse * clipRotation` delta, convention-dependent axis correction
- Bone mapping: humanoid bone names → `Humanoid.Bones` enum
- Root motion: hips translation applied, foot grounding enabled
- Layering: facial expressions, blink, and lip sync continue during body clip playback; procedural idle motion disabled during clip

### VRoid Poses (.vroidpose)

- Format: JSON from VRoid Studio with `BoneDefinition` containing quaternion rotations and `HipsPosition`
- Convention: Unity left-handed, converted per VRM version
- Smooth transition from current pose via interpolation
- Discovery: auto-scanned from `Assets/Poses/`

---

## Avatar Features

### Procedural Animation (always active unless clip playing)
- Breathing (chest scale oscillation)
- Subtle body sway
- Head/neck look-at cursor tracking
- Drag tilt response
- Thinking/listening pose bias

### Facial System
- Expressions: Neutral, Smiling, Sad, Angry, Happy, Surprised (mapped from LLM emotion detection)
- Smooth expression transitions
- Procedural blink with adjustable frequency
- Happy-blink reduced (not disabled)
- Mouth animation driven by `speechLevel` from TTS audio

### VRM BlendShape Expressions (VRM 1.0)
Additional expressions from model (e.g., custom VRoid Studio expressions) available in settings.

---

## LLM Integration

### Supported Providers

| Provider | Protocol | Streaming | Notes |
|----------|----------|-----------|-------|
| Ollama | `/api/chat` | Yes (NDJSON) | Default: `http://127.0.0.1:11434` |
| OpenAI | `/v1/chat/completions` | Yes (SSE) | Requires API key |
| LM Studio | OpenAI-compatible | Yes (SSE) | No API key needed, system message normalization |
| Gemini | OpenAI-compatible | Yes (SSE) | Via OpenAI-compatible endpoint |

### Chat Flow

1. User types message or uses speech input
2. `CompanionChatClient` sends to configured provider with streaming
3. Response streamed token-by-token to chat bubble
4. Emotion detected from response text → expression change
5. Response text sent to TTS for spoken output
6. `speechLevel` drives mouth animation during playback

---

## TTS Integration

### Supported Backends

| Backend | Type | Notes |
|---------|------|-------|
| System (AVSpeech) | Local | macOS built-in voices |
| Piper | Local process | Requires `piper` binary + `.onnx` voice model. Auto-install available. |
| XTTS | Local Python | Requires Python venv + reference audio for voice cloning |
| OpenAI TTS | Cloud API | Chunked streaming, multiple voices |
| Gemini TTS | Cloud API | Streaming SSE, configurable voices |

### Speech Level for Lip Sync

All TTS backends feed audio samples to `SpeechCoordinator.speechLevel` (0.0–1.0), which drives the VRM mouth blendshape in real-time.

---

## Window System

Two borderless `NSPanel` windows managed by `CompanionWindowCoordinator`:

1. **Avatar Panel** — transparent, always-on-top, renders Live2D or VRM avatar
2. **Bubble Panel** — chat messages, positioned relative to avatar panel

Features:
- Drag to reposition
- ⌃⌥H hotkey: move companion to current mouse screen
- Panel size synced with avatar layout settings
- Panels can become key/main window (`CompanionPanel` subclass)

---

## Assets Structure

```
Assets/
├── VRM/                    # VRM models (.vrm, .vroid)
├── VRMA/                   # VRM animation clips (.vrma)
├── Poses/                  # VRoid poses (.vroidpose)
├── Helen/                  # Live2D model (full body + head)
├── Helen (Head)/           # Live2D model (head only variant)
├── TTS/
│   ├── Piper/              # Piper voice models (.onnx)
│   └── Reference/          # XTTS reference audio (.wav)
├── shizuku/                # Live2D demo model
├── Epsilon/                # Live2D model
├── Unitychan/              # Live2D model
└── ...                     # Other Live2D models
```

### Model Discovery

`ModelCatalog` auto-discovers:
- **Live2D:** directories containing `*.model3.json`
- **VRM/VRoid:** files with `.vrm` / `.vroid` extensions
- **VRMA:** `.vrma` files from `Assets/VRMA/`
- **Poses:** `.vroidpose` files from `Assets/Poses/`
- **Presets:** `companion-preset.json` in model directories
- **Expressions:** `*.exp3.json` for Live2D expressions

---

## Build & Run

### Prerequisites

- macOS 15.0+
- Xcode with Swift 6.2 toolchain
- Homebrew packages: `glew`, `glfw` (for Live2D OpenGL rendering)
- Ollama running locally (for LLM, optional)

### Development Build

```bash
swift run Char
```

### Release Build (.app bundle)

```bash
scripts/build_app.sh
```

Creates `dist/Char.app` with:
- Release binary
- Assets copied to `Resources/Assets`
- Cubism shaders copied to `Resources/FrameworkShaders`
- GLEW/GLFW dylibs bundled in `Frameworks/`
- Ad-hoc code signature

### Xcode

Open `Package.swift` in Xcode, select `Char` scheme, Cmd+R. Resource resolution uses `#filePath`-based fallback to find Assets from DerivedData build directory.

---

## Configuration

All settings stored in UserDefaults, accessible via Settings window (Cmd+,):

- **LLM:** provider, endpoint, model name, API key, system prompt
- **TTS:** provider, voice, speed, language
- **Avatar:** model selection, layout (size, position), expression/motion presets
- **VRMA/Poses:** auto-discovered, trigger buttons in settings
- **Companion profile:** name, personality, response language

---

## Known Issues & Limitations

1. **VRM 0.x animations/poses are broken** — coordinate conversion produces incorrect torso rotation. VRM 0.x models are marked as unsupported in the UI.
2. **VRMA playback quality varies** — some clips still produce unnatural motion depending on source rig compatibility. Works best with clips made for standard VRM humanoid.
3. **Live2D + VRM mutual exclusion** — only one renderer active at a time based on selected model type.
4. **KeychainStore unused** — API keys currently in UserDefaults for convenience. Should migrate to Keychain for distribution.
5. **Linker warnings** — CubismSDK `.a` built for macOS 15.7, GLEW/GLFW built for macOS 26.0; harmless version mismatch warnings during build.

---

## Third-Party Dependencies

| Dependency | Location | Purpose |
|------------|----------|---------|
| VRMKit (local fork) | `ThirdParty/VRMKit/` | VRM 0.x/1.0 parsing + RealityKit rendering |
| Cubism SDK for Native 5-r.5 | `ThirdParty/CubismSdkForNative-5-r.5/` | Live2D model rendering (static lib + framework) |
| Soul-of-Waifu | `ThirdParty/Soul-of-Waifu/` | Reference repo for animation architecture |
| VRM-Assets-Pack | `ThirdParty/VRM-Assets-Pack-For-Silly-Tavern/` | Reference VRM assets |
| desktop-homunculus | `ThirdParty/desktop-homunculus/` | Reference desktop companion implementation |

---

## File-Level Reference

### Key Type Relationships

```
CharApp (@main)
 └─ AppDelegate
     ├─ CompanionViewModel (ObservableObject, central state)
     │   ├─ CompanionProfile (Codable, persisted settings)
     │   ├─ CompanionChatClient (LLM networking)
     │   │   ├─ OllamaClient
     │   │   └─ OpenAIClient
     │   ├─ SpeechCoordinator (TTS + speech recognition)
     │   │   ├─ PiperSupport
     │   │   └─ XTTSSupport
     │   └─ VRMACatalog / PoseCatalog (asset discovery)
     └─ CompanionWindowCoordinator (window management)
         ├─ AvatarPanelView
         │   └─ CompanionVRMRealityKit (RealityKit ARView)
         │       ├─ VRMAPlayer (animation playback)
         │       └─ VRoidPosePlayer (pose application)
         └─ BubblePanelView (chat UI)
```

### Important Protocols & Patterns

- **`@MainActor`** — most UI-related types are main-actor isolated
- **`ObservableObject` + `@Published`** — SwiftUI reactive state via `CompanionViewModel`
- **`Sendable`** conformance — required by Swift 6 concurrency; network clients and coordinators are `@Sendable`
- **Combine** — used for timer-based updates, publisher chains in `CompanionVRMRealityKit`
- **`async/await`** — all network and TTS operations

### AppEnvironment Resource Resolution

Three-level fallback for finding `Assets/` directory:

1. `Bundle.main.resourceURL` — for packaged `.app` builds
2. `FileManager.default.currentDirectoryPath` — for `swift run` from project root
3. Compile-time project root via `#filePath` — for Xcode builds (DerivedData)

Same pattern for `shadersRootURL` (Cubism OpenGL shaders).
