# AI character voices - free options (research, 2026-10-07)

Research only. No game code, nothing installed. Goal: voices for the
late-night pirate-radio DJ and story characters that can sound tired, angry,
sarcastic, scared or laughing, cost nothing, and are safe to ship in a
commercially released game.

## The short answer

1. **Qwen3-TTS (Apache-2.0)** to *design* each character's voice from a
   written description and act lines from plain-language instructions
   ("tired, half-whispering, 3 a.m. radio"). Best emotion control of anything
   with a clean commercial licence. Slow on a laptop CPU, but lines are baked
   offline, so slow is fine.
2. **Chatterbox Turbo / Nano (MIT)** to bake lots of lines locally on CPU,
   cloning the voices designed in step 1, with `[laugh]`, `[sigh]`,
   `[chuckle]` tags and an "exaggeration" dial for intensity.

Everything else is either non-commercial, needs an NVIDIA GPU, or has no real
emotion control. Details below.

## Key facts about the laptop

- **Iris Xe cannot accelerate these models.** PyTorch's Intel GPU (XPU)
  backend on Windows supports Arc and Core Ultra "Arc Graphics" only; Iris Xe
  in 11th-13th gen chips is not supported. Plan on **CPU only**.
- That is acceptable because game dialogue is **pre-rendered**: we generate
  WAV files once, review them, and ship the WAVs. No model ships in the game,
  and the game needs no AI at runtime.
- Speed figures below are from the projects' own pages or third-party tests
  on other machines. They are rough. Expect a 4-core laptop to be slower.

## Comparison

"Commercial OK" means the licence allows using generated audio in a game we
sell. NC = non-commercial, do not use.

| Option | Emotion control | Voice design / cloning | Quality | Commercial licence | Runs on this laptop? | Install effort |
|---|---|---|---|---|---|---|
| **Qwen3-TTS** (0.6B / 1.7B, Alibaba) | Natural-language instructions ("speak angrily", "sarcastic, bored") plus tone inferred from the text | **VoiceDesign** model makes a new voice from a text description; Base model clones from ~3 s of audio | Very good, among the most expressive open models | **Yes - Apache-2.0** | CPU only. 0.6B int8 measured ~3x slower than real time on 4 vCPU; 1.7B (needed for VoiceDesign) slower still. Fine for overnight baking | Medium: `pip install -U qwen-tts`, Python env. Free HF Space demo needs no install |
| **Chatterbox Turbo** (350M, Resemble AI) | `[laugh]`, `[chuckle]`, `[cough]`, `[sigh]` tags; `exaggeration` dial | Zero-shot cloning from a short clip; no text-based design | Very good, natural | **Yes - MIT**. Adds an inaudible watermark to output | CPU works but slower than real time (estimate) | Low-medium: `pip install chatterbox-tts`, Python 3.11 |
| **Chatterbox Nano** (110M, Resemble AI) | Same tags as Turbo | Cloning from ~5 s clip | Good; a step below Turbo | **Yes - MIT** | **Yes.** ~3x faster than real time on 8 CPU cores (vendor figure) | Low: same package |
| **Kokoro-82M** | None. Fixed neutral read | 54 preset voices, no cloning | Clean and clear, but flat | **Yes - Apache-2.0** | **Yes, fast** on CPU | Low: `pip install kokoro` + espeak-ng installer |
| **Pocket TTS** (100M, Kyutai) | None documented; only what the reference clip carries | Cloning from one clip | Good for size | **Yes - CC-BY-4.0** (credit Kyutai). Gated; bans impersonation | **Yes.** ~6x real time on 2 cores of an M4 | Low: `pip install pocket-tts` |
| **Orpheus 3B** (Canopy Labs) | Tags like `<laugh>`, `<sigh>`, `<groan>` | Preset voices; cloning | Very good | Apache-2.0 card, **but built on Llama 3.2**, so the Llama licence likely also applies (attribution, terms). Check before use | CPU very slow at 3B; GGUF/llama.cpp ports help | Medium-high |
| **Dia 1.6B** (Nari Labs) | `(laughs)`, `(sighs)`, `(gasps)` etc. Two-speaker dialogue | Cloning via audio prompt | Very good for banter | **Yes - Apache-2.0** | **No.** GPU only, ~10 GB VRAM | n/a |
| **Zonos v0.1** (Zyphra) | Sliders: happiness, anger, sadness, fear; pitch, rate | Cloning from 10-30 s | Good | **Yes - Apache-2.0** | **No.** NVIDIA GPU, 6 GB+ | n/a |
| **IndexTTS-2** (bilibili) | Best-in-class: emotion reference clip, 8 emotion sliders, or text | Cloning | Excellent | **Not by default** - bilibili licence; commercial use needs written permission | GPU-oriented | n/a |
| **F5-TTS** | Only via reference clip | Cloning | Good | **NC - CC-BY-NC-4.0** weights | - | - |
| **XTTS-v2** (Coqui) | Only via reference clip | Cloning | Good | **NC - Coqui Public Model License** (company closed; no way to buy a licence) | - | - |
| **Fish Audio OpenAudio S1-mini** | Rich tags: (angry), (sad), (laughing), (whispering)... | Cloning | Very good | **NC - CC-BY-NC-SA-4.0** | - | - |
| **Google Gemini TTS** (hosted, free tier) | Style prompts plus inline tags like `<laugh>`, `<pause>` | 30 studio voices plus a large library; voice replication | Excellent | Google claims no ownership of output. **But:** free tier content is used to improve Google products, and free tier may not be used for apps offered to users in the **UK/EEA/Switzerland**. Read terms for Roy's country before relying on it | Cloud | Low: API key from AI Studio |
| **ElevenLabs** (hosted, free) | v3 audio tags, very expressive | Design + cloning | Excellent | **NC on free plan.** Commercial licence starts with the paid Starter plan | Cloud | Low |
| **Hume Octave** (hosted, free) | Understands emotional intent; voice design by description | Design + cloning | Excellent | **NC on Free and Starter tiers.** Also: Hume's TTS API is **being discontinued on 2026-11-13** | Cloud | Low |

## Recommendation and how to try it in an afternoon

**Pick 1 - Qwen3-TTS VoiceDesign, then Chatterbox for bulk.**

Afternoon plan (no install for the first half):

1. **Hour 1 - design voices in the browser.** Open the official Qwen3-TTS
   Hugging Face Space (link below). Write a description for the DJ, e.g.
   "gravelly male voice, late 30s, tired, dry and sarcastic, close to the
   microphone". Generate 3-4 test lines in different moods (bored, laughing,
   scared). Keep the best take of each character as a 10-15 s reference WAV.
   Free Spaces run on a shared GPU quota, so expect queues and daily limits.
2. **Hour 2 - judge acting.** Same lines, change only the instruction
   ("angrier", "laughing through it", "whispering, scared"). Note which
   emotions land and which sound fake.
3. **Hours 3-4 - local bake test (only if Roy approves installing Python
   packages).** In a fresh Python 3.11 virtual environment,
   `pip install chatterbox-tts`, load Nano or Turbo with `device="cpu"`, feed
   it the reference WAV from step 1, and render ten lines with `[laugh]` /
   `[sigh]` tags and a couple of `exaggeration` values. Time it to see real
   CPU speed on this laptop.

**Pick 2 (fallback for a narrator who does not need to act) - Kokoro.**
Fast and permissive, but flat. Useful for placeholder lines only.

## Risks and rules

- **Voices must be original.** Clone only voices we designed (Qwen3
  VoiceDesign output) or a real person who has given written consent. Never
  clone a celebrity, a real radio DJ, an actor or a character from another
  game, even "as a sound-alike". This is a legal risk (right of publicity,
  unfair competition) and against the use policies of Pocket TTS, Gemini and
  others.
- **Licence of the model, not just the code.** Several projects (F5-TTS,
  Fish) have MIT/Apache code but NC weights. Always read the model card.
  Keep a copy of the licence and the model version used for each voice in
  the repo when we start baking.
- **Store disclosure.** Steam's Content Survey asks developers to disclose
  pre-generated AI content, including sound, and shows it on the store page.
- **Free hosted tiers are fragile.** Terms change and services close (Hume's
  TTS API ends 2026-11-13). Local Apache/MIT models stay usable forever once
  downloaded.
- **Watermark.** Chatterbox output carries Resemble's inaudible watermark.
  Not a licence issue, just worth knowing.
- **Consistency.** Emotion-heavy models vary from take to take. Budget time
  to re-roll and pick takes, as with a human actor.

## Sources

- Qwen3-TTS repo (licence, model variants): https://github.com/QwenLM/Qwen3-TTS
- Qwen3-TTS VoiceDesign model card: https://huggingface.co/Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign
- Qwen3-TTS Space demo: https://huggingface.co/spaces/Qwen/Qwen3-TTS
- Qwen3-TTS CPU timing (third party): https://github.com/gabriele-mastrapasqua/qwen3-tts
- Chatterbox repo: https://github.com/resemble-ai/chatterbox
- Chatterbox model card: https://huggingface.co/ResembleAI/chatterbox
- Chatterbox Turbo: https://huggingface.co/ResembleAI/chatterbox-turbo
- Chatterbox Nano: https://huggingface.co/ResembleAI/chatterbox-nano
- Kokoro-82M: https://huggingface.co/hexgrad/Kokoro-82M and https://github.com/hexgrad/kokoro
- Pocket TTS: https://huggingface.co/kyutai/pocket-tts
- Orpheus 3B: https://huggingface.co/canopylabs/orpheus-3b-0.1-ft
- Dia 1.6B: https://huggingface.co/nari-labs/Dia-1.6B
- Zonos: https://huggingface.co/Zyphra/Zonos-v0.1-transformer
- IndexTTS: https://github.com/index-tts/index-tts
- F5-TTS: https://huggingface.co/SWivid/F5-TTS
- XTTS-v2 licence: https://huggingface.co/coqui/XTTS-v2/blob/main/LICENSE.txt
- OpenAudio S1-mini: https://huggingface.co/fishaudio/openaudio-s1-mini
- Gemini TTS docs: https://ai.google.dev/gemini-api/docs/speech-generation
- Gemini pricing (free tier, data use): https://ai.google.dev/gemini-api/docs/pricing
- Gemini API terms (UK/EEA/CH rule, output ownership): https://ai.google.dev/gemini-api/terms
- ElevenLabs pricing: https://elevenlabs.io/pricing
- Hume TTS overview (sunset notice): https://dev.hume.ai/docs/text-to-speech-tts/overview
- Hume pricing: https://www.hume.ai/pricing
- PyTorch Intel GPU support: https://docs.pytorch.org/docs/stable/notes/get_start_xpu.html
- Steam Content Survey (AI disclosure): https://partner.steamgames.com/doc/gettingstarted/contentsurvey
