# Edge Read Aloud sentence replay cache

On 2026-11-10 the German and Dutch packs had a roughly two-second delay when revisiting an earlier sentence in Edge Read Aloud. The SAPI adapter now keeps the finished PCM for recently spoken exact text in the Edge process. Entries are scoped to the selected voice state and model language, with a 4 MB per-entry and 32 MB total limit. A changed voice-state file invalidates the matching cache key. The first reading still calls the synthesis worker; a repeat uses the stored PCM and the same word-boundary event path.

The updated DLL was installed at `C:\Program Files\PocketTTS\pocket_sapi.dll`, with the prior DLL backed up at `results\pocket_sapi-before-seek-cache.dll`. The installed and built DLLs had matching SHA-256 `AAE0150240E2183C5FDB4442C7FD39152F0F9D0AFBA07BF49635C8119664C181`.

| Installed SAPI voice | First synthesis | Exact replay | WAV comparison |
|---|---:|---:|---|
| Juergen (German) | 744 ms | below 1 ms timer resolution | Identical SHA-256, 228,526 bytes |
| Daan (Dutch) | 794 ms | below 1 ms timer resolution | Identical SHA-256, 266,926 bytes |

The isolated test-token run also passed: German 571 ms first / below 1 ms replay; Dutch 820 ms first / below 1 ms replay. The test registration was removed afterward. Run `scripts/test-seek-cache.ps1` to repeat the isolated check; the installed test WAVs are in `results/installed-seek-*.wav`.

A subsequent isolated SAPI run through the same adapter checked every installed language pack. Each replay produced a byte-identical WAV and completed below the PowerShell stopwatch's 1 ms resolution:

| Language | First synthesis |
|---|---:|
| English | 286 ms |
| French | 826 ms |
| German | 837 ms |
| Italian | 671 ms |
| Spanish | 654 ms |
| Brazilian Portuguese | 600 ms |
| Dutch | 804 ms |

The cache is in the shared SAPI DLL, not in an individual language pack. These are SAPI calls writing to a file; they do not measure audible onset or interruption in NVDA. NVDA is not installed on this test machine. Its arrow-key navigation and cancel/restart behavior remain an acceptance test, particularly because a new sentence cannot use the replay cache and the application may send different fragments for the same visible line.

Edge reopened after the DLL replacement, displayed Juergen in its Read Aloud voice list, and showed word highlighting on the German test page. This is a compatibility check, not a measured Edge audible-onset benchmark. Edge navigation and playback scheduling may still add delay. A sentence is cached only after it has been synthesized fully once; text or voice changes cause a miss.
