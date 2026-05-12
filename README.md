# braindrain

> *A Claude Code status-line plugin that watches your context fill up. The next section explains the idea — Smart Zone vs. Dumb Zone — that the indicator is built on.*

A Claude Code status-line plugin that gives you a single, brutally honest verdict at the bottom of your TUI:

```
SMART  ▓▓▓░░░░░░░  32k / 200k     ← bright green, you're in the Smart Zone
DUMB   ▓▓▓▓▓▓▓▓▓▓  147k / 1M      ← bright red, you've crossed into the Dumb Zone
```

The threshold is **100 000 input tokens**, fixed, regardless of the model's nominal context window. Quality degrades by absolute token count, not by fraction of the window, so a 1M-context model running at 200k is still squarely in the Dumb Zone — and this plugin makes that visceral.

## The idea: Smart Zone vs. Dumb Zone

The framing comes from [**Dex Horthy** (HumanLayer)](https://humanlayer.dev) and his RPI / Ralph-loop methodology for agentic coding. Horthy's observation, paraphrased:

> Coding agents have a **Smart Zone** at the start of a fresh context window and a **Dumb Zone** that begins around 40 % of the window and gets worse from there. The job of context engineering is to keep the agent inside the Smart Zone — by ruthless resets, narrow tasks, and refusing to let context accumulate uncritically.

The Dumb Zone isn't a cliff; it's a slope. Quality degrades smoothly as input grows, but the curve steepens past a point where the model can no longer keep distant facts straight, gets pulled around by distractors, and quietly drops details from the middle of the context. The visible symptom is an agent that *sounds* confident while making junior-engineer mistakes.

This plugin's `SMART` → `DUMB` flip is a coarse, single-bit version of that idea, fixed at 100 000 tokens because that's where the slope starts to bite for most current frontier models regardless of their nominal window size.

References for the concept:

- Dex Horthy — *No Vibes Allowed: Solving Hard Problems in Complex Codebases* (HumanLayer talk). Coverage: <https://bagrounds.org/videos/no-vibes-allowed-solving-hard-problems-in-complex-codebases-dex-horthy-humanlayer>
- Dex Horthy on the *Dev Interrupted* podcast — Ralph loops, RPI, and escaping the Dumb Zone: <https://linearb.io/dev-interrupted/podcast/dex-horthy-humanlayer-rpi-methodology-ralph-loop>
- Companion blog post on the same conversation: <https://linearb.io/blog/dex-horthy-humanlayer-rpi-methodology-ralph-loop>

## The science: Context Rot

If you want a peer-shared, controlled study rather than a podcast clip, the canonical reference is:

> **Hong, K., Troynikov, A., & Huber, J. (2025).** *Context Rot: How Increasing Input Tokens Impacts LLM Performance.* Chroma Research. <https://research.trychroma.com/context-rot>

The Chroma team evaluated **18 state-of-the-art models** — GPT-4.1, Claude 4, Gemini 2.5, Qwen3, and others — across controlled experiments and showed that reliability decreases significantly with longer inputs, **even on simple tasks like retrieval and verbatim text replication**. The degradation is non-uniform and well below the models' advertised context limits. Three compounding mechanisms:

1. **Lost-in-the-middle** — models attend well to the beginning and end of context but poorly to the middle, with 30 %+ accuracy drops on facts buried mid-window.
2. **Attention dilution** — transformer self-attention is quadratic in sequence length; at 100k tokens that's ~10 billion pairwise relationships competing for the model's finite attention budget.
3. **Distractor interference** — semantically similar but irrelevant content actively misleads the model, and the failure mode worsens as input grows.

Replication toolkit and raw data: <https://github.com/chroma-core/context-rot>.

The practical upshot for a coding agent: **the advertised "1M context window" is a hard ceiling, not a working budget.** Useful work happens well below it, and the gap between "fits in context" and "the model actually reasons over it correctly" widens as you fill the window. 100 000 tokens is a reasonable absolute waterline before the Dumb Zone takes hold for current models — *that's* the number this plugin watches.

## What gets shown

`<LABEL>  <10-char bar>  <used> / <window>`

- **LABEL** — `SMART` (green, bold) below the threshold, `DUMB` (red, bold) at/above.
- **Bar** — fills 0–10 blocks as a "headroom-to-100k" gauge: `tokens × 10 / 100 000`, capped at 10/10 once over. The bar shares the label's colour, so the whole row reads as one signal.
- **`used / window`** — current `total_input_tokens` over the model's context window size, formatted as `32k`, `1.4M`, etc.

"Used" comes from `context_window.total_input_tokens` in the status-line JSON, which is the sum of `input_tokens + cache_creation_input_tokens + cache_read_input_tokens`. This matches what Claude Code's own `/context` accounting reports.

## Install

### Option A — via marketplace (recommended once published)

Inside Claude Code:

```
/plugin marketplace add emgiezet/braindrain
/plugin install braindrain@braindrain
```

Then follow step 3 below to wire the `statusLine` config.

### Option B — clone locally

1. Clone the repo somewhere stable:
   ```bash
   git clone git@github.com:emgiezet/braindrain.git ~/.claude/plugins/braindrain
   ```

2. Make the script executable:
   ```bash
   chmod +x ~/.claude/plugins/braindrain/scripts/statusline.sh
   ```

3. Add this block to `~/.claude/settings.json` (merge with any existing top-level keys; don't nest inside other blocks):
   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "/absolute/path/to/braindrain/scripts/statusline.sh",
       "padding": 1
     }
   }
   ```
   Replace the path with wherever you cloned the repo. Tildes don't expand inside this JSON — use a fully resolved absolute path.

4. Accept the workspace-trust prompt the next time Claude Code starts. The status line will appear after the first assistant response.

> **Why the manual `statusLine` step?** Claude Code plugins can only ship `agent` and `subagentStatusLine` defaults in their bundled `settings.json` today — the main `statusLine` field has to live in user settings. If Anthropic relaxes that, this plugin will install in one step with no changes here.

## Requirements

- `jq` on `PATH` (`apt install jq`, `brew install jq`, etc.)
- Claude Code **≥ v2.1.132**. Before that version, `total_input_tokens` was a cumulative session total, not the current context window — the verdict would drift upward over time and never reset after `/compact`.
- A terminal with ANSI colour support (any modern terminal).

## How the SMART → DUMB flip behaves

- `total_input_tokens < 100 000` → SMART (green).
- `total_input_tokens >= 100 000` → DUMB (red). The boundary itself is DUMB, by design — if you're sitting on exactly 100k you've already crossed the line.
- Immediately after `/compact`, `context_window` is briefly `null`. The script falls back to `0 tokens / 200k window` and shows green SMART with an empty bar until the next API response repopulates the numbers. This is correct: a freshly compacted session really is smart again.

## What to do when you see DUMB

The indicator only diagnoses. Mitigations, in rough order of effort:

1. **`/compact`** — cheapest move. Folds the conversation into a summary; the indicator should drop back to green on the next turn.
2. **Hand off to a fresh session** with a brief written down. Horthy's RPI loop (Research → Plan → Implement, each in its own short-lived context) is built on this principle.
3. **Narrow the task.** If you're trying to hold the whole codebase in context, you've already lost — give the agent one file or one function at a time.
4. **Pull out tools and skills.** Persisting reasoning in tool definitions or skill files keeps it out of the rolling conversation context.

## Troubleshooting

- **Status line doesn't appear.** Check `claude --debug` output for the first invocation. Common causes: script not executable, `disableAllHooks: true` in settings, or the workspace-trust prompt wasn't accepted.
- **Shows `braindrain: install jq`.** Install `jq`.
- **Bar looks empty even when DUMB.** You're seeing the `0 tokens` fallback. Wait for the next assistant turn, or check that your Claude Code version reports `context_window.total_input_tokens` as current-context (≥ v2.1.132).
- **Numbers don't match `/context`.** The status line reflects the most recent API response; `/context` reflects the next prepared request. A small drift is normal between turns.

Official status-line troubleshooting: <https://code.claude.com/docs/en/statusline#troubleshooting>

## Credits

- The Smart Zone / Dumb Zone framing is **Dex Horthy's** (HumanLayer). This plugin is a single-bit indicator built on top of his idea — read his work for the full picture.
- The empirical basis is the **Chroma "Context Rot" research** by Hong, Troynikov, and Huber (2025).
- Inspired in spirit by [arpagon/pi-context-zone](https://github.com/arpagon/pi-context-zone), which does the same job for the Pi coding agent.

## License

MIT. See `LICENSE`.
