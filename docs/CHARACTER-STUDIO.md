# Character Studio

## Concept

The Character Studio is the core abstraction in SwiftVoxAlta. It is the process of going from written text to a voiced character -- deriving the voice from the script itself rather than from external direction.

A character in a script reveals who they are through:
- What they say (dialogue content, vocabulary, sentence structure)
- How the writer describes them (action lines, character introductions)
- What directions the writer gives (parentheticals like "quietly", "with barely contained rage")
- What other characters say about them
- The context of scenes they appear in

The Character Studio extracts this evidence and distills it into a voice.

## The Pipeline

```
Script Text
    |
    v
[1] Script Parser ---- extracts characters, dialogue, directions
    |
    v
[2] Character Analyzer ---- LLM pass (SwiftBruja) to build profiles
    |
    v
[3] Voice Designer ---- Qwen3-TTS VoiceDesign from profile
    |
    v
[4] Voice Audition ---- generate candidates, user selects
    |
    v
[5] Voice Lock ---- persist reference clip + clone prompt
    |
    v
[6] Line Renderer ---- Qwen3-TTS Base cloning for all dialogue
    |
    v
Audio Output
```

## Step Details

### 1. Script Parser

Parses Fountain-formatted scripts (or attributed plain text) into structured data:

```
ScriptElement
  - Character name
  - Dialogue text
  - Parenthetical (optional)
  - Scene heading context
  - Action/description lines mentioning this character
```

This is a text parsing problem, not an ML problem. A Fountain parser produces this deterministically.

### 2. Character Analyzer

An LLM pass (via SwiftBruja) that reads all of a character's textual evidence and produces a structured profile:

```
CharacterProfile
  - name: "ELENA"
  - gender: "female"
  - ageRange: "late 30s"
  - description: "A former military officer turned diplomat. Precise
    in speech, measured in delivery. Her dialogue is clipped and
    economical -- she does not waste words."
  - voiceTraits: ["controlled", "low-mid register", "deliberate pacing",
    "slight tension underneath calm surface"]
  - summary: "Elena speaks like someone who learned to hide urgency
    behind composure. Her voice should feel like still water with
    a current underneath."
```

The LLM is instructed to derive traits strictly from what appears in the script. No invention. The `voiceTraits` and `summary` fields become the input to voice design.

### 3. Voice Designer

The CharacterProfile's descriptive fields are composed into a natural language instruction for Qwen3-TTS VoiceDesign:

```
"A controlled female voice in the low-mid register with deliberate
pacing. Late 30s. Slight tension underneath a calm, composed surface.
Precise and economical delivery."
```

This instruction is fed to `generate_voice_design()` which produces a reference audio clip -- a short sample of what this character sounds like.

### 4. Voice Audition

Voice generation has inherent variance. The system generates N candidates (default: 3-5) for each character and presents them for selection. The user listens and picks the one that best fits their mental model of the character.

This is where human judgment enters the pipeline. Everything before this point is automated; everything after uses the locked choice.

### 5. Voice Lock

Once selected, the reference clip is persisted alongside a pre-computed voice clone prompt (speaker embedding). This is the character's "voice ID":

```
VoiceLock
  - characterName: "ELENA"
  - referenceClip: elena_voice_ref.wav (24kHz, ~3-5 seconds)
  - clonePrompt: pre-computed embedding for fast cloning
  - designInstruction: the text that generated this voice
  - lockedAt: timestamp
```

The clone prompt avoids re-extracting speaker features for every line. It is computed once and reused.

### 6. Line Renderer

With locked voices, every line of dialogue is rendered using the Base model's voice cloning:

```
Input:  "We don't have time for this." (ELENA, parenthetical: "cutting him off")
Output: elena_scene12_line3.wav
```

The parenthetical "cutting him off" can optionally inform a brief `instruct` hint to the model, but the voice identity comes entirely from the clone prompt.

## What Stays Out

The Character Studio deliberately does not:

- **Add emotional interpretation beyond what the script provides.** If the writer wrote "(angrily)", that's a signal. If they didn't, the delivery should be neutral/natural for the character's baseline voice.
- **Invent backstory or motivation.** The LLM analyzes what's written, not what might be implied.
- **Override the writer's parentheticals.** If the script says "(whispered)", the render whispers, even if the surrounding context might suggest shouting.
- **Apply "acting" choices.** This is a read, not a performance. The voice is consistent; the emotional range comes from the text itself.

## Voice Persistence

Character voices are stored per-project:

```
~/Library/Caches/intrusive-memory/VoiceStudio/
  └── project-{hash}/
      ├── manifest.json
      ├── elena/
      │   ├── profile.json
      │   ├── voice_ref.wav
      │   ├── clone_prompt.bin
      │   └── candidates/
      │       ├── candidate_001.wav
      │       ├── candidate_002.wav
      │       └── candidate_003.wav
      └── marcus/
          ├── profile.json
          ├── voice_ref.wav
          ├── clone_prompt.bin
          └── candidates/
              └── ...
```

If the script changes and a character's profile shifts significantly, the system can flag the voice lock as potentially stale and offer to re-audition.
