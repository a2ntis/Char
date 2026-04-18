# Animation Event System — Specification

## Context

This document describes the full specification for implementing the **Animation Event Mapping System** in the Char desktop companion app (macOS, SwiftUI + RealityKit + VRM).

The goal: allow the user to assign any combination of animations (VRMA, BVH) and poses to different character events (state changes, emotions, gestures, commands). The system should make the character feel alive — different animations play in different situations, driven by state, detected emotions in text, user gestures, and explicit commands.

---

## Existing Architecture (Key Files)

| File | Role |
|------|------|
| `Sources/CharApp/Models.swift` | `CompanionProfile` (Codable, persisted to UserDefaults), `CompanionPresenceState`, `CompanionEmotionState` |
| `Sources/CharApp/CompanionViewModel.swift` | Main `@Observable` class. Manages state transitions, `@Published` animation request properties, emotion detection |
| `Sources/CharApp/CompanionViews.swift` | `CompanionVRMRealityView` (ARView subclass). Handles idle cycling, startup greeting, look-at, VRMAPlayer, VRoidPosePlayer |
| `Sources/CharApp/CharApp.swift` | SwiftUI `CompanionSettingsView` — Form-based settings UI |
| `Sources/CharApp/VRMAPlayer.swift` | `VRMAPlayer`, `VRMACatalog`, `CompanionVRMAOption` |
| `Sources/CharApp/BVHSupport.swift` | `BVHConverter`, `BVHCatalog`, `CompanionBVHOption` |

### Existing state enums

```swift
enum CompanionPresenceState: Int { case idle, listening, speaking, thinking }
enum CompanionEmotionState: Int  { case neutral, happy, excited, shy, thinking, sleepy, angry }
```

### Existing animation trigger chain (ViewModel → View)

```
CompanionViewModel.$manualVRMARequest  → vrmView?.playVRMA(filePath:)
CompanionViewModel.$manualPoseRequest  → vrmView?.applyPose(filePath:) / clearPose()
```

Wired in `AvatarPanelContentView.bindViewModel()` (CharApp.swift).

### Existing idle/startup logic in CompanionVRMRealityView

- `startupGreetingPlayed: Bool` — plays `greeting2.vrma` (hardcoded) on first idle frame after model load
- `idleAnimNames = ["neutral","neutral2","neutral3","neutral4"]` (hardcoded BVH names)
- `updateIdleAnimation(deltaTime:)` — cycles idle animations with 8–18s random interval
- `playStartupGreeting()` — plays `Assets/VRMA/greeting2.vrma` synchronously

### Existing asset catalogs

```swift
VRMACatalog.discover(in: assetsRoot)  // Assets/VRMA/*.vrma
BVHCatalog.discover(in: assetsRoot)   // Assets/BVH/*.bvh
PoseCatalog.discover(in: assetsRoot)  // Assets/Poses/*.vroidpose + *.vrma
```

All three are loaded into `@Published` arrays in `CompanionViewModel.init()`.

### Persistence

`CompanionProfile` is Codable, saved/loaded via `JSONEncoder/Decoder` under `UserDefaults.standard["companionProfile"]`.  
**Important:** `CompanionProfile` has an explicit `CodingKeys` enum and a custom `init(from decoder:)` with `decodeIfPresent` + defaults for every field. Any new field added to `CompanionProfile` MUST also be added to `CodingKeys` and decoded in `init(from decoder:)`.

---

## Available Animation Assets

### VRMA (`Assets/VRMA/`)
```
dogeza, drink_water, gatan, gekirei, greeting, greeting2, hello,
humidai, idle-maid, idle-sitting, model pose, motion_pose,
peace sign, shoot, show full body, spin, use_smartphone, warm-up
```

### BVH (`Assets/BVH/`)
**Idle/neutral:** neutral, neutral2, neutral3, neutral4, neutral_idle, neutral_idle2, kneel_idle, kneel_idle2, laying_idle, laying_idle2, laying_idle3, sit_idle, sit_idle2, sit_idle3, sit_idle4  
**Emotions:** admiration×3, amusement×3, anger×3, annoyance×2, approval×3, caring×2, confusion×3, curiosity×3, desire×3, disappointment×2, disapproval×2, disgust×3, embarrassment, excitement×3, fear×3, gratitude, grief, joy×3, love×3, nervousness×3, optimism, pride×2, realization, relief×2, remorse×3, sadness×2, surprise×2  
**Hit reactions:** hitarea_butt, hitarea_chest, hitarea_foot, hitarea_groin, hitarea_hands, hitarea_head, hitarea_leg, reaction_groinhit, reaction_headshot  
**Actions:** action_attention_seeking, action_crawling, action_crouch, action_gaming, action_greeting, action_greeting1, action_jog, action_jump, action_laydown, action_pat, action_pickingup, action_run, action_standup, action_walk  
**Dance:** dance_1, dance_2, dance_backup, dance_dab, dance_gangnam_style, dance_headdrop, dance_marachinostep, dance_northern_soul_spin, dance_ontop, dance_pushback, dance_rumba  
**Exercise:** exercise_crunch, exercise_crunches, exercise_jogging, exercise_jumping_jacks

### Poses (`Assets/Poses/`)
```
absolute-cinema.vrma, arms-crossed.vroidpose, default.vrma,
fighting.vroidpose, fuck-you.vrma, grrr.vroidpose, hands-out.vroidpose,
hands-out2.vroidpose.vrma, head-in-hand.vroidpose, idn.vrma,
kneeling.vroidpose, lotus.vrma, nyan.vrma, sits-sad.vrma,
sitting.vroidpose, thinking.vroidpose, this-way.vroidpose,
touching-hair.vroidpose, wiping-nose.vroidpose, wow.vrma
```

---

## Data Model to Implement

### New types (add to `Models.swift`)

```swift
/// A single animation or pose that can be assigned to an event slot.
struct AnimationSlotItem: Codable, Identifiable, Hashable, Transferable {
    var id: UUID = UUID()
    var assetType: AnimationAssetType
    var displayName: String
    var filePath: String

    // Transferable conformance for SwiftUI drag-and-drop
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .animationSlotItem)
    }
}

enum AnimationAssetType: String, Codable, Hashable {
    case vrma   // VRMA animation file
    case bvh    // BVH motion capture (converted to VRMA at runtime)
    case pose   // Static pose (.vroidpose or pose-vrma from Poses folder)
}

// UTType extension for Transferable
extension UTType {
    static let animationSlotItem = UTType(exportedAs: "com.char.animationslotitem")
}

/// All events that can trigger animations.
enum AnimationEventType: String, Codable, CaseIterable {
    // --- Layer 1: State events (cycling/looping while state is active) ---
    case startup        // Model just loaded — one-shot greeting
    case idle           // Idle state — cycling random picks
    case speaking       // AI is speaking — cycling random picks
    case thinking       // AI is thinking — cycling random picks
    case listening      // User is speaking/typing — cycling random picks

    // --- Layer 2: Emotion reactions (one-shot on emotion detection) ---
    case joy
    case excitement
    case anger
    case sadness
    case fear
    case surprise
    case love
    case disgust
    case confusion
    case approval
    case disapproval
    case embarrassment
    case pride
    case gratitude
    case curiosity
    case admiration
    case nervousness
    case relief
    case desire
    case remorse

    // --- Layer 3: Interaction reactions (one-shot on gesture) ---
    case tap            // User taps the character
    case drag           // User drags the character

    // --- Layer 4: Command actions (one-shot, text-triggered in future) ---
    case dance
    case spin
    case wave
    case jump
    case laydown
    case sitdown
    case standup
    case walk
    case attention
    case dogeza
    case peace

    /// Human-readable name
    var displayName: String {
        switch self {
        case .startup:      return "Запуск"
        case .idle:         return "Idle"
        case .speaking:     return "Говорит"
        case .thinking:     return "Думает"
        case .listening:    return "Слушает"
        case .joy:          return "Радость"
        case .excitement:   return "Восторг"
        case .anger:        return "Злость"
        case .sadness:      return "Грусть"
        case .fear:         return "Страх"
        case .surprise:     return "Удивление"
        case .love:         return "Любовь"
        case .disgust:      return "Отвращение"
        case .confusion:    return "Смятение"
        case .approval:     return "Согласие"
        case .disapproval:  return "Несогласие"
        case .embarrassment:return "Смущение"
        case .pride:        return "Гордость"
        case .gratitude:    return "Благодарность"
        case .curiosity:    return "Любопытство"
        case .admiration:   return "Восхищение"
        case .nervousness:  return "Нервозность"
        case .relief:       return "Облегчение"
        case .desire:       return "Желание"
        case .remorse:      return "Сожаление"
        case .tap:          return "Тап"
        case .drag:         return "Перетаскивание"
        case .dance:        return "Танец"
        case .spin:         return "Спин"
        case .wave:         return "Помахать"
        case .jump:         return "Прыжок"
        case .laydown:      return "Лечь"
        case .sitdown:      return "Сесть"
        case .standup:      return "Встать"
        case .walk:         return "Пройтись"
        case .attention:    return "Привлечь внимание"
        case .dogeza:       return "Догеза"
        case .peace:        return "Peace sign"
        }
    }

    var icon: String {
        switch self {
        case .startup:      return "🚀"
        case .idle:         return "💤"
        case .speaking:     return "🗣️"
        case .thinking:     return "🤔"
        case .listening:    return "👂"
        case .joy:          return "😊"
        case .excitement:   return "🤩"
        case .anger:        return "😠"
        case .sadness:      return "😢"
        case .fear:         return "😨"
        case .surprise:     return "😲"
        case .love:         return "🥰"
        case .disgust:      return "🤢"
        case .confusion:    return "😕"
        case .approval:     return "👍"
        case .disapproval:  return "👎"
        case .embarrassment:return "😳"
        case .pride:        return "😤"
        case .gratitude:    return "🙏"
        case .curiosity:    return "🧐"
        case .admiration:   return "😍"
        case .nervousness:  return "😬"
        case .relief:       return "😮‍💨"
        case .desire:       return "🤤"
        case .remorse:      return "😞"
        case .tap:          return "👆"
        case .drag:         return "✋"
        case .dance:        return "💃"
        case .spin:         return "🌀"
        case .wave:         return "👋"
        case .jump:         return "⬆️"
        case .laydown:      return "🛌"
        case .sitdown:      return "🪑"
        case .standup:      return "🧍"
        case .walk:         return "🚶"
        case .attention:    return "📣"
        case .dogeza:       return "🙇"
        case .peace:        return "✌️"
        }
    }

    /// Play mode: cycle = keep cycling while state is active; oneShot = play once then return
    var playMode: AnimationPlayMode {
        switch self {
        case .startup, .idle, .speaking, .thinking, .listening:
            return .cycling
        default:
            return .oneShot
        }
    }

    var category: AnimationEventCategory {
        switch self {
        case .startup, .idle, .speaking, .thinking, .listening:
            return .state
        case .joy, .excitement, .anger, .sadness, .fear, .surprise, .love,
             .disgust, .confusion, .approval, .disapproval, .embarrassment,
             .pride, .gratitude, .curiosity, .admiration, .nervousness,
             .relief, .desire, .remorse:
            return .emotion
        case .tap, .drag:
            return .interaction
        case .dance, .spin, .wave, .jump, .laydown, .sitdown, .standup,
             .walk, .attention, .dogeza, .peace:
            return .command
        }
    }
}

enum AnimationPlayMode: String, Codable {
    case cycling   // Used for state events: random pick, play, pick next on finish
    case oneShot   // Play once, then return to current state cycling
}

enum AnimationEventCategory: String, Codable, CaseIterable {
    case state
    case emotion
    case interaction
    case command

    var displayName: String {
        switch self {
        case .state:       return "Состояния"
        case .emotion:     return "Эмоции"
        case .interaction: return "Взаимодействие"
        case .command:     return "Команды"
        }
    }

    var icon: String {
        switch self {
        case .state:       return "🔄"
        case .emotion:     return "😊"
        case .interaction: return "👆"
        case .command:     return "⚡"
        }
    }
}
```

### Changes to `CompanionProfile` (Models.swift)

1. Add field:
```swift
var animationEventMappings: [String: [AnimationSlotItem]] = Self.defaultEventMappings()
```

2. Add to `CodingKeys` enum:
```swift
case animationEventMappings
```

3. Add decode in `init(from decoder:)`:
```swift
animationEventMappings = try container.decodeIfPresent(
    [String: [AnimationSlotItem]].self,
    forKey: .animationEventMappings
) ?? Self.defaultEventMappings()
```

4. Add static default mappings method:
```swift
static func defaultEventMappings() -> [String: [AnimationSlotItem]] {
    // NOTE: filePaths here are relative names only — resolved at runtime
    // using AppEnvironment.assetsRootURL
    var m: [String: [AnimationSlotItem]] = [:]

    // Startup: greeting2.vrma
    m["startup"] = [
        AnimationSlotItem(assetType: .vrma, displayName: "greeting2",
                          filePath: "VRMA/greeting2.vrma")
    ]

    // Idle: the four neutral BVH animations
    m["idle"] = [
        AnimationSlotItem(assetType: .bvh, displayName: "neutral",  filePath: "BVH/neutral.bvh"),
        AnimationSlotItem(assetType: .bvh, displayName: "neutral2", filePath: "BVH/neutral2.bvh"),
        AnimationSlotItem(assetType: .bvh, displayName: "neutral3", filePath: "BVH/neutral3.bvh"),
        AnimationSlotItem(assetType: .bvh, displayName: "neutral4", filePath: "BVH/neutral4.bvh"),
    ]

    // All other events start empty — user configures them
    return m
}
```

> **Note on filePaths:** Store as relative paths from `assetsRootURL` (e.g. `"VRMA/greeting2.vrma"`, `"BVH/neutral.bvh"`, `"Poses/sitting.vroidpose"`). At runtime, resolve with `AppEnvironment.assetsRootURL.appendingPathComponent(item.filePath).path`.

---

## Runtime Logic

### New method in `CompanionViewModel`

```swift
/// Trigger an event animation. Called by state observers, gesture handlers, and (future) text analysis.
func triggerEventAnimation(_ event: AnimationEventType) {
    let items = profile.animationEventMappings[event.rawValue] ?? []
    guard let item = items.randomElement() else { return }

    let fullPath = AppEnvironment.assetsRootURL
        .appendingPathComponent(item.filePath).path

    switch item.assetType {
    case .vrma:
        manualVRMARequest = CompanionVRMARequest(
            label: item.displayName, filePath: fullPath)
    case .bvh:
        // Re-use existing previewBVH which handles async BVH→VRMA conversion
        let opt = CompanionBVHOption(id: fullPath, displayName: item.displayName, filePath: fullPath)
        previewBVH(opt)
    case .pose:
        manualPoseRequest = CompanionPoseRequest(
            label: item.displayName, filePath: fullPath)
    }
}
```

### Hooks in CompanionViewModel

**Emotion state changes** — in `setEmotion(for text: String)` or its observer:
```swift
// Map CompanionEmotionState → AnimationEventType and trigger
private func triggerEmotionAnimation(for emotion: CompanionEmotionState) {
    let event: AnimationEventType
    switch emotion {
    case .happy:    event = .joy
    case .excited:  event = .excitement
    case .angry:    event = .anger
    case .shy:      event = .embarrassment
    case .sleepy:   event = .relief      // placeholder
    case .thinking: event = .curiosity
    case .neutral:  return
    }
    triggerEventAnimation(event)
}
```
Call `triggerEmotionAnimation(for: newEmotion)` when `emotionState` changes to non-neutral.

**Presence state changes** — when `presenceState` transitions:  
- `.thinking` → `triggerEventAnimation(.thinking)` (one-shot reaction, then view cycles thinking idles)
- `.listening` → `triggerEventAnimation(.listening)`

**Gesture events:**
- In `pulseDragging()`: also call `triggerEventAnimation(.drag)`
- In tap callback (`tapHandler`): also call `viewModel.triggerEventAnimation(.tap)` (in addition to opening chat)

### View changes in CompanionVRMRealityView

**Replace hardcoded startup with mapping:**
```swift
// In playStartupGreeting() — resolve from profile mapping
func playStartupGreeting() {
    let items = animationEventMappings["startup"] ?? []
    guard let item = items.randomElement() else { return }
    let fullPath = AppEnvironment.assetsRootURL
        .appendingPathComponent(item.filePath).path
    // play based on assetType...
}
```

**Replace hardcoded idle list with mapping:**
```swift
// In playNextIdleAnimation()
private func playNextIdleAnimation() {
    let items = animationEventMappings["idle"] ?? []
    // filter to avoid repeating last item (use idleLastIndex → idleLastId: UUID?)
    let available = items.filter { $0.id != idleLastId }
    guard let item = (available.isEmpty ? items : available).randomElement() else { return }
    idleLastId = item.id
    // dispatch based on assetType: .bvh → BVHConverter, .vrma → playVRMA
}
```

**Add `animationEventMappings` property to view:**
```swift
var animationEventMappings: [String: [AnimationSlotItem]] = [:]
```
Set from `AvatarPanelContentView.bindViewModel()`:
```swift
viewModel.$profile
    .sink { [weak vrmView] profile in
        vrmView?.animationEventMappings = profile.animationEventMappings
    }
    .store(in: &cancellables)
```

**Pose hold duration** — when a one-shot event plays a pose, it should auto-clear after N seconds so idle cycling can resume. Add to view:
```swift
private var poseHoldTimer: Timer?
private let defaultPoseHoldDuration: TimeInterval = 4.0

func applyEventPose(filePath: String) {
    applyPose(filePath: filePath)
    poseHoldTimer?.invalidate()
    poseHoldTimer = Timer.scheduledTimer(withTimeInterval: defaultPoseHoldDuration,
                                          repeats: false) { [weak self] _ in
        self?.clearPose()
    }
}
```

---

## Settings UI

**Location:** `CompanionSettingsView` in `CharApp.swift`  
**Add as a new `Section`** with header `"Анимации и реакции"`.

### Layout

Split-pane layout inside the section:
- **Left column** — Palette: all discovered animations (VRMA + BVH + Poses in one list)
- **Right column** — Events: grouped by category, each with a drop zone

### Palette item brick colors
- VRMA: `.teal` / green
- BVH: `.blue` / cyan  
- Pose: `.purple`

### Drag-and-drop implementation

Use SwiftUI `Transferable` + `.draggable()` / `.dropDestination()` (requires macOS 13+, which the project already targets).

```swift
// Palette item
Text(item.displayName)
    .draggable(item)

// Event slot drop zone
HStack { /* existing bricks */ }
    .dropDestination(for: AnimationSlotItem.self) { droppedItems, _ in
        for item in droppedItems {
            if !mapping.contains(where: { $0.id == item.id }) {
                mapping.append(item)
            }
        }
        viewModel.profile.animationEventMappings[event.rawValue] = mapping
        return true
    }
```

### Remove brick
Each brick has an `×` button that removes it from the event's list and calls `persistProfile()`.

### UI Structure (pseudocode)

```swift
Section("Анимации и реакции") {
    HStack(alignment: .top, spacing: 16) {

        // LEFT: Palette
        VStack(alignment: .leading) {
            Text("Доступные").font(.headline)
            ScrollView {
                ForEach(allAnimationsUnified) { item in
                    AnimationBrick(item: item)
                        .draggable(item)
                }
            }
        }
        .frame(width: 180)

        // RIGHT: Event slots grouped by category
        ScrollView {
            ForEach(AnimationEventCategory.allCases, id: \.self) { category in
                Text("\(category.icon) \(category.displayName)").font(.headline)
                ForEach(AnimationEventType.allCases.filter { $0.category == category }) { event in
                    AnimationEventRow(
                        event: event,
                        items: viewModel.profile.animationEventMappings[event.rawValue] ?? [],
                        onUpdate: { newItems in
                            viewModel.profile.animationEventMappings[event.rawValue] = newItems
                            viewModel.persistProfile()
                        }
                    )
                }
            }
        }
    }
}
```

---

## Unified Palette (allAnimationsUnified)

Computed from the three existing catalog arrays in `CompanionViewModel`:

```swift
var allAnimationsUnified: [AnimationSlotItem] {
    let vrmas = availableVRMAAnimations.map {
        AnimationSlotItem(assetType: .vrma, displayName: $0.displayName,
                          filePath: relativePath($0.filePath))
    }
    let bvhs = availableBVHAnimations.map {
        AnimationSlotItem(assetType: .bvh, displayName: $0.displayName,
                          filePath: relativePath($0.filePath))
    }
    let poses = availablePoses.map {
        AnimationSlotItem(assetType: .pose, displayName: $0.displayName,
                          filePath: relativePath($0.filePath))
    }
    return vrmas + bvhs + poses
}

private func relativePath(_ fullPath: String) -> String {
    let assetsRoot = AppEnvironment.assetsRootURL.path
    return String(fullPath.dropFirst(assetsRoot.count + 1)) // strip leading slash
}
```

---

## Implementation Order

| Step | File | Task |
|------|------|------|
| 1 | `Models.swift` | Add `AnimationSlotItem`, `AnimationAssetType`, `AnimationEventType`, `AnimationPlayMode`, `AnimationEventCategory`. Extend `CompanionProfile`. |
| 2 | `CompanionViewModel.swift` | Add `triggerEventAnimation()`, emotion/presence/gesture hooks, `allAnimationsUnified` computed property. Expose `persistProfile()` as `internal` (currently `private`). |
| 3 | `CompanionViews.swift` | Add `animationEventMappings` property to `CompanionVRMRealityView`. Replace hardcoded startup/idle with mapping lookups. Add `applyEventPose()` with hold timer. Update binding in `bindViewModel()`. |
| 4 | `CharApp.swift` | Add "Анимации и реакции" section to `CompanionSettingsView`. Implement palette + event slots with drag-and-drop. |
| 5 | Test | Verify default mappings work (startup + idle). Verify persistence survives app restart. Verify tap/drag events fire. |

---

## Important Implementation Notes

1. **`CompanionProfile.CodingKeys` must be kept in sync** — every new field needs both a `CodingKeys` case and a `decodeIfPresent` line in `init(from decoder:)`. Missing either silently drops the field on decode.

2. **BVH async conversion** — `BVHConverter.vrmaPath(for:)` is async and must be called in `Task.detached`. Follow the pattern in `playNextIdleAnimation()`.

3. **`idleConverting` guard** — `updateIdleAnimation` checks `!idleConverting` to avoid double-firing. Keep this guard when replacing the hardcoded idle list.

4. **Emotion + animation independence** — emotions change blend shapes (expressions), animations change body pose. They are completely independent layers. Do not block emotion changes because an animation is playing, and do not interrupt ongoing animations just because emotion changed.

5. **`speaking` cycling** — when `presenceState == .speaking`, the view should cycle speaking animations similarly to idle (random pick from the `speaking` slot, replay on finish). Currently there is no speaking animation cycling. This needs to be added alongside idle cycling in `updateIdleAnimation` or a new `updateSpeakingAnimation`.

6. **One-shot + return** — for emotion/interaction/command events: play once, then resume the current state's cycling animation. The existing `vrmaPlayer == nil` → idle cycle logic already handles this for idle. For speaking, need similar logic.

7. **`persistProfile()` visibility** — it is currently `private` in `CompanionViewModel`. Change to `internal` so the settings UI binding can call it after updating `profile.animationEventMappings`.

8. **UTType declaration** — the `UTType` extension for `animationSlotItem` must be declared in the app's `Info.plist` as an exported type identifier, or alternatively use a simpler `Transferable` implementation via `DataRepresentation` to avoid the plist requirement.

   Simpler alternative:
   ```swift
   static var transferRepresentation: some TransferRepresentation {
       DataRepresentation(contentType: .data) { item in
           try JSONEncoder().encode(item)
       } importing: { data in
           try JSONDecoder().decode(AnimationSlotItem.self, from: data)
       }
   }
   ```

9. **Default mappings resolve at runtime** — `CompanionProfile.defaultEventMappings()` stores relative paths. Ensure `AppEnvironment.assetsRootURL` is available wherever these are resolved. If `assetsRootURL` changes (e.g. different build), relative paths still work.

10. **Backward compatibility** — existing users have no `animationEventMappings` in UserDefaults. The `decodeIfPresent(...) ?? Self.defaultEventMappings()` in `init(from decoder:)` handles this gracefully.
