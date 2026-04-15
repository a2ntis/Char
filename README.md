# Char

Local desktop anime companion for macOS.

Floating transparent window with an animated avatar (VRM or Live2D), built-in chat, local/cloud LLM integration, and multi-backend TTS with lip sync.

## Features

- **VRM 1.0 avatars** rendered via RealityKit with facial expressions, blink, breathing, body sway, cursor look-at, VRMA body animations, and VRoid poses
- **Live2D avatars** rendered via Cubism SDK (OpenGL) with expressions and motions
- **LLM chat** — Ollama, OpenAI, LM Studio, Gemini (streaming)
- **TTS** — System (AVSpeech), Piper (local), XTTS (local), OpenAI TTS, Gemini TTS
- **Speech input** via Apple Speech Recognition
- **Lip sync** driven by real-time TTS audio level
- **Emotion detection** from LLM responses → automatic expression changes
- **Global hotkey** ⌃⌥H to move companion to current screen

## Quick Start

1. Install dependencies:
   ```bash
   brew install glew glfw
   ```
2. (Optional) Start Ollama and pull a model:
   ```bash
   ollama pull qwen3:14b
   ```
3. Build and run:
   ```bash
   swift run Char
   ```
4. Open Settings (Cmd+,) to configure LLM endpoint, TTS, and avatar.

## Build Release App

```bash
scripts/build_app.sh
open dist/Char.app
```

## Xcode

Open `Package.swift` in Xcode, select `Char` scheme, Cmd+R.

## Project Structure

```
Sources/CharApp/        # Main app (SwiftUI + AppKit)
Sources/Live2DBridge/   # C++ bridge to Live2D Cubism SDK
ThirdParty/VRMKit/      # Local VRMKit fork (VRM parsing + RealityKit)
ThirdParty/CubismSdk…/  # Live2D Cubism SDK
Assets/VRM/             # VRM models
Assets/VRMA/            # VRM animations
Assets/Poses/           # VRoid poses
Assets/TTS/             # TTS voices and references
Assets/*/               # Live2D models
```

## Documentation

- [Project Specification](Docs/SPEC.md) — full architecture, module reference, and current state
- [VRM Animation Spec](Docs/VRM-Animation-Spec.md) — animation system design notes

## Notes

- **VRM 1.0** is the supported avatar format. VRM 0.x models load but animations/poses are broken.
- Default LLM endpoint: `http://127.0.0.1:11434/api/chat` (Ollama)
- API keys are stored in UserDefaults for convenience. For distribution, migrate to Keychain.
- Piper TTS requires a local `piper` binary and `.onnx` voice model (auto-install available in settings).
