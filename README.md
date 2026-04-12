# Char

Local desktop anime companion for macOS.

## MVP

- native macOS app with `SwiftUI + AppKit`
- floating transparent window that stays above other windows
- procedural anime-style avatar with idle and blink animation
- built-in chat panel
- local LLM replies through `Ollama`
- optional spoken replies through system TTS or `Piper`

## Run

1. Start Ollama.
2. Pull a model, for example:
   - `ollama pull qwen3:14b`
3. Build and run:
   - `swift run Char`

## Notes

- Default endpoint: `http://127.0.0.1:11434/api/chat`
- Default model: `qwen3:14b`
- TTS provider is configured in app `Settings`.
- `Piper` support expects a local `piper` binary and a voice model `.onnx` path in settings.
- Speech input is scaffolded, but for a polished always-on microphone flow it is better to open the package in Xcode and add the usual macOS privacy strings and signing setup.
- For the current self-use MVP, the OpenAI API key is stored in local app settings to avoid repeated macOS password prompts. For a proper distributable app, switch this back to Keychain storage after adding stable app signing/notarization.
