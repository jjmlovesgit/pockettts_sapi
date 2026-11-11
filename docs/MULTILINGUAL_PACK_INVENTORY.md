# Multilingual pack inventory

Checked 2026-11-10 against Kyutai's official Pocket TTS documentation, model repository, and voice repository. This inventory records the research history. Current implementation status is in [LANGUAGE_PACK_SETUP.md](LANGUAGE_PACK_SETUP.md); the pinned release-candidate asset manifest is `packaging/language-packs.json`.

## Supported languages and initial voice candidates

| Language / Windows tag | Official voice candidates shown in the Pocket TTS demo | Candidate gender coverage | Current model evidence |
|---|---|---|---|
| English / en-US | Jane, Caro Davy, Anna, Azelma, Eponine, Eve, Fantine, Mary, Vera; George, Charles, Michael, Paul, Jean, Bill Boerst, Peter Yearsley, Stuart Bell | Both; largest selection | Current product model: `english_7m_refl_2026-10`, 66.5 MB weights, tokenizer already bundled. |
| French / fr-FR | Estelle (also English voices may clone French prompts/text, test required) | Female shown; male candidate not verified | Official `french` 6-layer model file listed as 219 MB; tokenizer 60.7 KB (model repository listing). |
| German / de-DE | Juergen | Male shown; female candidate not verified | Official `german` 6-layer model: 219,029,196 bytes. Distinct weight file and German tokenizer. |
| Italian / it-IT | Giovanni | Male shown; female candidate not verified | Official `italian` 6-layer config. Exact asset size to confirm. |
| Spanish / es-ES | Lola | Female shown; male candidate not verified | Official `spanish` 6-layer config. Exact asset size to confirm. |
| Portuguese / pt-BR | Rafael | Male shown; female candidate not verified | Official `portuguese` 6-layer config. Exact asset size to confirm. |
| Dutch / nl-NL | Daan | Male shown; female candidate not verified | Official `dutch` 6-layer config. Exact asset size to confirm. |

Demo voice names and gender/style labels were supplied by the user screenshot. Official CLI docs identify the locale-specific defaults: Estelle, Juergen, Giovanni, Lola, Rafael, and Daan, with Alba as English default. The demo screenshot also shows broader English donation voices.

## Voice licensing and sources

- Kyutai's `voice-donations/` directory is described as CC0, 228 verified volunteer donations. It contains gender-neutral filenames, so an individual voice's presentation must be auditioned; file IDs should not be guessed from display names.
- `voice-zero/` contains Bill Boerst, Caro Davy, Peter Yearsley, and Stuart Bell and is described as CC0. This is useful for the larger English choice.
- Other directories use separate licenses; exclude them unless reviewed individually. In particular, the repository marks Expresso and EARS as CC BY-NC 4.0.
- Official multilingual Pocket TTS voice states are model/language-specific. Generate or obtain each chosen voice state against the matching language config; do not reuse the current English `.safetensors` state as if it were language-neutral.

## Enhanced prompt files checked 2026-11-10

The official `tts-voices` repository contains `_enhanced.wav` prompt variants in two folders relevant to selection:

- `voice-donations/`: 228 enhanced WAVs, each 640,044 bytes (about 0.61 MiB); the folder is identified as CC0 volunteer donations. Candidate filenames include `Andrea_(Spanish)_enhanced.wav` and `Alejandro_espanol_latino_enhanced.wav`, which may help Spanish voice coverage. Gender and native-language suitability should be confirmed by listening and repository metadata before selection.
- `vctk/`: 106 enhanced WAVs, approximately 0.55–0.90 MB each; the collection is CC BY 4.0. VCTK speaker IDs require its speaker metadata to map gender/accent; retain attribution per CC BY.
- No `_enhanced.wav` files were listed at the top level of `alba-mackenna/`, `cml-tts/`, `ears/`, `expresso/`, `unmute-prod-website/`, or `voice-zero/` in the current repository tree.

The non-English demo presets are explicitly listed as Daan (Dutch, male), Estelle (French, female), Giovanni (Italian, male), Juergen (German, male), Lola (Spanish, female), and Rafael (Brazilian Portuguese, male). The English voice set is larger. These built-in demo names are useful initial candidates; this inventory does not yet resolve all names to prompt files or establish both genders for every locale. The CC0 donation folder provides additional named prompts that may fill gaps, subject to audition and mapping.

## Installer sizing and design implications

- The six non-English standard models use the official 6-layer configs; the 24-layer variants are larger preview models and are out of initial scope.
- Each of the six non-English standard language folders lists a separate 219,029,196-byte model asset. Plan a model download for every selected language pack.
- Language pack download should install the matching native model, tokenizer/config, and demo voice state. Setup shows estimated download size. A failed download can be retried by rerunning Setup; within-file HTTP resume is not implemented.
- English stays on the selected 6.9M ReFL model. The six non-English model assets total about 1.31 GB before tokenizers and voice states.

## Official references

- [Pocket TTS supported language configs](https://github.com/kyutai-labs/pocket-tts/blob/main/docs/API%20Reference/python-api.md)
- [Official Pocket TTS model files](https://huggingface.co/kyutai/pocket-tts/tree/main/languages)
- [Official voice catalog and license notes](https://huggingface.co/kyutai/tts-voices)
- [Voice donations](https://huggingface.co/kyutai/tts-voices/tree/main/voice-donations)
- [Voice-Zero samples](https://huggingface.co/kyutai/tts-voices/tree/main/voice-zero)

## Next verification work

1. Pin one immutable model and voice repository revision.
2. Compare model file hashes across all six 6-layer language paths; record exact model and tokenizer sizes.
3. Resolve the demo display names to exact source recordings and verify license metadata for each.
4. Export one female and one male candidate per language where available, then audition them with native language text and SAPI.
5. Confirm runtime behavior switching languages and installed packs before implementing optional language checkboxes in Setup.

## English model + German tokenizer experiment (2026-11-10)

Used the user's exact text: `Freut mich! Es freut mich, dich kennenzulernen. Nice to meet you!` and Juergen.

| Run | Model | Tokenizer | Juergen state | Generated duration / generation time |
|---|---|---|---|---|
| A | English `english_7m_refl_2026-10` (66,482,920 B) | German `languages/german/tokenizer.json` (245,966 B) | English-model Juergen state (1,018,256 B) | 7.12 s / 262 ms |
| B | Native `german` six-layer model (219,029,196 B) | German tokenizer JSON | German Juergen state (6,096,696 B) | 3.68 s / 395 ms |

Both generated successfully in the official Rust CLI. Run A used the English model config with only tokenizer backend/path changed from SentencePiece to the German tokenizer JSON, and used the English model's Juergen voice state. This demonstrates technical compatibility, but does not establish German pronunciation quality. The audio files are `results/juergen-english-model-german-tokenizer.wav` and `results/juergen-german-native.wav`; user listening evaluation is needed. The large duration difference also suggests the outputs may differ in tokenization or stopping behavior.

User listening result: the native German model + German tokenizer output is clearly better. Treat the language-specific model as required for German in the product. The tokenizer-only English-model configuration is not acceptable for German, even though it can generate audio. Apply native per-language models as the planning assumption for other locales, with one listening check per locale before release.

## Other native-language samples generated (2026-11-10)

Generated one short sample per remaining language using the CLI's native language config and locale default demo voice. First-use asset loading succeeded for every language. This confirms the current runtime can load and generate all six non-English language packs offline after the initial download; audio quality still needs the user's listening review.

| Language | Voice | Test sentence | Generated duration | File |
|---|---|---|---:|---|
| French | Estelle | `Bonjour ! Ravi de faire votre connaissance.` | 2.48 s | `results/estelle-french-native.wav` |
| Italian | Giovanni | `Buongiorno! Piacere di conoscerti.` | 3.12 s | `results/giovanni-italian-native.wav` |
| Spanish | Lola | `¡Buenos días! Mucho gusto en conocerte.` | 3.68 s | `results/lola-spanish-native.wav` |
| Brazilian Portuguese | Rafael | `Bom dia! Prazer em conhecer você.` | 2.72 s | `results/rafael-portuguese-native.wav` |
| Dutch | Daan | `Goedemorgen! Leuk je te ontmoeten.` | 2.48 s | `results/daan-dutch-native.wav` |

Rust CLI generation logs are in `results/multilingual-sample-generation.log` when run through the maintained benchmark command; these five outputs were generated interactively during the inventory step. Each generation took about 0.27–0.40 seconds after the model was loaded.

## Installer and runtime design decision

- Setup should offer independent optional checkboxes for French, German, Italian, Spanish, Brazilian Portuguese, and Dutch. English 6.9M remains part of the base install. Display the approximate download size before starting.
- Each checked pack downloads that language's pinned native model, matching tokenizer, default demo voice state, and attribution metadata. The demo's English voices remain an optional expanded English selection.
- The installer downloads all checked packs first, verifies their pinned hashes and complete files, then installs the selected packs and registers their SAPI/OneCore tokens. A failed pack download must stop installation cleanly or allow retry without leaving a partially registered pack.
- The SAPI engine now reads `ModelLanguage` and the voice state from each token and switches the single shared worker as needed. Do not start a resident worker for every installed model, since six model weights are about 1.31 GB on disk and concurrent worker memory would be much larger.
- User accepts a delay when changing to a different language/model. Keep one shared worker: on the first request after a language change, switch/restart it with the selected language model, load that model once, and retain it warm for subsequent requests in that language. Same-language sentences and cursor navigation must not reload the model. Do not keep all language models resident at once.

### Large preset voice states

The official server's multipart endpoint has a 2 MiB request limit; native locale voice states are 3.9–7.6 MB. On 2026-11-10 a German worker launched with Juergen's language-specific state as `--default-voice` generated a 136,364-byte WAV from a plain form text request without uploading the state. The SAPI engine now selects the token's `ModelLanguage` and state path when starting a worker, records the loaded language and voice in the current user's registry, reuses the worker for the same pair, and posts text alone to the worker. Switching either the language or selected voice state restarts the worker once. This includes a change of rate variant where rate selects a different voice state; warm same-variant sentences reuse the worker.

An isolated SAPI COM probe passed without modifying the installed DLL: English generated 213,166 bytes (625 ms, worker PID 31596); the first German request generated 136,366 bytes (514 ms, PID 8880); a second German sentence generated 144,046 bytes (326 ms, same PID 8880). Both German utterances used Juergen's 6 MB state preloaded by the worker. The probe removed its temporary per-user tokens/COM registration and stopped the worker. See `results/german-switch-local-result.txt` and `scripts/probe-german-sapi-switch-local.ps1`. This verifies one language switch and warm reuse through SAPI; it does not yet verify installed machine tokens, Edge, NVDA, all locales, or repeated cross-language/rate changes.
- Uninstall removes installed packs and their tokens; later add/remove pack management should use the same verified downloader and token lifecycle as Setup.

### Gates before shipping multilingual Setup

1. **Passed 2026-11-10:** user approved the French, Italian, Spanish, Brazilian Portuguese, and Dutch samples. The earlier Juergen German sample was also approved as clearly better with the native German model.
2. Pin immutable model, tokenizer, and voice-state files and verify hashes; replace all `main` refs in the manifest.
3. Implement language-aware tokens and safe single-worker model switching, with a loaded-language marker so same-language requests reuse the warm worker.
4. Test each locale in SAPI, Edge Read Aloud, and NVDA where available; test expected first-switch delay, warm same-language requests, rapid interruption, offline restart, upgrade, and uninstall.
5. Build installer checkboxes/downloader only after runtime selection is reliable; then test resume, hash mismatch, unavailable network, and partial install cleanup.

## Demo voice asset mapping and current sizes (2026-11-10)

The Pocket TTS model repository includes ready-to-use, model-specific `.safetensors` voice states, so base install does not need to ship the source WAV for each built-in voice. Display names normalize directly to asset IDs in the English 6.9M and multilingual embeddings folders:

| Demo display | Locale | Asset ID | English 6.9M state | Native language state |
|---|---|---|---:|---:|
| Alba | English | `alba` | 1,042,832 B | English |
| Anna | English | `anna` | 1,272,208 B | English |
| Azelma | English | `azelma` | 1,198,480 B | English |
| Bill Boerst | English | `bill_boerst` | 1,091,984 B | English |
| Caro Davy | English | `caro_davy` | 846,224 B | English |
| Charles | English | `charles` | 1,034,640 B | English |
| Eponine | English | `eponine` | 1,157,520 B | English |
| Eve | English | `eve` | 1,026,448 B | English |
| Fantine | English | `fantine` | 1,075,600 B | English |
| George | English | `george` | 985,488 B | English |
| Jane | English | `jane` | 1,223,056 B | English |
| Mary | English | `mary` | 993,680 B | English |
| Michael | English | `michael` | 1,190,288 B | English |
| Paul | English | `paul` | 1,141,136 B | English |
| Peter Yearsley | English | `peter_yearsley` | 608,640 B | English |
| Stuart Bell | English | `stuart_bell` | 846,224 B | English |
| Vera | English | `vera` | 1,116,560 B | English |
| Daan | Dutch | `daan` | not same English model | language-specific |
| Estelle | French | `estelle` | not same English model | 7,571,256 B |
| Giovanni | Italian | `giovanni` | not same English model | language-specific |
| Juergen | German | `juergen` | not same English model | language-specific |
| Lola | Spanish | `lola` | not same English model | language-specific |
| Rafael | Brazilian Portuguese | `rafael` | not same English model | language-specific |

Repository file list also shows English voice states for non-English names as cross-language voices; these are distinct from each native language state. For French, all 24 demo voices have precomputed French states, typically 3.6–7.6 MB each. A pack should include only the demo's native locale voice by default, and the larger English choice set only in the English pack.

`voice-zero/` maps the four English demo names to original prompt files exactly: `bill_boerst.wav` 955,496 B, `caro_davy.wav` 743,528 B, `peter_yearsley.wav` 524,448 B, `stuart_bell.wav` 745,776 B. Kyutai identifies this collection as CC0. The per-language preset prompts and voice states are in [Kyutai's pocket-tts model repository](https://huggingface.co/kyutai/pocket-tts/tree/main/languages), and the displayed English voices are found under its `embeddings/` directories. Model asset listings show the six multilingual model files are each 219,029,196 B but have different Git object IDs; treat them as separate until SHA-256 confirms byte identity. The English 6.9M model is 66.5 MB.

Important: the retrieved file IDs and sizes are from the current `main` tree, not yet locked to immutable commits. Pin exact revisions and compare SHA-256 before implementation. The provided browser list's style labels and gender labels remain the source for presentation; do not infer gender from asset IDs.
