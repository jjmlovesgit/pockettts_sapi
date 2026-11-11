# Milestone 0: source and license audit

Checked 2026-11-05 against official upstream sources.

## Sources and pinned benchmark inputs

- Pocket TTS source: [Kyutai GitHub](https://github.com/kyutai-labs/pocket-tts), MIT code license (`LICENSE`). For the initial benchmark, use PyPI `pocket-tts==4.0.1`, release commit `a922b91`, and the official revision-pinned 2026-10 English configs.
- Model weights: [kyutai/pocket-tts](https://huggingface.co/kyutai/pocket-tts), model card declares CC BY 4.0. Its gated access conditions prohibit unauthorized voice cloning, deceptive use, and other unlawful or harmful uses. This machine's Hugging Face identity authenticated and could read/download the gated model assets on 2026-11-05. The weights used in this benchmark are from revision `db04f0e653473e5c7333c69686ac92b7460b0c1d`.
- Tokenizer: official `kyutai/pocket-tts-without-voice-cloning`, revision `08ffc58775e62aad9409511b9591c9af626270f3`. Only tokenizer files are used from this repository; model weights are not substituted.
- Prompt: [kyutai/tts-voices](https://huggingface.co/kyutai/tts-voices) documents `voice-donations/Butter.wav` as a volunteer donation, licensed CC0. The prompt may be used for cloning tests. We will not redistribute a generated voice or audio sample without checking applicable terms and purpose.
- Existing local prompts in `C:\Projects\pocket-tts-openai_streaming_server\voices-celebrities` have unclear provenance/permissions and are excluded from the benchmark and package.

## Distribution consequence

Updated 2026-11-09: The upstream Pocket TTS source is MIT; the model and tokenizer repositories declare CC BY 4.0; and `voice-donations/Butter.wav` is CC0 1.0. These published licenses permit redistribution subject to their terms. A fork is not required. The installer includes the full MIT, CC BY 4.0, CC0 1.0, and SoundTouch LGPL 2.1 texts, corresponding SoundTouch source, source URLs, pinned model/tokenizer revisions, and changes to the Butter prompt. It identifies this adapter as independent from Kyutai.

Sources: [Pocket TTS MIT license](https://github.com/kyutai-labs/pocket-tts/blob/main/LICENSE), [model card and gated conditions](https://huggingface.co/kyutai/pocket-tts), [tokenizer card](https://huggingface.co/kyutai/pocket-tts-without-voice-cloning), [Butter voice donations](https://huggingface.co/kyutai/tts-voices), [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).

Before a public release, verify the exact accepted Hugging Face gated conditions and produce a license inventory for dependencies embedded in the official Rust runtime and the Windows adapter. The published model card shows use conditions, including a ban on unauthorized voice cloning; it does not show a redistribution ban. The project must show the consent reminder for user-imported prompts and must not imply that a file selection establishes speaker consent.

## Result

**Attribution is packaged; public release review remains open for gated conditions and embedded dependencies.** No training or model modification is part of this milestone.
