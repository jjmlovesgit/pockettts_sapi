#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <sapi.h>
#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

static double percentile(std::vector<double> values, double p) {
    if (values.empty()) return 0;
    std::sort(values.begin(), values.end());
    size_t i = static_cast<size_t>((values.size() - 1) * p + 0.5);
    return values[i];
}

static ISpStream* openCapture(const std::wstring& path) {
    ISpStream* stream = nullptr;
    HRESULT hr = CoCreateInstance(CLSID_SpStream, nullptr, CLSCTX_INPROC_SERVER,
                                  IID_ISpStream, reinterpret_cast<void**>(&stream));
    if (FAILED(hr)) return nullptr;
    WAVEFORMATEX format{};
    format.wFormatTag = WAVE_FORMAT_PCM; format.nChannels = 1; format.nSamplesPerSec = 24000;
    format.wBitsPerSample = 16; format.nBlockAlign = 2; format.nAvgBytesPerSec = 48000;
    hr = stream->BindToFile(path.c_str(), SPFM_CREATE_ALWAYS, &SPDFID_WaveFormatEx, &format, 0);
    if (FAILED(hr)) { stream->Release(); return nullptr; }
    return stream;
}

static double captureDurationMs(const std::wstring& path) {
    std::ifstream file(path, std::ios::binary);
    std::vector<unsigned char> bytes((std::istreambuf_iterator<char>(file)), {});
    if (bytes.size() < 44 || memcmp(bytes.data(), "RIFF", 4) || memcmp(bytes.data() + 8, "WAVE", 4)) return -1;
    for (size_t p = 12; p + 8 <= bytes.size();) {
        uint32_t size = uint32_t(bytes[p+4]) | (uint32_t(bytes[p+5]) << 8) |
                        (uint32_t(bytes[p+6]) << 16) | (uint32_t(bytes[p+7]) << 24);
        size_t data = p + 8;
        if (!memcmp(bytes.data() + p, "data", 4) && data + size <= bytes.size())
            return 1000.0 * size / 48000.0;
        p = data + size + (size & 1);
    }
    return -1;
}

static int runRate(ISpVoice* voice, const std::wstring& outputDir) {
    if (!CreateDirectoryW(outputDir.c_str(), nullptr) && GetLastError() != ERROR_ALREADY_EXISTS) {
        std::printf("rate_capture_error=0x%08lx\n", static_cast<unsigned long>(GetLastError()));
        return 20;
    }
    struct RateCase { long value; const wchar_t* name; };
    const RateCase cases[] = {{-5, L"slow"}, {0, L"normal"}, {5, L"fast"}};
    double durations[3]{};
    const wchar_t* text = L"Pocket TTS rate test. The same cloned voice should speak this sentence at each selected rate.";
    for (size_t i = 0; i < std::size(cases); ++i) {
        std::vector<double> samples;
        for (int trial = 1; trial <= 3; ++trial) {
            std::wstring path = outputDir + L"\\rate_" + cases[i].name + L"_" + std::to_wstring(trial) + L".wav";
            ISpStream* stream = openCapture(path);
            if (!stream) return 21;
            HRESULT hr = voice->SetRate(cases[i].value);
            if (SUCCEEDED(hr)) hr = voice->SetOutput(stream, TRUE);
            if (SUCCEEDED(hr)) hr = voice->Speak(text, SPF_DEFAULT, nullptr);
            voice->SetOutput(nullptr, TRUE);
            stream->Close();
            stream->Release();
            if (FAILED(hr)) {
                std::printf("rate_error value=%ld hr=0x%08lx\n", cases[i].value, static_cast<unsigned long>(hr));
                return 22;
            }
            double duration = captureDurationMs(path);
            if (duration <= 0) return 23;
            samples.push_back(duration);
            std::printf("rate_capture name=%ls sapi_rate=%ld trial=%d duration_ms=%.1f file=%ls\n",
                        cases[i].name, cases[i].value, trial, duration, path.c_str());
        }
        durations[i] = percentile(samples, .50);
        std::printf("rate_median name=%ls sapi_rate=%ld duration_ms=%.1f\n",
                    cases[i].name, cases[i].value, durations[i]);
    }
    if (durations[0] < durations[1] * 1.20 || durations[2] > durations[1] * 0.83) {
        std::printf("rate_check_failed slow=%.1f normal=%.1f fast=%.1f\n",
                    durations[0], durations[1], durations[2]);
        return 24;
    }
    std::printf("rate_check_passed slow_over_normal=%.2f fast_over_normal=%.2f\n",
                durations[0] / durations[1], durations[2] / durations[1]);
    const RateCase fragmentRates[] = {{-5, L"slow"}, {5, L"fast"}};
    const std::wstring tracePath = outputDir + L"\\rate_fragment_trace.txt";
    DeleteFileW(tracePath.c_str());
    SetEnvironmentVariableW(L"POCKETTTS_SAPI_FRAGMENT_TRACE", tracePath.c_str());
    for (const auto& item : fragmentRates) {
        const std::wstring path = outputDir + L"\\rate_xml_" + item.name + L".wav";
        const std::wstring xml = L"<speak><rate absspeed=\"" +
            std::to_wstring(item.value) + L"\">Pocket TTS rate test. The same cloned voice should speak this sentence at each selected rate.</rate></speak>";
        ISpStream* stream = openCapture(path);
        if (!stream) return 25;
        HRESULT hr = voice->SetRate(0);
        if (SUCCEEDED(hr)) hr = voice->SetOutput(stream, TRUE);
        if (SUCCEEDED(hr)) hr = voice->Speak(xml.c_str(), SPF_IS_XML, nullptr);
        voice->SetOutput(nullptr, TRUE);
        stream->Close();
        stream->Release();
        if (FAILED(hr)) {
            std::printf("rate_xml_error value=%ld hr=0x%08lx\n", item.value, static_cast<unsigned long>(hr));
            return 26;
        }
        const double duration = captureDurationMs(path);
        std::printf("rate_xml name=%ls fragment_rate=%ld duration_ms=%.1f file=%ls\n",
                    item.name, item.value, duration, path.c_str());
        if ((item.value < 0 && duration < durations[1] * 1.15) ||
            (item.value > 0 && duration > durations[1] * 0.87)) return 27;
    }
    SetEnvironmentVariableW(L"POCKETTTS_SAPI_FRAGMENT_TRACE", nullptr);
    std::wprintf(L"rate_fragment_trace=%ls\n", tracePath.c_str());
    std::printf("rate_fragment_check_passed\n");
    return 0;
}

static HRESULT measureFirstAudio(ISpVoice* voice, const std::wstring& text, double& ms, DWORD flags = SPF_ASYNC) {
    static unsigned sequence = 0;
    std::wstring name = L"Local\\PocketTTSFirstAudio_" + std::to_wstring(GetCurrentProcessId()) +
                        L"_" + std::to_wstring(++sequence);
    HANDLE event = CreateEventW(nullptr, TRUE, FALSE, name.c_str());
    if (!event) return HRESULT_FROM_WIN32(GetLastError());
    if (!SetEnvironmentVariableW(L"POCKETTTS_SAPI_FIRST_AUDIO_EVENT", name.c_str())) {
        HRESULT hr = HRESULT_FROM_WIN32(GetLastError()); CloseHandle(event); return hr;
    }
    auto start = std::chrono::steady_clock::now();
    HRESULT hr = voice->Speak(text.c_str(), flags, nullptr);
    if (SUCCEEDED(hr)) {
        DWORD wait = WaitForSingleObject(event, 10000);
        if (wait != WAIT_OBJECT_0) hr = wait == WAIT_TIMEOUT ? HRESULT_FROM_WIN32(ERROR_TIMEOUT)
                                                           : HRESULT_FROM_WIN32(GetLastError());
        else ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count();
    }
    if (SUCCEEDED(hr)) hr = voice->WaitUntilDone(30000);
    SetEnvironmentVariableW(L"POCKETTTS_SAPI_FIRST_AUDIO_EVENT", nullptr);
    CloseHandle(event);
    return hr;
}

static int runLatency(ISpVoice* voice, const std::wstring& outputDir, long rate) {
    HRESULT rateHr = voice->SetRate(rate);
    if (FAILED(rateHr)) return 6;
    std::printf("latency_sapi_rate=%ld\n", rate);
    HRESULT notifyHr = voice->SetNotifyWin32Event();
    if (FAILED(notifyHr)) { std::printf("notify_error=0x%08lx\n", static_cast<unsigned long>(notifyHr)); return 7; }
    if (!CreateDirectoryW(outputDir.c_str(), nullptr) && GetLastError() != ERROR_ALREADY_EXISTS) {
        std::printf("capture_error=0x%08lx\n", static_cast<unsigned long>(GetLastError())); return 8;
    }
    const std::pair<const wchar_t*, const wchar_t*> cases[] = {
        {L"letter_Z", L"Z"}, {L"letter_a", L"a"}, {L"word_yes", L"yes"}, {L"word_next", L"next"}
    };
    for (const auto& item : cases) {
        std::vector<double> samples;
        for (int i = 0; i < 20; ++i) {
            std::wstring warmPath = outputDir + L"\\warm.wav";
            ISpStream* warmStream = openCapture(warmPath);
            if (!warmStream || FAILED(voice->SetOutput(warmStream, TRUE))) { if(warmStream) warmStream->Release(); return 9; }
            double ms = 0; HRESULT hr = measureFirstAudio(voice, item.second, ms);
            warmStream->Close(); voice->SetOutput(nullptr, TRUE); warmStream->Release();
            if (FAILED(hr)) { std::printf("latency_error case=%ls iteration=%d hr=0x%08lx\n", item.first, i, static_cast<unsigned long>(hr)); return 10; }
            samples.push_back(ms);
        }
        std::printf("warm case=%ls n=%zu median_ms=%.1f p95_ms=%.1f max_ms=%.1f\n", item.first,
                    samples.size(), percentile(samples, .50), percentile(samples, .95), *std::max_element(samples.begin(), samples.end()));
    }
    std::wstring longText;
    for (int i = 0; i < 12; ++i)
        longText += L"OLD content that should be canceled before it reaches the listener. ";
    double baselineZ = 0, baselineNext = 0;
    for (const auto& item : {std::pair<const wchar_t*, const wchar_t*>{L"Z",L"Z"}, {L"next",L"next"}}) {
        std::wstring path = outputDir + L"\\reference_" + item.first + L".wav";
        ISpStream* stream = openCapture(path);
        if (!stream || FAILED(voice->SetOutput(stream, TRUE))) { if(stream) stream->Release(); return 13; }
        double firstMs = 0; HRESULT hr = measureFirstAudio(voice, item.second, firstMs);
        stream->Close(); voice->SetOutput(nullptr, TRUE); stream->Release();
        if (FAILED(hr)) return 14;
        double duration = captureDurationMs(path);
        if (duration < 0) { std::printf("capture_parse_error=%ls\n", path.c_str()); return 15; }
        if (item.first[0] == L'Z') baselineZ = duration; else baselineNext = duration;
        std::printf("capture_reference text=%ls duration_ms=%.1f file=%ls\n",
                    item.first, duration, path.c_str());
    }
    std::vector<double> rapid;
    unsigned staleDuration = 0;
    for (int i = 0; i < 20; ++i) {
        const wchar_t* nextText = i % 2 ? L"Z" : L"next";
        std::wstring path = outputDir + L"\\rapid_" + std::to_wstring(i + 1) + L".wav";
        ISpStream* stream = openCapture(path);
        if (!stream || FAILED(voice->SetOutput(stream, TRUE))) { if(stream) stream->Release(); return 16; }
        HRESULT hr = voice->Speak(longText.c_str(), SPF_ASYNC, nullptr);
        if (FAILED(hr)) { stream->Close(); stream->Release(); return 11; }
        Sleep(5);
        double ms = 0;
        hr = measureFirstAudio(voice, nextText, ms,
                               SPF_ASYNC | SPF_PURGEBEFORESPEAK);
        stream->Close(); voice->SetOutput(nullptr, TRUE); stream->Release();
        if (FAILED(hr)) { std::printf("rapid_error iteration=%d hr=0x%08lx\n", i, static_cast<unsigned long>(hr)); return 12; }
        rapid.push_back(ms);
        double duration = captureDurationMs(path);
        double baseline = nextText[0] == L'Z' ? baselineZ : baselineNext;
        if (duration < 0) { std::printf("capture_parse_error=%ls\n", path.c_str()); return 17; }
        // Pocket TTS can vary a one-word response by several hundred ms between
        // requests. A canceled multi-sentence utterance would add seconds.
        bool extraAudio = duration > baseline + 1000.0;
        if (extraAudio) ++staleDuration;
        std::printf("capture iteration=%d text=%ls first_audio_ms=%.1f duration_ms=%.1f baseline_ms=%.1f stale_audio=%s file=%ls\n",
                    i + 1, nextText, ms, duration, baseline, extraAudio ? "yes" : "no", path.c_str());
    }
    std::printf("rapid_purge_restart n=%zu median_ms=%.1f p95_ms=%.1f max_ms=%.1f\n", rapid.size(),
                percentile(rapid, .50), percentile(rapid, .95), *std::max_element(rapid.begin(), rapid.end()));
    std::printf("capture_summary trials=%zu excess_audio=%u output=%ls\n",
                rapid.size(), staleDuration, outputDir.c_str());
    if (staleDuration) return 18;
    return 0;
}

int wmain(int argc, wchar_t** argv) {
    bool latencyMode = false;
    long latencyRate = 0;
    std::wstring captureDir = L"sapi-latency-captures";
    for (int i = 1; i < argc; ++i) {
        if (!wcscmp(argv[i], L"--latency")) {
            latencyMode = true;
            if (i + 1 < argc && wcsncmp(argv[i + 1], L"--", 2) != 0) captureDir = argv[i + 1];
        }
        if (!wcscmp(argv[i], L"--latency-rate") && i + 1 < argc) latencyRate = wcstol(argv[i + 1], nullptr, 10);
    }
    HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    if (FAILED(hr)) return 1;
    ISpObjectToken* token = nullptr;
    ISpVoice* voice = nullptr;
    hr = CoCreateInstance(CLSID_SpObjectToken, nullptr, CLSCTX_INPROC_SERVER,
                          IID_ISpObjectToken, reinterpret_cast<void**>(&token));
    bool machineMode = argc > 1 && wcscmp(argv[1], L"--machine") == 0;
    const wchar_t* tokenId = machineMode
        ? L"HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Speech\\Voices\\Tokens\\PocketTTSProof7m"
        : L"HKEY_CURRENT_USER\\SOFTWARE\\Microsoft\\Speech\\Voices\\Tokens\\PocketTTSProof7m";
    if (SUCCEEDED(hr)) hr = token->SetId(nullptr, tokenId, FALSE);
    if (SUCCEEDED(hr)) hr = CoCreateInstance(CLSID_SpVoice, nullptr, CLSCTX_ALL,
                                             IID_ISpVoice, reinterpret_cast<void**>(&voice));
    if (SUCCEEDED(hr)) hr = voice->SetVoice(token);
    if (SUCCEEDED(hr) && latencyMode) {
        int result = runLatency(voice, captureDir, latencyRate);
        if (voice) voice->Release();
        if (token) token->Release();
        CoUninitialize();
        return result;
    }
    const ULONGLONG mask = SPFEI(SPEI_WORD_BOUNDARY) | SPFEI(SPEI_SENTENCE_BOUNDARY);
    if (SUCCEEDED(hr)) hr = voice->SetInterest(mask, mask);
    int modeArg = machineMode ? 2 : 1;
    bool cancelMode = argc > modeArg && wcscmp(argv[modeArg], L"--cancel") == 0;
    bool rateMode = argc > modeArg && wcscmp(argv[modeArg], L"--rate") == 0;
    bool ssmlMode = argc > modeArg && wcscmp(argv[modeArg], L"--ssml") == 0;
    bool limitMode = argc > modeArg && wcscmp(argv[modeArg], L"--limit") == 0;
    bool missingMode = argc > modeArg && wcscmp(argv[modeArg], L"--missing") == 0;
    if (SUCCEEDED(hr) && rateMode) {
        std::wstring outputDir = argc > modeArg + 1 ? argv[modeArg + 1] : L"rate-captures";
        int result = runRate(voice, outputDir);
        if (voice) voice->Release();
        if (token) token->Release();
        CoUninitialize();
        return result;
    } else if (SUCCEEDED(hr) && cancelMode) {
        std::wstring longText;
        for (int i = 0; i < 150; ++i)
            longText += L"Pocket TTS cancellation test. The speech engine should stop promptly when purged. ";
        hr = voice->Speak(longText.c_str(), SPF_ASYNC, nullptr);
        std::printf("cancel_queue_hr=0x%08lx chars=%zu\n", static_cast<unsigned long>(hr), longText.size());
        if (SUCCEEDED(hr)) {
            Sleep(250);
            ULONGLONG start = GetTickCount64();
            hr = voice->Speak(nullptr, SPF_PURGEBEFORESPEAK | SPF_ASYNC, nullptr);
            std::printf("cancel_purge_hr=0x%08lx\n", static_cast<unsigned long>(hr));
            if (SUCCEEDED(hr)) hr = voice->WaitUntilDone(5000);
            std::printf("cancel_elapsed_ms=%llu\n",
                        static_cast<unsigned long long>(GetTickCount64() - start));
        }
    } else if (SUCCEEDED(hr) && limitMode) {
        std::wstring oversized(32769, L'x');
        hr = voice->Speak(oversized.c_str(), SPF_DEFAULT, nullptr);
        std::printf("oversize_hr=0x%08lx\n", static_cast<unsigned long>(hr));
        bool rejected = FAILED(hr);
        if (voice) voice->Release();
        if (token) token->Release();
        CoUninitialize();
        return rejected ? 0 : 4;
    } else if (SUCCEEDED(hr) && ssmlMode) {
        hr = voice->Speak(
            L"<speak version=\"1.0\" xmlns=\"http://www.w3.org/2001/10/synthesis\" xml:lang=\"en-US\"><s>First fragment.</s><break time=\"500ms\"/><s>Second fragment.</s></speak>",
            SPF_IS_XML, nullptr);
    } else if (SUCCEEDED(hr)) {
        hr = voice->Speak(
            L"Pocket TTS is speaking through Windows SAPI. This proof uses a local cloned voice.",
            SPF_DEFAULT, nullptr);
    }
    unsigned sentences = 0, words = 0;
    if (SUCCEEDED(hr)) {
        SPEVENT events[64]{};
        ULONG count = 0;
        while (SUCCEEDED(voice->GetEvents(64, events, &count)) && count) {
            for (ULONG i = 0; i < count; ++i) {
                if (events[i].eEventId == SPEI_SENTENCE_BOUNDARY) ++sentences;
                if (events[i].eEventId == SPEI_WORD_BOUNDARY) ++words;
            }
        }
    }
    std::printf("hr=0x%08lx sentence_events=%u word_events=%u\n",
                static_cast<unsigned long>(hr), sentences, words);
    if (voice) voice->Release();
    if (token) token->Release();
    CoUninitialize();
    if (missingMode) return FAILED(hr) ? 0 : 5;
    if (ssmlMode) return SUCCEEDED(hr) && sentences >= 2 && words >= 4 ? 0 : 3;
    return SUCCEEDED(hr) && (cancelMode || (sentences > 0 && words > 0)) ? 0 : 2;
}
