# Char — Soul System Specification

> Version: 0.2
> Date: 2026-04-20
> Status: Proposed
> Scope: production-ready specification for memory, character, emotion, and command handling in Char

This document describes the **Soul** subsystem for Char: long-term memory, character identity, emotional expression, reaction planning, and direct command execution.

The goal is not just to "add memory", but to make the on-screen character feel persistent, personal, expressive, and internally coherent without overflowing the model context window.

The spec is written so that **any agent can implement it without guessing product intent**.

---

## 0. TL;DR

Soul consists of 4 runtime domains:

1. **Memory Engine**
   Stores raw dialogue, extracts compact facts, compresses old sessions, retrieves only relevant information, and persists between launches.

2. **Character Engine**
   Stores the character definition as structured data (`SoulCard`), including persona, speech style, world rules, lorebook, backstory, values, taboos, and growth log.

3. **Emotion Pipeline**
   Produces 4 synchronized outputs from each answer:
   - face expression
   - TTS prosody
   - body reaction / animation
   - long-lived mood state

4. **Command Router**
   Detects direct user commands like "повернись", "подними руку", "потанцуй", executes them locally, and lets the LLM only comment on them instead of pretending to perform them.

Core design rule:

- **The journal is verbatim, the prompt is compressed.**

The system must always preserve raw history locally, but never stuff full history into the prompt. Prompt assembly always uses:

- character identity
- pinned/core memory
- relevant retrieved facts
- relevant episode summaries
- active lorebook entries
- recent turns

Default prompt budget target: **<= 6k tokens**.

---

## 1. Why This Spec Exists

Char already has:

- a desktop avatar
- VRM/Live2D rendering
- TTS
- LLM chat
- an animation event system

Char does not yet have:

- durable memory between sessions
- a first-class character format
- a reliable separation between "who the character is" and "what the model improvises"
- synchronized emotion across face, voice, and body
- deterministic handling of direct user commands

Without Soul, the character risks feeling like a stateless chat wrapper with animation.

With Soul, the character should feel closer to a living companion:

- remembers important things
- stays in character over time
- grows without becoming incoherent
- reacts in voice and body, not just text
- can obey direct commands

---

## 2. External Research And What We Take From It

This section is normative in intent, not in implementation. We borrow useful ideas, not code or branding.

### 2.1 Character.AI

Public Character.AI updates show a useful product direction:

- On **March 31, 2025**, Character.AI announced **Auto Memories** that capture facts from long-running chats.
- On **June 1, 2025** in the May 2025 update, Character.AI announced **Chat Memories**, a user-editable fixed memory box with up to **400 characters**.
- On **April 2025** they announced editable auto memories and noted that first memories begin appearing only after about **40 messages**.
- On **October 4, 2025** in the September 2025 update, they said **Lorebook** was still being actively shaped through user research.

What we take:

- users want both **automatic** and **manual** memory
- fixed pinned memory is valuable
- memory must be visible and editable
- long chats need explicit world/scenario support

What we do not copy:

- opaque memory behavior
- delayed visibility of memory state
- memory as a hidden platform feature

For Char, memory must be:

- local-first
- inspectable
- editable
- partitioned by type
- usable by the agent immediately

### 2.2 MemPalace

The MemPalace README emphasizes:

- **verbatim local storage**
- **semantic retrieval**
- **pluggable backend**
- **validity-aware knowledge graph**

This is useful because it reinforces two strong principles:

- do not destroy raw dialogue
- separate storage from retrieval

What we take:

- append-only raw journal
- local-first persistence
- validity windows for facts

What we reject for Char as a core concept:

- palace metaphor as a required mental model
- pure verbatim retrieval without structured fact extraction

Char needs both:

- raw history
- structured compact memory

### 2.3 Letta / MemGPT

Letta's documentation clearly separates:

- core memory that stays in context
- archival memory that stays out of context and is retrieved on demand

This separation is directly applicable to Char.

### 2.4 mem0

The Mem0 paper argues for:

- dynamic extraction of salient information
- consolidation
- retrieval instead of full-context replay
- optional graph memory for relationships

This aligns strongly with Char.

### 2.5 Soul-of-Waifu

The local reference project is useful mainly as a product comparison point:

- card import matters
- lorebook matters
- long chat memory matters
- voice/avatar integration matters

What we may reuse conceptually:

- card compatibility expectations
- prompt section ordering
- split between short context and long memory

What we should improve:

- stronger memory contracts
- better forgetting and contradiction handling
- richer emotion synchronization
- stricter command execution rules

---

## 3. Design Principles

The following rules are normative.

1. **Local-first by default**
   All memory data lives on disk locally unless the user explicitly chooses a cloud model. If a cloud model is used, only prompt material is sent, not the full database.

2. **Verbatim history is sacred**
   Raw turns are stored as-is in the journal and are never rewritten by summarization.

3. **Structured memory is selective**
   Not every line becomes a fact. Only information that is salient, stable, or likely to matter later should be promoted.

4. **Prompts are layered**
   The model never receives the full journal. Prompt assembly is deterministic and budgeted.

5. **Character is data**
   Character identity is stored in structured files, not in a giant handwritten system prompt only.

6. **Commands are real actions**
   If the user says "raise your right hand", the body layer executes it directly. The LLM may react verbally, but it does not decide whether the command happened.

7. **Emotions are multimodal**
   Emotion is not one enum on the final text. It is face, body, voice, and mood together.

8. **Growth must be bounded**
   The character may evolve, but core identity cannot drift uncontrollably.

9. **Memory must be debuggable**
   The user and developers should be able to inspect what is stored, why it was stored, and what was retrieved.

10. **Graceful degradation**
   If embeddings fail, retrieval falls back to FTS/BM25.
   If structured output fails, fall back to tags.
   If tags fail, fall back to plain text with heuristic emotion.

---

## 4. System Overview

### 4.1 Runtime Modules

```text
ChatVM
  -> CommandRouter
  -> MemoryEngine.retrieve()
  -> CharacterEngine.activeCard()
  -> PromptBuilder
  -> LLMClient.stream()
  -> OutputParser
  -> EmotionPipeline
  -> SpeechCoordinator / VRM / Live2D
  -> MemoryEngine.ingest()
```

### 4.2 Main Data Domains

Soul stores data in 5 conceptual buckets:

1. `journal`
   Raw append-only dialogue and reflections.

2. `facts`
   Compact atomic statements with confidence and temporal metadata.

3. `episodes`
   Summaries of related windows of conversation.

4. `character`
   SoulCard, lorebook, growth log, self-facts, relationship state.

5. `mood`
   Persistent PAD state plus short-lived reaction state.

### 4.3 Storage Location

One profile gets one Soul store:

`~/Library/Application Support/Char/soul/{profileId}/`

Recommended contents:

- `soul.db`
- `cards/`
- `exports/`
- `logs/`

---

## 5. Memory Model

### 5.1 Memory Layers

Char uses 6 memory layers:

| Layer | Purpose | In prompt | Mutability |
|---|---|---|---|
| `L0 Identity` | SoulCard identity, world rules, taboos, speech style | always | rare |
| `L1 Core` | pinned durable facts | always | manual + selective auto |
| `L2 Working` | recent turns | always | rolling |
| `L3 Semantic` | retrieved compact facts | on demand | continuous |
| `L4 Episodic` | retrieved summaries of old interactions | on demand | continuous |
| `L5 Archive` | heavily compressed old memory | rare | background only |

Important:

- `journal` is not itself a prompt layer
- archive exists for retrieval, not for routine prompt stuffing

### 5.2 Memory Domains

Every fact must belong to a domain:

- `user_profile`
- `character_self`
- `relationship`
- `world`
- `scenario`
- `session_ephemeral`

This matters because Char must not mix:

- real user facts
- roleplay-only facts
- temporary situation facts

Example:

- "Меня зовут Денис" -> `user_profile`
- "Сегодня я злой" -> `session_ephemeral`
- "Мы сейчас играем сцену в замке" -> `scenario`
- "Char заботится о пользователе" -> `relationship`

### 5.3 Fact Truth Levels

Each fact must also have a truth class:

- `explicit`
- `inferred`
- `roleplay`
- `obsolete`

Rules:

- only `explicit` and stable `inferred` facts may enter `core`
- `roleplay` facts must never overwrite canonical user profile facts
- `obsolete` facts remain queryable for timeline/history but are excluded from default retrieval

### 5.4 What Gets Stored As A Fact

A new fact should be created only if at least one of these is true:

- the user directly states a stable personal fact
- the user directly states a preference
- the character or user defines a relationship state that may matter later
- the exchange establishes a recurring project, plan, concern, or taboo
- a repeated transient fact becomes persistent through confirmation

A fact should not be created for:

- small talk filler
- purely rhetorical lines
- hypothetical statements
- jokes that are obviously non-canonical
- impermanent emotional color unless repeated or important

### 5.5 Core Memory Policy

`core` is extremely small and deliberate.

Constraints:

- target <= 500 tokens
- hard max 10 entries
- only high-value facts

Allowed in core:

- user name and preferred form of address
- critical preferences
- critical boundaries / sensitive topics
- stable relationship facts
- crucial character self-identity anchors

Core promotion sources:

- manual pin by user
- manual pin by developer/admin UI
- selective tool call from model after confirmation rules

The model may suggest core promotion, but the engine decides.

### 5.6 Journal Policy

The journal is append-only and stores:

- user turns
- assistant turns
- reflection turns
- system events relevant to memory

Journal guarantees:

- no auto-rewrites
- no loss due to summarization
- exportable as JSONL

### 5.7 Fact Schema

Minimum fact structure:

```json
{
  "id": "ULID",
  "profileId": "UUID",
  "domain": "user_profile",
  "truthClass": "explicit",
  "subject": "user",
  "predicate": "has_pet",
  "object": "entity://dog/barsik",
  "value": "Барсик, корги, 3 года",
  "confidence": 0.91,
  "salience": 0.73,
  "firstSeen": "2026-04-20T12:00:00Z",
  "lastConfirmed": "2026-04-20T12:00:00Z",
  "validFrom": null,
  "validUntil": null,
  "invalidatedAt": null,
  "sourceTurns": ["..."],
  "pinned": false
}
```

Required metadata:

- confidence
- salience
- source turn ids
- timestamps
- invalidation fields

### 5.8 Contradictions

Contradictions must not delete history.

When a new fact conflicts with an old fact:

1. keep both
2. mark the old one `obsolete`
3. set `invalidatedAt`
4. link the replacement fact

Example:

- old: `user lives_in Kyiv`
- new: `user lives_in Warsaw`

Result:

- Warsaw becomes current
- Kyiv remains as past information, not default retrieval

### 5.9 Consolidation

Consolidation is a background process with 4 jobs:

1. **episode segmentation**
   Group related turn windows into episodes.

2. **fact merge**
   Deduplicate near-identical facts.

3. **summary compression**
   Turn older dialogue into shorter episode summaries.

4. **archive compression**
   Merge very old episodes into month-scale archive entries.

Default temporal ladder:

- `0-1 day`: journal + rich episode summary
- `1-7 days`: shorter episode summary
- `7-30 days`: compact episode summary
- `30+ days`: archive summary

The journal still stays intact.

### 5.10 Retrieval

Retrieval is hybrid.

Scoring combines:

- vector similarity
- BM25 / FTS score
- recency
- salience
- domain match
- entity match
- contradiction filter

Suggested formula:

```text
score =
  0.45 * vector
  0.20 * bm25
  0.12 * recency
  0.13 * salience
  0.05 * domain_match
  0.05 * entity_match
```

Default retrieved bundle:

- up to 8 facts
- up to 3 episodes
- optional 1 archive summary if highly relevant

Target retrieval budget:

- <= 1500 prompt tokens combined

### 5.11 Prompt Budget Policy

Default order of importance:

1. system format rules
2. character identity
3. taboos and safety rules
4. core memory
5. retrieved facts
6. active lorebook
7. retrieved episodes
8. current mood
9. recent turns
10. archive

When over budget:

- archive drops first
- then lowest-score episodes
- then lowest-score facts
- then oldest recent turns

Core and identity should be the last to shrink.

### 5.12 Memory Write Rules

To keep memory clean, the engine must apply these filters:

- fact extraction runs after the full turn completes
- the extractor sees the new turn plus relevant known facts
- low-confidence facts below threshold are discarded
- the same fact seen repeatedly increases confidence
- a fact may be auto-pinned only after repeated confirmation or explicit user request

Recommended thresholds:

- write threshold: `0.55`
- retrieval threshold: `0.35`
- auto-core threshold: `0.90` plus repeat count

### 5.13 Reflections

Reflections are allowed, but constrained.

They may:

- write diary-like notes
- form questions to ask later
- update mood
- append character-self observations

They may not:

- create canonical user facts from pure speculation
- rewrite the SoulCard identity
- overwrite pinned memory

### 5.14 User Controls

The UI must allow:

- view fact list
- pin / unpin fact
- mark fact incorrect
- forget fact
- inspect source turns
- export memory
- reset profile memory

Memory must never be a black box.

---

## 6. Character Model

### 6.1 SoulCard

`SoulCard` is the structured character format for Char.

It should be compatible with common roleplay card formats where practical, but Char's runtime must treat it as its own first-class schema.

The card must include:

- name
- description
- personality
- scenario
- speech style
- values
- taboos
- relationship defaults
- lorebook
- backstory
- growth settings
- default mood baseline
- optional avatar / TTS metadata

### 6.2 Character Identity Contract

Character identity is split into 3 zones:

1. **immutable anchors**
   Name, core concept, major taboos, key values.

2. **stable style**
   Speech rhythm, tone, habits, worldview tendencies.

3. **evolving state**
   Relationship score, growth log, chapter progress, current mood.

Rules:

- reflections may affect evolving state
- user edits may affect any zone
- automatic growth may not rewrite immutable anchors

### 6.3 Lorebook

Lorebook entries are activated by:

- keyword hit
- entity hit
- scenario mode
- explicit tag

Each entry should support:

- priority
- token budget
- sticky mode
- cooldown
- optional probability
- optional scenario scope

Lorebook exists to help the model stay consistent without bloating the base card.

### 6.4 Growth

Character growth is allowed but bounded.

Growth may record:

- relationship changes
- recurring concerns
- learned habits
- self-observations
- story chapter progress

Growth may not:

- erase personality anchors
- invent a new worldview without repeated evidence
- silently change taboos or safety rules

Growth entries should be append-only and summarized into a compact `growth_log`.

### 6.5 Character Self-Memory

The character also needs self-facts, not only user facts.

Examples:

- what the character values
- what the character worries about
- what promises the character made
- what emotional themes recur in the relationship

This self-memory is critical for making the character feel alive and internally continuous.

---

## 7. Emotion Model

### 7.1 Four Layers

Every answer segment may affect 4 layers:

1. `face`
2. `prosody`
3. `body`
4. `mood`

These layers share a source event but have separate lifetimes.

### 7.2 Emotion Vocabulary

Recommended normalized set:

- `neutral`
- `smiling`
- `happy`
- `joyful`
- `sad`
- `crying`
- `angry`
- `furious`
- `surprised`
- `shocked`
- `scared`
- `disgusted`
- `shy`
- `embarrassed`
- `thinking`
- `curious`
- `love`
- `confused`
- `relieved`
- `proud`
- `bored`
- `sleepy`
- `pained`
- `nervous`

This is richer than raw VRM presets and should be projected down to available avatar capabilities.

### 7.3 Face Layer

Face layer maps normalized emotions to:

- VRM standard expressions
- custom blendshapes if available
- fallback legacy emotion state

Rules:

- expression changes should fade smoothly
- one segment may specify intensity
- missing custom shapes must not break the animation

### 7.4 Prosody Layer

Prosody instructs TTS how to say a segment.

Supported fields:

- style
- rate
- pitch
- volume
- pause before
- pause after
- emphasis

Allowed style examples:

- `calm`
- `cheerful`
- `tired`
- `whisper`
- `shout`
- `trembling`
- `playful`
- `shy`
- `angry`
- `sarcastic`

### 7.5 Body Layer

Body layer maps to the existing `AnimationEventType` system.

It must not invent unsupported actions.

The body layer can be driven by:

- explicit user command
- LLM-selected reaction
- emotion fallback mapping
- idle/state cycle

### 7.6 Mood Layer

Mood is long-lived and stored separately from per-segment emotion.

Use PAD:

- pleasure / valence
- arousal
- dominance

Mood affects:

- default resting face
- default prosody when unspecified
- retrieval bias
- reflection tone

Mood should decay slowly toward character baseline.

### 7.7 Reaction Arbitration

This is one of the most important parts of the spec.

Priority order:

1. safety constraints
2. explicit user command
3. currently locked body action
4. explicit reaction from output segment
5. emotion fallback reaction
6. state animation
7. idle animation

Interpretation:

- if the user says "подними правую руку", that action wins
- the LLM may accompany it with words or a face emotion
- the model must not cancel or replace the direct command with a different animation

### 7.8 Emotion Timing Targets

Recommended targets:

- face response after parsed segment: <= 100 ms
- body trigger after parsed segment: <= 150 ms
- TTS style application before audio playback: <= 50 ms additional overhead
- end-to-end visible emotional response after segment parse: <= 300 ms

---

## 8. Commands

### 8.1 Command Types

Commands come in 3 groups:

1. **mapped commands**
   Directly map to existing animation events.
   Example: `dance`, `wave`, `jump`.

2. **pose commands**
   Trigger a known pose or pose-like action.
   Example: `sit`, `kneel`, `turn this way`.

3. **bone / parametric commands**
   Low-level body manipulation.
   Example: `raise right arm`, `turn left`, `look up`.

### 8.2 Parsing Policy

Command parsing happens before the LLM request.

The parser should return:

```json
{
  "commands": [
    {
      "type": "raise_arm",
      "side": "right",
      "strength": 0.8
    }
  ],
  "residualText": "можешь поднять правую руку?"
}
```

### 8.3 Safety Constraints

Commands must be whitelisted and bounded.

Examples:

- arm rotation max angle
- body tilt max range
- no unsupported skeleton operations
- no endless animation lock without timeout

### 8.4 LLM Awareness

The prompt should explicitly say:

- direct movement commands were already executed by the engine
- the model should verbally react, not narrate fake execution

Good:

- "Да, подняла."

Bad:

- "Я медленно поднимаю руку..." when the engine did not or could not perform it

---

## 9. LLM Output Contract

### 9.1 Preferred Structured Format

Preferred response structure:

```json
{
  "segments": [
    {
      "text": "Привет.",
      "emotion": "smiling",
      "intensity": 0.55,
      "prosody": {
        "style": "calm",
        "rate": -0.05
      },
      "reaction": "wave"
    }
  ],
  "moodDelta": {
    "valence": 0.05,
    "arousal": 0.02,
    "dominance": 0.00
  },
  "memoryHints": [
    {
      "kind": "candidate_fact",
      "reason": "user stated a stable preference"
    }
  ]
}
```

### 9.2 Fallback Tagged Format

Fallback example:

```text
[e:smiling][r:wave]Привет.[/r]
[p:calm rate=-0.05]Я тебя слушаю.[/p]
```

### 9.3 Parser Rules

The parser must:

- work incrementally with streaming chunks
- emit segments as soon as complete
- validate emotion and reaction values against whitelists
- downgrade unknown values safely

### 9.4 Non-Goals For The Output Contract

The model should not directly:

- mutate the database
- decide whether commands physically executed
- write arbitrary memory entries without engine validation

The model may only suggest memory actions.

---

## 10. Prompt Assembly

Recommended prompt order:

1. output format rules
2. character identity
3. speech style
4. values and taboos
5. scenario / lorebook
6. relationship state
7. core memory
8. retrieved facts
9. retrieved episodes
10. current mood
11. recent turns
12. current user message

The prompt builder should produce a bundle object first, then render it to provider-specific messages.

This makes the system easier to test.

---

## 11. Implementation In Char

### 11.1 New Package

Create `Sources/SoulKit/`.

Suggested submodules:

- `Memory/`
- `Character/`
- `Emotion/`
- `Commands/`
- `LLM/`
- `Util/`

### 11.2 Key Integration Points

The current app already has the main hooks we need:

- `CompanionViewModel.swift`
- `Models.swift`
- `SpeechCoordinator.swift`
- `CompanionViews.swift`
- animation event mapping in `AnimationEventType`

Required integration work:

1. initialize a Soul session per profile
2. replace raw `conversationMessages` prompt construction with `PromptBuilder`
3. ingest turns after completion
4. route streamed deltas through `OutputParser`
5. feed parsed segments into face, body, and TTS
6. persist memory between launches
7. add memory and card management UI

### 11.3 Storage Tech

Recommended:

- SQLite
- FTS5
- GRDB.swift

Embeddings may start as:

- SQLite BLOB vectors with brute-force search

This is acceptable for MVP and keeps the stack simple.

---

## 12. Delivery Plan

### Phase 0: Foundation

Deliver:

- `SoulKit` package scaffold
- `soul.db`
- journal persistence
- fact schema
- retrieval bundle type

Definition of done:

- restart-safe journal storage works

### Phase 1: Memory MVP

Deliver:

- fact extraction
- core memory
- recent-turn prompt builder
- BM25 retrieval
- memory UI list

Definition of done:

- user facts survive relaunch

### Phase 2: Character Engine

Deliver:

- `SoulCard`
- import compatibility
- lorebook activation
- structured character editor

Definition of done:

- different cards produce clearly different behavior on identical prompts

### Phase 3: Emotion + Commands

Deliver:

- structured output parser
- face layer
- prosody layer
- body reaction mapping
- direct command router

Definition of done:

- command execution and emotional response are visibly synchronized

### Phase 4: Consolidation

Deliver:

- episode summaries
- archive compression
- embeddings
- hybrid retrieval

Definition of done:

- long chats stay under prompt budget without obvious memory loss

### Phase 5: Reflection + Growth

Deliver:

- reflection jobs
- growth log
- bounded self-evolution

Definition of done:

- the character can reference prior relationship development without identity drift

---

## 13. Acceptance Criteria

The system is successful when all of the following are true:

1. After relaunch, the character still remembers stable user facts.
2. After very long chats, the prompt stays within budget.
3. Contradictory facts are resolved without deleting history.
4. Direct body commands execute locally and deterministically.
5. Emotion affects face, voice, and body in sync.
6. Different SoulCards create reliably different personalities.
7. Memory is inspectable and editable by the user.
8. Growth happens without breaking core character identity.

---

## 14. Explicit Non-Goals For v1

The following are intentionally out of scope for the first production version:

- multi-character autonomous conversations
- vision memory
- dream generation
- full knowledge graph UI
- deep autonomous planning loops
- cloud sync

These can come later, but they should not block the first real Soul implementation.

---

## 15. Recommended Tables

Minimum SQLite tables:

- `journal_turns`
- `facts`
- `episodes`
- `archive_entries`
- `soul_cards`
- `mood_state`
- `settings`
- `embeddings`

This is enough for the full architecture without overcomplicating the MVP.

---

## 16. Recommended Tests

Must-have tests:

- fact extraction and merge
- contradiction invalidation
- prompt budget enforcement
- retrieval relevance
- parser recovery from malformed JSON
- command arbitration priority
- mood decay
- persistence across restart

Must-have manual scenarios:

- "Как зовут мою собаку?" after restart
- "Нет, меня зовут не Денис, а Дима"
- "Подними правую руку"
- "Потанцуй"
- 30+ minutes of chat with later recall

---

## 17. Source Summary

Sources used to shape this design:

- Character.AI Help Center:
  - March 31, 2025 update on Auto Memories:
    `https://support.character.ai/hc/en-us/articles/35409588582683-Community-Update-March-2025`
  - June 1, 2025 update on Chat Memories:
    `https://support.character.ai/hc/en-us/articles/37510587029531-Community-Update-May-2025`
  - April 2025 update on editable auto memories and memory visibility:
    `https://support.character.ai/hc/en-us/articles/36429196456475-Community-Update-April-2025`
  - October 4, 2025 update mentioning Lorebook research:
    `https://support.character.ai/hc/en-us/articles/41760067000475-Community-Update-September-2025`
- MemPalace GitHub README:
  `https://github.com/MemPalace/mempalace`
- Letta archival memory docs:
  `https://docs.letta.com/guides/ade/archival-memory`
- Mem0 paper:
  `https://arxiv.org/abs/2504.19413`
- Local reference project:
  `ThirdParty/Soul-of-Waifu`
- Existing Char docs and source files:
  - `Docs/SPEC.md`
  - `Docs/ANIMATION_EVENT_SYSTEM_SPEC.md`
  - `Docs/VRM-Animation-Spec.md`
  - `Sources/CharApp/Models.swift`
  - `Sources/CharApp/CompanionViewModel.swift`
  - `Sources/CharApp/CompanionViews.swift`
  - `Sources/CharApp/SpeechCoordinator.swift`

---

## 18. Final Product Positioning

The right mental model for Soul is:

- not "chat history with summaries"
- not "RAG bolted onto a persona prompt"
- not "emotion by regex after the answer is done"

Soul should behave like a **stateful companion runtime**:

- memory is selective
- identity is structured
- emotion is multimodal
- commands are real
- growth is bounded

That is the shortest path to a character that feels genuinely alive.
