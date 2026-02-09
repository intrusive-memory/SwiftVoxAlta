# Voice Design Workflow

## From Script to Voice

The central design challenge: how do you turn written text into a voice that sounds like it belongs to the character, without imposing external creative choices?

### The Principle

The voice should be **derived**, not **directed**. The writer already made creative choices about who this character is. Those choices are embedded in:

- The words they use
- How other characters describe them
- What the writer tells us in action/description lines
- The parentheticals the writer chose to include

We extract and synthesize, we do not add.

### What the LLM Does

The character analysis prompt is narrowly scoped:

```
You are analyzing a screenplay character to create a voice description
for text-to-speech synthesis. Use ONLY information present in the
provided script text. Do not invent or assume traits not supported
by the text.

Given the following evidence for the character {NAME}:

DIALOGUE LINES:
{all dialogue}

PARENTHETICAL DIRECTIONS:
{all parentheticals}

ACTION/DESCRIPTION MENTIONING THIS CHARACTER:
{all action lines referencing them}

SCENE CONTEXTS:
{scene headings where they appear}

Produce a JSON object with these fields:
- gender: "male", "female", "nonBinary", or "unspecified"
- ageRange: estimated from textual evidence (e.g., "mid 40s")
- description: 2-3 sentence character summary based on evidence
- voiceTraits: array of 3-6 vocal quality descriptors
  (register, pacing, texture, energy level)
- summary: 1-2 sentence voice description suitable as a TTS instruction
```

The key constraint: **"Use ONLY information present in the provided script text."** If the script doesn't tell us the character is old, we don't assume they're old. If there's no indication of accent, we don't add one.

### What VoiceDesign Receives

The LLM output's `summary` field becomes the `instruct` parameter for Qwen3-TTS VoiceDesign:

```
"A controlled female voice in the low-mid register with deliberate
pacing. Late 30s. Precise and economical delivery with slight tension
underneath a calm surface."
```

Qwen3-TTS VoiceDesign interprets this description and generates a short audio sample embodying those traits.

### Handling Sparse Characters

Not every character has rich textual evidence. A character with three lines and no description lines yields a sparse profile. The system handles this gracefully:

- **Minimal evidence**: If only gender can be inferred, the voice design instruction is generic within that gender. "A male voice with neutral, conversational delivery."
- **No evidence**: Gender defaults to `unspecified`. The instruction is maximally neutral. "A clear, natural speaking voice."
- **Single scene**: Scene context (INT. POLICE STATION, EXT. PLAYGROUND) can inform register and energy even when character description is absent.

The system is transparent about confidence. A sparse profile is flagged so the user knows this voice is largely default rather than script-derived.

## Per-Line Rendering

Once a voice is locked, each line renders with:

- **Voice identity**: From the clone prompt (consistent across all lines)
- **Text**: The dialogue as written
- **Language**: Detected or specified
- **Hint (optional)**: Derived from the parenthetical, if present

### Parenthetical Handling

Parentheticals in screenplays are terse directions:

```
ELENA
(barely audible)
I said no.
```

These map to Qwen3-TTS `instruct` parameter values:

| Parenthetical | TTS Instruction |
|--------------|-----------------|
| (whispering) | "Speak in a whisper" |
| (shouting) | "Speak loudly and forcefully" |
| (barely audible) | "Speak very quietly, almost inaudible" |
| (sarcastic) | "Speak with a sarcastic tone" |
| (to herself) | "Speak quietly, as if talking to oneself" |
| (laughing) | "Speak while laughing lightly" |
| (beat) | [insert pause before line] |
| (cont'd) | [no instruction, continuation] |

Not all parentheticals map to vocal instructions. Some are blocking directions ("turning to face him") that don't affect voice delivery. The system includes a classification step that distinguishes vocal directions from physical/blocking directions.

Parenthetical translation is handled by a simple mapping table for common cases, with an LLM fallback for unusual ones. The LLM fallback is lightweight -- it's classifying a short phrase, not generating content.

### Lines Without Parentheticals

Most lines have no parenthetical. These render with the character's baseline voice and no additional instruction. The vocal character comes entirely from the locked voice identity. This is intentional -- the writer chose not to direct the delivery, so the delivery should be neutral for that character's voice.

## Voice Iteration

### When to Re-Audition

A voice lock can become stale if:

1. **Script revision adds significant new dialogue** that changes the character's profile
2. **Character description changes** in a rewrite
3. **User is unsatisfied** and wants to try again

Staleness detection compares the current CharacterProfile against the one stored with the voice lock. If the `voiceTraits` or `summary` differ beyond a threshold, the system suggests re-audition.

### Re-Audition Without Full Reset

The user can:
- Generate new candidates while keeping the old lock as fallback
- Compare new candidates against the existing locked voice
- Lock a new voice or keep the existing one

The system never silently replaces a locked voice. Voice changes are always user-initiated.

## Batch Workflow

For a full script render:

```
1. Parse script
2. Extract all characters
3. Analyze all characters (can batch LLM calls)
4. For each character with no locked voice:
   a. Generate candidates
   b. Present for audition
   c. Lock selection
5. For each character (parallelizable):
   a. Load clone prompt
   b. Render all lines sequentially
6. Assemble per-character tracks
7. Export
```

Steps 4a-4c are the interactive bottleneck. Everything else is automated. For unattended rendering (all voices already locked), steps 1-3 are fast verification and step 5 is the bulk of the work.
