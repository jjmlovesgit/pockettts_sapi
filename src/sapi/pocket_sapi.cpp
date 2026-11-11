// Pocket TTS SAPI 5 proof: local COM engine backed by the official Rust server.
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <winhttp.h>
#include <iphlpapi.h>
#include <sapi.h>
#include <sapiddk.h>
#include <algorithm>
#include <atomic>
#include <cctype>
#include <cstdint>
#include <cmath>
#include <chrono>
#include <cwctype>
#include <fstream>
#include <iterator>
#include <list>
#include <mutex>
#include <new>
#include <thread>
#include <string>
#include <vector>

#pragma comment(lib, "winhttp.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "iphlpapi.lib")
#pragma comment(lib, "advapi32.lib")
#pragma comment(lib, "ws2_32.lib")

namespace {
#ifdef POCKETTTS_TEST_CLSID
const GUID kClsid = {0x2f28f1b0,0x0e38,0x49e7,{0x9f,0x14,0x0c,0xcb,0x3c,0x11,0xc7,0x09}};
#else
const GUID kClsid = {0x52586884,0xb3dc,0x46c5,{0xa2,0x98,0xa4,0x96,0x06,0xcc,0x54,0x21}};
#endif
std::atomic<long> gObjects{0};
std::atomic<long> gLocks{0};
constexpr INTERNET_PORT kPort = 18765;
constexpr size_t kMaxTextChars = 32768;
constexpr size_t kMaxAudioBytes = 32u * 1024u * 1024u;
constexpr size_t kReplayCacheBytes = 32u * 1024u * 1024u;
constexpr size_t kReplayCacheEntryBytes = 4u * 1024u * 1024u;
constexpr size_t kReplayCacheEntries = 64;

struct CachedSpeech {
    std::wstring key;
    std::vector<unsigned char> wav;
};
std::mutex gReplayCacheMutex;
std::list<CachedSpeech> gReplayCache;
size_t gReplayCacheSize = 0;

std::wstring ReplayKey(const std::wstring& text, const std::wstring& voice,
                       const std::wstring& language) {
    std::wstring key = language + L'\x1f' + voice + L'\x1f' + text;
    WIN32_FILE_ATTRIBUTE_DATA attributes{};
    if (GetFileAttributesExW(voice.c_str(), GetFileExInfoStandard, &attributes)) {
        key += L'\x1f' + std::to_wstring(attributes.nFileSizeHigh);
        key += L':' + std::to_wstring(attributes.nFileSizeLow);
        key += L':' + std::to_wstring(attributes.ftLastWriteTime.dwHighDateTime);
        key += L':' + std::to_wstring(attributes.ftLastWriteTime.dwLowDateTime);
    }
    return key;
}

bool CachedReplay(const std::wstring& key, std::vector<unsigned char>& wav) {
    std::lock_guard<std::mutex> guard(gReplayCacheMutex);
    for (auto item = gReplayCache.begin(); item != gReplayCache.end(); ++item) {
        if (item->key != key) continue;
        wav = item->wav;
        gReplayCache.splice(gReplayCache.begin(), gReplayCache, item);
        return true;
    }
    return false;
}

void RememberReplay(std::wstring key, const std::vector<unsigned char>& wav) {
    if (wav.empty() || wav.size() > kReplayCacheEntryBytes) return;
    std::lock_guard<std::mutex> guard(gReplayCacheMutex);
    for (auto item = gReplayCache.begin(); item != gReplayCache.end(); ++item) {
        if (item->key != key) continue;
        gReplayCacheSize -= item->wav.size();
        gReplayCache.erase(item);
        break;
    }
    gReplayCache.push_front({std::move(key), wav});
    gReplayCacheSize += wav.size();
    while (gReplayCacheSize > kReplayCacheBytes || gReplayCache.size() > kReplayCacheEntries) {
        gReplayCacheSize -= gReplayCache.back().wav.size();
        gReplayCache.pop_back();
    }
}
// Axum's multipart default request limit is 2 MiB. Prompt files are normalized
// to 24 kHz mono and kept below this limit with room for multipart framing.
constexpr size_t kMaxVoicePromptUploadBytes = 1800000u;

std::string Utf8(const std::wstring& s) {
    int n = WideCharToMultiByte(CP_UTF8, 0, s.c_str(), static_cast<int>(s.size()), nullptr, 0, nullptr, nullptr);
    if (n <= 0) return {};
    std::string out(static_cast<size_t>(n), '\0');
    WideCharToMultiByte(CP_UTF8, 0, s.c_str(), static_cast<int>(s.size()), out.data(), n, nullptr, nullptr);
    return out;
}

std::string FormEncode(const std::string& in) {
    constexpr char hex[] = "0123456789ABCDEF";
    std::string out = "text=";
    for (unsigned char c : in) {
        if (std::isalnum(c) || c == '-' || c == '_' || c == '.' || c == '~') out.push_back(static_cast<char>(c));
        else if (c == ' ') out.push_back('+');
        else { out.push_back('%'); out.push_back(hex[c >> 4]); out.push_back(hex[c & 15]); }
    }
    return out;
}

// Pocket's model can read compact initialisms as a word. Normalize only the
// synthesis copy; keep SAPI's source text unchanged for boundary events.
std::wstring SpokenText(const std::wstring& source) {
    struct PronunciationRule {
        const wchar_t* written;
        const wchar_t* spoken;
        size_t length;
    };
    static const PronunciationRule rules[] = {
        {L"TTS", L"tee tee ess", 3},
        {L"ZP", L"zee eye pee", 2},
    };
    std::wstring out;
    for (size_t i = 0; i < source.size();) {
        bool replaced = false;
        for (const auto& rule : rules) {
            const bool leftBoundary = i == 0 || !std::iswalnum(source[i - 1]);
            if (!leftBoundary || i + rule.length > source.size()) continue;
            bool match = true;
            for (size_t j = 0; j < rule.length; ++j) {
                if (std::towupper(source[i + j]) != rule.written[j]) {
                    match = false;
                    break;
                }
            }
            const bool rightBoundary = i + rule.length >= source.size() ||
                !std::iswalnum(source[i + rule.length]);
            if (!match || !rightBoundary) continue;
            out += rule.spoken;
            i += rule.length;
            replaced = true;
            break;
        }
        if (!replaced) out.push_back(source[i++]);
    }
    return out;
}

struct HttpHandle {
    HINTERNET h = nullptr;
    explicit HttpHandle(HINTERNET value = nullptr) : h(value) {}
    ~HttpHandle() { if (h) WinHttpCloseHandle(h); }
    HttpHandle(const HttpHandle&) = delete;
    HttpHandle& operator=(const HttpHandle&) = delete;
};

struct CancelableRequest {
    HINTERNET h;
    std::atomic<HINTERNET>& active;
    CancelableRequest(HINTERNET value, std::atomic<HINTERNET>& slot) : h(value), active(slot) {
        active.store(value, std::memory_order_release);
    }
    ~CancelableRequest() {
        if (h && active.exchange(nullptr, std::memory_order_acq_rel) == h) WinHttpCloseHandle(h);
    }
};

struct EventHandle {
    HANDLE h = nullptr;
    explicit EventHandle(HANDLE value = nullptr) : h(value) {}
    ~EventHandle() { if (h) CloseHandle(h); }
    EventHandle(const EventHandle&) = delete;
    EventHandle& operator=(const EventHandle&) = delete;
};

struct WorkerMutexLease {
    HANDLE h = nullptr;
    bool owned = false;
    explicit WorkerMutexLease(HANDLE value) : h(value) {}
    ~WorkerMutexLease() {
        if (owned) ReleaseMutex(h);
        if (h) CloseHandle(h);
    }
    WorkerMutexLease(const WorkerMutexLease&) = delete;
    WorkerMutexLease& operator=(const WorkerMutexLease&) = delete;
};

HRESULT EnsureServer(const std::wstring& language, const std::wstring& defaultVoice);
bool GetInstallRoot(std::wstring& root);

HRESULT FetchWavSync(const std::wstring& text, const std::wstring& voiceStatePath,
                 const std::wstring& language,
                 std::atomic<bool>& cancelled, std::atomic<HINTERNET>& activeRequest,
                 std::vector<unsigned char>& wav, bool& aborted) {
    const bool traceTiming = GetEnvironmentVariableW(L"POCKETTTS_SAPI_HTTP_TRACE", nullptr, 0) != 0;
    const auto totalStart = std::chrono::steady_clock::now();
    auto mark = totalStart;
    auto trace = [&](const wchar_t* phase) {
        if (!traceTiming) return;
        const auto now = std::chrono::steady_clock::now();
        wchar_t line[192]{};
        swprintf_s(line, L"PocketTTS SAPI HTTP %ls %.1fms\n", phase,
                   std::chrono::duration<double, std::milli>(now - mark).count());
        OutputDebugStringW(line);
        mark = now;
    };
    // Keep the selected worker alive until this HTTP response is complete.
    // Other SAPI clients may use different voice tokens in separate processes.
    WorkerMutexLease workerMutex(CreateMutexW(nullptr, FALSE, L"Local\\PocketTTS.SAPI.Worker"));
    if (!workerMutex.h) return HRESULT_FROM_WIN32(GetLastError());
    for (int attempt = 0; attempt < 100 && !workerMutex.owned; ++attempt) {
        if (cancelled.load()) { aborted = true; return S_OK; }
        DWORD wait = WaitForSingleObject(workerMutex.h, 100);
        if (wait == WAIT_OBJECT_0 || wait == WAIT_ABANDONED) workerMutex.owned = true;
        else if (wait != WAIT_TIMEOUT) return HRESULT_FROM_WIN32(GetLastError());
    }
    if (!workerMutex.owned) return HRESULT_FROM_WIN32(ERROR_TIMEOUT);
    HRESULT ready = EnsureServer(language, voiceStatePath);
    if (FAILED(ready)) return ready;
    if (cancelled.load()) { aborted = true; return S_OK; }
    // The installed worker starts with this state as its default voice. Sending
    // text alone avoids the server's 2 MiB multipart limit for larger presets.
    std::wstring installedRoot;
    const std::wstring requestVoicePath = GetInstallRoot(installedRoot) ? L"" : voiceStatePath;
    trace(L"ensure_server");
    HttpHandle session(WinHttpOpen(L"PocketTTS-SAPI-Proof/0.1", WINHTTP_ACCESS_TYPE_NO_PROXY,
                                  WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0));
    if (!session.h) return HRESULT_FROM_WIN32(GetLastError());
    WinHttpSetTimeouts(session.h, 2000, 2000, 3000, 30000);
    HttpHandle conn(WinHttpConnect(session.h, L"127.0.0.1", kPort, 0));
    if (!conn.h) return HRESULT_FROM_WIN32(GetLastError());
    CancelableRequest req(WinHttpOpenRequest(conn.h, L"POST", L"/tts", nullptr, WINHTTP_NO_REFERER,
                                      WINHTTP_DEFAULT_ACCEPT_TYPES, 0), activeRequest);
    if (!req.h) return HRESULT_FROM_WIN32(GetLastError());
    if (cancelled.load()) { aborted = true; return S_OK; }
    const std::string encodedText = Utf8(text);
    std::string body;
    std::wstring contentType;
    if (requestVoicePath.empty()) {
        body = FormEncode(encodedText);
        contentType = L"Content-Type: application/x-www-form-urlencoded\r\n";
    } else {
        std::ifstream file(requestVoicePath, std::ios::binary);
        if (!file) return HRESULT_FROM_WIN32(ERROR_FILE_NOT_FOUND);
        file.seekg(0, std::ios::end);
        const auto fileSize = file.tellg();
        if (fileSize <= 0 || fileSize > kMaxVoicePromptUploadBytes)
            return HRESULT_FROM_WIN32(ERROR_FILE_TOO_LARGE);
        file.seekg(0, std::ios::beg);
        std::vector<char> state(static_cast<size_t>(fileSize));
        if (!file.read(state.data(), fileSize)) return E_FAIL;
        const bool audioPrompt = requestVoicePath.size() >= 4 &&
            _wcsicmp(requestVoicePath.c_str() + requestVoicePath.size() - 4, L".wav") == 0;
        const char* filename = audioPrompt ? "voice.wav" : "voice.safetensors";
        const char* mime = audioPrompt ? "audio/wav" : "application/octet-stream";
        contentType = L"Content-Type: multipart/form-data; boundary=----PocketTTSVoiceBoundary7MA4YWxk\r\n";
        body = "------PocketTTSVoiceBoundary7MA4YWxk\r\nContent-Disposition: form-data; name=\"text\"\r\n\r\n";
        body += encodedText;
        body += "\r\n------PocketTTSVoiceBoundary7MA4YWxk\r\nContent-Disposition: form-data; name=\"voice_wav\"; filename=\"";
        body += filename;
        body += "\"\r\nContent-Type: ";
        body += mime;
        body += "\r\n\r\n";
        body.append(state.data(), state.size());
        body += "\r\n------PocketTTSVoiceBoundary7MA4YWxk--\r\n";
    }
    if (!WinHttpSendRequest(req.h, contentType.c_str(), -1,
                            const_cast<char*>(body.data()), static_cast<DWORD>(body.size()),
                            static_cast<DWORD>(body.size()), 0))
        return cancelled.load() ? S_OK : HRESULT_FROM_WIN32(GetLastError());
    if (cancelled.load()) { aborted = true; return S_OK; }
    trace(L"send_request");
    if (!WinHttpReceiveResponse(req.h, nullptr))
        return cancelled.load() ? S_OK : HRESULT_FROM_WIN32(GetLastError());
    if (cancelled.load()) { aborted = true; return S_OK; }
    trace(L"receive_headers");
    DWORD status = 0, statusSize = sizeof(status);
    if (!WinHttpQueryHeaders(req.h, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                             WINHTTP_HEADER_NAME_BY_INDEX, &status, &statusSize, WINHTTP_NO_HEADER_INDEX))
        return HRESULT_FROM_WIN32(GetLastError());
    if (status != 200) return E_FAIL;
    wav.clear();
    unsigned char buffer[16384];
    for (;;) {
        if (cancelled.load()) { aborted = true; return S_OK; }
        DWORD count = 0;
        if (!WinHttpReadData(req.h, buffer, sizeof(buffer), &count))
            return cancelled.load() ? S_OK : HRESULT_FROM_WIN32(GetLastError());
        if (cancelled.load()) { aborted = true; return S_OK; }
        if (!count) break;
        if (wav.size() + count > kMaxAudioBytes) return HRESULT_FROM_WIN32(ERROR_BUFFER_OVERFLOW);
        wav.insert(wav.end(), buffer, buffer + count);
    }
    trace(L"read_body");
    if (traceTiming) {
        wchar_t line[192]{};
        swprintf_s(line, L"PocketTTS SAPI HTTP total %.1fms bytes=%zu\n",
                   std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - totalStart).count(), wav.size());
        OutputDebugStringW(line);
    }
    return S_OK;
}

HRESULT FetchWav(const std::wstring& text, const std::wstring& voiceStatePath,
                 const std::wstring& language, ISpTTSEngineSite* site,
                 std::vector<unsigned char>& wav, bool& aborted) {
    std::atomic<bool> cancelled{false}, finished{false};
    std::atomic<HINTERNET> activeRequest{nullptr};
    HRESULT result = E_FAIL;
    bool workerAborted = false;
    std::thread worker([&] {
        try {
            result = FetchWavSync(text, voiceStatePath, language, cancelled, activeRequest, wav, workerAborted);
        } catch (...) {
            result = E_FAIL;
        }
        finished.store(true, std::memory_order_release);
    });
    while (!finished.load(std::memory_order_acquire)) {
        if (site->GetActions() & SPVES_ABORT) {
            cancelled.store(true);
            if (HINTERNET request = activeRequest.exchange(nullptr)) WinHttpCloseHandle(request);
            break;
        }
        Sleep(5);
    }
    worker.join();
    aborted = cancelled.load() || workerAborted;
    return aborted ? S_OK : result;
}

uint32_t U32(const unsigned char* p) {
    return uint32_t(p[0]) | (uint32_t(p[1]) << 8) | (uint32_t(p[2]) << 16) | (uint32_t(p[3]) << 24);
}

bool GetInstallRoot(std::wstring& root) {
#ifdef POCKETTTS_TEST_CLSID
    wchar_t testRoot[32768]{};
    DWORD testChars = GetEnvironmentVariableW(L"POCKETTTS_SAPI_TEST_ROOT", testRoot, ARRAYSIZE(testRoot));
    if (testChars > 0 && testChars < ARRAYSIZE(testRoot)) {
        root.assign(testRoot, testChars);
        return true;
    }
#endif
    HKEY key = nullptr;
    if (RegOpenKeyExW(HKEY_LOCAL_MACHINE, L"SOFTWARE\\PocketTTS", 0, KEY_QUERY_VALUE, &key) != ERROR_SUCCESS)
        return false;
    DWORD type = 0, bytes = 0;
    LONG result = RegQueryValueExW(key, L"InstallRoot", nullptr, &type, nullptr, &bytes);
    if (result != ERROR_SUCCESS || type != REG_SZ || bytes < sizeof(wchar_t)) {
        RegCloseKey(key);
        return false;
    }
    std::wstring value(bytes / sizeof(wchar_t), L'\0');
    result = RegQueryValueExW(key, L"InstallRoot", nullptr, &type,
                              reinterpret_cast<BYTE*>(value.data()), &bytes);
    RegCloseKey(key);
    if (result != ERROR_SUCCESS) return false;
    while (!value.empty() && value.back() == L'\0') value.pop_back();
    root = std::move(value);
    return !root.empty();
}

bool IsSupportedModelLanguage(const std::wstring& value) {
    static const wchar_t* supported[] = {L"english_7m_refl_2026-10", L"french", L"german", L"italian", L"spanish", L"portuguese", L"dutch"};
    for (const auto* item : supported) if (_wcsicmp(value.c_str(), item) == 0) return true;
    return false;
}

std::wstring ReadRegistryString(const wchar_t* subkey, const wchar_t* name, const std::wstring& fallback) {
    HKEY key = nullptr;
    if (RegOpenKeyExW(HKEY_LOCAL_MACHINE, subkey, 0, KEY_QUERY_VALUE, &key) != ERROR_SUCCESS) return fallback;
    DWORD type = 0, bytes = 0;
    LONG result = RegQueryValueExW(key, name, nullptr, &type, nullptr, &bytes);
    if (result != ERROR_SUCCESS || type != REG_SZ || bytes < sizeof(wchar_t)) {
        RegCloseKey(key);
        return fallback;
    }
    std::wstring value(bytes / sizeof(wchar_t), L'\0');
    result = RegQueryValueExW(key, name, nullptr, &type,
                              reinterpret_cast<BYTE*>(value.data()), &bytes);
    RegCloseKey(key);
    if (result != ERROR_SUCCESS) return fallback;
    while (!value.empty() && value.back() == L'\0') value.pop_back();
    return value.empty() ? fallback : value;
}

std::wstring GetModelLanguage() {
    std::wstring value = ReadRegistryString(L"SOFTWARE\\PocketTTS", L"ModelLanguage", L"english_7m_refl_2026-10");
    return IsSupportedModelLanguage(value) ? value : L"english_7m_refl_2026-10";
}

bool SetRegistryString(const wchar_t* name, const std::wstring& value) {
    HKEY key = nullptr;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, L"SOFTWARE\\PocketTTS", 0, nullptr, 0, KEY_SET_VALUE, nullptr, &key, nullptr) != ERROR_SUCCESS) return false;
    const LONG result = RegSetValueExW(key, name, 0, REG_SZ, reinterpret_cast<const BYTE*>(value.c_str()), static_cast<DWORD>((value.size()+1)*sizeof(wchar_t)));
    RegCloseKey(key);
    return result == ERROR_SUCCESS;
}

std::wstring ReadWorkerValue(const wchar_t* name) {
    HKEY key = nullptr;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, L"SOFTWARE\\PocketTTS", 0, KEY_QUERY_VALUE, &key) != ERROR_SUCCESS) return L"";
    DWORD type=0, bytes=0;
    LONG rc=RegQueryValueExW(key,name,nullptr,&type,nullptr,&bytes);
    if(rc!=ERROR_SUCCESS || type!=REG_SZ || bytes<sizeof(wchar_t)){RegCloseKey(key);return L"";}
    std::wstring value(bytes/sizeof(wchar_t),L'\0');
    rc=RegQueryValueExW(key,name,nullptr,&type,reinterpret_cast<BYTE*>(value.data()),&bytes);
    RegCloseKey(key);
    if(rc!=ERROR_SUCCESS)return L"";
    while(!value.empty()&&value.back()==L'\0')value.pop_back();
    return value;
}

bool HasLoopbackListener() {
    DWORD bytes = 0;
    if (GetExtendedTcpTable(nullptr, &bytes, FALSE, AF_INET, TCP_TABLE_OWNER_PID_LISTENER, 0) != ERROR_INSUFFICIENT_BUFFER)
        return false;
    std::vector<unsigned char> storage(bytes);
    auto* table = reinterpret_cast<MIB_TCPTABLE_OWNER_PID*>(storage.data());
    if (GetExtendedTcpTable(table, &bytes, FALSE, AF_INET, TCP_TABLE_OWNER_PID_LISTENER, 0) != NO_ERROR)
        return false;
    for (DWORD i = 0; i < table->dwNumEntries; ++i) {
        const auto& row = table->table[i];
        if (ntohs(static_cast<u_short>(row.dwLocalPort)) == kPort &&
            (row.dwLocalAddr == htonl(INADDR_LOOPBACK) || row.dwLocalAddr == htonl(INADDR_ANY)))
            return true;
    }
    return false;
}

bool IsServerHealthy() {
    // A closed loopback port makes WinHTTP spend seconds on a failed request
    // on some Windows hosts. Skip that request when no listener exists.
    if (!HasLoopbackListener()) return false;
    HttpHandle session(WinHttpOpen(L"PocketTTS-SAPI/0.2", WINHTTP_ACCESS_TYPE_NO_PROXY,
                                  WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0));
    if (!session.h) return false;
    WinHttpSetTimeouts(session.h, 500, 500, 500, 1000);
    HttpHandle conn(WinHttpConnect(session.h, L"127.0.0.1", kPort, 0));
    if (!conn.h) return false;
    HttpHandle req(WinHttpOpenRequest(conn.h, L"GET", L"/health", nullptr,
                                      WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, 0));
    if (!req.h || !WinHttpSendRequest(req.h, WINHTTP_NO_ADDITIONAL_HEADERS, 0,
                                      WINHTTP_NO_REQUEST_DATA, 0, 0, 0) ||
        !WinHttpReceiveResponse(req.h, nullptr)) return false;
    DWORD status = 0, size = sizeof(status);
    return WinHttpQueryHeaders(req.h, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                               WINHTTP_HEADER_NAME_BY_INDEX, &status, &size,
                               WINHTTP_NO_HEADER_INDEX) && status == 200;
}

bool ServerOwnsPort(const std::wstring& expectedExe, DWORD* ownerPid = nullptr) {
    DWORD bytes = 0;
    if (GetExtendedTcpTable(nullptr, &bytes, FALSE, AF_INET, TCP_TABLE_OWNER_PID_LISTENER, 0) != ERROR_INSUFFICIENT_BUFFER)
        return false;
    std::vector<unsigned char> storage(bytes);
    auto* table = reinterpret_cast<MIB_TCPTABLE_OWNER_PID*>(storage.data());
    if (GetExtendedTcpTable(table, &bytes, FALSE, AF_INET, TCP_TABLE_OWNER_PID_LISTENER, 0) != NO_ERROR)
        return false;
    for (DWORD i = 0; i < table->dwNumEntries; ++i) {
        const auto& row = table->table[i];
        if (ntohs(static_cast<u_short>(row.dwLocalPort)) != kPort || row.dwLocalAddr != htonl(INADDR_LOOPBACK))
            continue;
        HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, row.dwOwningPid);
        if (!process) return false;
        std::wstring image(32768, L'\0');
        DWORD chars = static_cast<DWORD>(image.size());
        const bool queried = QueryFullProcessImageNameW(process, 0, image.data(), &chars) != FALSE;
        CloseHandle(process);
        if (!queried) return false;
        image.resize(chars);
        if (_wcsicmp(image.c_str(), expectedExe.c_str()) != 0) return false;
        if (ownerPid) *ownerPid = row.dwOwningPid;
        return true;
    }
    return false;
}

HRESULT EnsureServer(const std::wstring& requestedLanguage, const std::wstring& requestedVoice) {
    const std::wstring language = IsSupportedModelLanguage(requestedLanguage) ? requestedLanguage : GetModelLanguage();
    std::wstring root;
    if (!GetInstallRoot(root)) return S_OK; // Development tests manage their own server.
    const std::wstring exe = root + L"\\pocket-tts.exe";
    const std::wstring cache = root + L"\\models\\hf";
    const std::wstring voice = requestedVoice.empty() ? root + L"\\voices\\Alba.safetensors" : requestedVoice;
    if (GetFileAttributesW(exe.c_str()) == INVALID_FILE_ATTRIBUTES ||
        GetFileAttributesW(cache.c_str()) == INVALID_FILE_ATTRIBUTES ||
        GetFileAttributesW(voice.c_str()) == INVALID_FILE_ATTRIBUTES)
        return HRESULT_FROM_WIN32(ERROR_FILE_NOT_FOUND);
    HANDLE mutex = CreateMutexW(nullptr, FALSE, L"Local\\PocketTTS.SAPI.Worker");
    if (!mutex) return HRESULT_FROM_WIN32(GetLastError());
    DWORD wait = WaitForSingleObject(mutex, 10000);
    if (wait != WAIT_OBJECT_0 && wait != WAIT_ABANDONED) {
        CloseHandle(mutex);
        return HRESULT_FROM_WIN32(ERROR_TIMEOUT);
    }
    HRESULT result = S_OK;
    if (IsServerHealthy()) {
        DWORD pid = 0;
        if (!ServerOwnsPort(exe, &pid)) result = HRESULT_FROM_WIN32(ERROR_ADDRESS_ALREADY_ASSOCIATED);
        else {
            const std::wstring running = ReadWorkerValue(L"WorkerLanguage");
            const std::wstring runningVoice = ReadWorkerValue(L"WorkerVoice");
            if (_wcsicmp(running.c_str(), language.c_str()) != 0 ||
                _wcsicmp(runningVoice.c_str(), voice.c_str()) != 0) {
                if (running.empty() || runningVoice.empty()) result = HRESULT_FROM_WIN32(ERROR_INVALID_STATE);
                else {
                    HANDLE old = OpenProcess(PROCESS_TERMINATE | SYNCHRONIZE, FALSE, pid);
                    if (!old || !TerminateProcess(old, 0)) result = HRESULT_FROM_WIN32(GetLastError());
                    else {
                        for (int i=0; i<100 && IsServerHealthy(); ++i) Sleep(100);
                        if (IsServerHealthy()) result = HRESULT_FROM_WIN32(ERROR_TIMEOUT);
                    }
                    if (old) CloseHandle(old);
                }
            }
        }
    }
    if (SUCCEEDED(result) && !IsServerHealthy()) {
        std::wstring command = L"\"" + exe + L"\" serve --host 127.0.0.1 --port " +
            std::to_wstring(kPort) + L" --language " + language + L" --default-voice \"" + voice + L"\"";
        STARTUPINFOW startup{};
        startup.cb = sizeof(startup);
        PROCESS_INFORMATION process{};
        wchar_t oldCache[32768]{}, oldOffline[64]{};
        DWORD oldCacheSize = GetEnvironmentVariableW(L"HF_HUB_CACHE", oldCache, ARRAYSIZE(oldCache));
        DWORD oldOfflineSize = GetEnvironmentVariableW(L"HF_HUB_OFFLINE", oldOffline, ARRAYSIZE(oldOffline));
        if (!SetEnvironmentVariableW(L"HF_HUB_CACHE", cache.c_str()) ||
            !SetEnvironmentVariableW(L"HF_HUB_OFFLINE", L"1")) {
            result = HRESULT_FROM_WIN32(GetLastError());
        } else if (!CreateProcessW(nullptr, command.data(), nullptr, nullptr, FALSE, CREATE_NO_WINDOW,
                                   nullptr, root.c_str(), &startup, &process)) {
            result = HRESULT_FROM_WIN32(GetLastError());
        } else {
            CloseHandle(process.hThread);
            bool ready = false;
            for (int i = 0; i < 300; ++i) {
                if (IsServerHealthy()) { ready = true; break; }
                if (WaitForSingleObject(process.hProcess, 0) == WAIT_OBJECT_0) break;
                Sleep(100);
            }
            CloseHandle(process.hProcess);
            if (!ready) result = HRESULT_FROM_WIN32(ERROR_SERVICE_NOT_ACTIVE);
            else if (!ServerOwnsPort(exe)) result = HRESULT_FROM_WIN32(ERROR_ADDRESS_ALREADY_ASSOCIATED);
            else if (!SetRegistryString(L"WorkerLanguage", language) ||
                     !SetRegistryString(L"WorkerVoice", voice)) result = HRESULT_FROM_WIN32(ERROR_ACCESS_DENIED);
        }
        if (oldCacheSize == 0) SetEnvironmentVariableW(L"HF_HUB_CACHE", nullptr);
        else SetEnvironmentVariableW(L"HF_HUB_CACHE", oldCache);
        if (oldOfflineSize == 0) SetEnvironmentVariableW(L"HF_HUB_OFFLINE", nullptr);
        else SetEnvironmentVariableW(L"HF_HUB_OFFLINE", oldOffline);
    }
    ReleaseMutex(mutex);
    CloseHandle(mutex);
    return result;
}

HRESULT PcmRange(const std::vector<unsigned char>& wav, size_t& start, size_t& bytes) {
    if (wav.size() < 44 || memcmp(wav.data(), "RIFF", 4) || memcmp(wav.data()+8, "WAVE", 4)) return E_FAIL;
    bool fmt = false;
    size_t pos = 12;
    while (pos + 8 <= wav.size()) {
        const uint32_t len = U32(wav.data()+pos+4);
        if (!memcmp(wav.data()+pos, "fmt ", 4) && len >= 16 && pos + 24 <= wav.size()) {
            const unsigned char* p = wav.data()+pos+8;
            fmt = p[0] == 1 && p[1] == 0 && p[2] == 1 && p[3] == 0 && U32(p+4) == 24000 && p[14] == 16;
        }
        if (!memcmp(wav.data()+pos, "data", 4)) {
            if (!fmt) return E_FAIL;
            start = pos + 8;
            bytes = (wav.size() - start) & ~size_t(1); // streaming header uses an unknown data length
            return bytes ? S_OK : E_FAIL;
        }
        if (len > wav.size() - pos - 8) return E_FAIL;
        pos += 8 + len + (len & 1);
    }
    return E_FAIL;
}

// Pocket TTS can emit several hundred milliseconds of near-silence before a
// word. Remove that delay from generated speech, while retaining 100 ms before
// the first sustained voice energy so quiet initial consonants are preserved.
size_t TrimGeneratedLeadingSilence(const std::vector<unsigned char>& wav, size_t start, size_t bytes) {
    constexpr size_t samplesPerWindow = 240; // 10 ms at the validated 24 kHz PCM format
    constexpr size_t prerollSamples = 2400;
    constexpr size_t maxScanSamples = 48000;
    constexpr uint64_t rmsThresholdSquared = 65u * 65u; // roughly -54 dBFS
    const size_t samples = std::min(bytes / 2, maxScanSamples);
    for (size_t at = 0; at + 2 * samplesPerWindow <= samples; at += samplesPerWindow) {
        auto audibleWindow = [&](size_t first) {
            uint64_t power = 0;
            for (size_t i = first; i < first + samplesPerWindow; ++i) {
                const size_t p = start + i * 2;
                const int16_t sample = static_cast<int16_t>(
                    static_cast<uint16_t>(wav[p]) | (static_cast<uint16_t>(wav[p + 1]) << 8));
                power += static_cast<int32_t>(sample) * sample;
            }
            return power >= rmsThresholdSquared * samplesPerWindow;
        };
        if (audibleWindow(at) && audibleWindow(at + samplesPerWindow))
            return at > prerollSamples ? (at - prerollSamples) * 2 : 0;
    }
    return 0;
}

long ClampSapiRate(long rate) {
    return std::clamp(rate, -10L, 10L);
}

enum class PaceVariant { Slow, Normal, Fast };
PaceVariant RateToPaceVariant(long rate) {
    const long clamped = ClampSapiRate(rate);
    if (clamped <= -3) return PaceVariant::Slow;
    if (clamped >= 3) return PaceVariant::Fast;
    return PaceVariant::Normal;
}

class Engine final : public ISpTTSEngine, public ISpObjectWithToken {
    std::atomic<ULONG> refs_{1};
    ISpObjectToken* token_ = nullptr;
public:
    Engine() { ++gObjects; }
    ~Engine() { if (token_) token_->Release(); --gObjects; }
    STDMETHODIMP QueryInterface(REFIID iid, void** out) override {
        if (!out) return E_POINTER;
        *out = nullptr;
        if (iid == IID_IUnknown || iid == __uuidof(ISpTTSEngine)) *out = static_cast<ISpTTSEngine*>(this);
        else if (iid == __uuidof(ISpObjectWithToken)) *out = static_cast<ISpObjectWithToken*>(this);
        else return E_NOINTERFACE;
        AddRef(); return S_OK;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return ++refs_; }
    STDMETHODIMP_(ULONG) Release() override { ULONG n = --refs_; if (!n) delete this; return n; }
    STDMETHODIMP SetObjectToken(ISpObjectToken* token) override {
        if (!token) return E_POINTER;
        if (token_) token_->Release();
        token_ = token; token_->AddRef(); return S_OK;
    }
    STDMETHODIMP GetObjectToken(ISpObjectToken** out) override {
        if (!out) return E_POINTER;
        *out = token_; if (token_) token_->AddRef();
        return token_ ? S_OK : E_FAIL;
    }
    STDMETHODIMP GetOutputFormat(const GUID*, const WAVEFORMATEX* target, GUID* id, WAVEFORMATEX** out) override {
        if (!out) return E_POINTER;
        auto* fmt = static_cast<WAVEFORMATEX*>(CoTaskMemAlloc(sizeof(WAVEFORMATEX)));
        if (!fmt) return E_OUTOFMEMORY;
        *fmt = {}; fmt->wFormatTag = WAVE_FORMAT_PCM; fmt->nChannels = 1;
        fmt->nSamplesPerSec = 24000; fmt->wBitsPerSample = 16;
        fmt->nBlockAlign = 2; fmt->nAvgBytesPerSec = 48000;
        if (id) *id = SPDFID_WaveFormatEx;
        *out = fmt; return S_OK;
    }
    STDMETHODIMP Speak(DWORD, REFGUID formatId, const WAVEFORMATEX* outputFormat, const SPVTEXTFRAG* fragments,
                       ISpTTSEngineSite* site) override {
        if (!site) return E_POINTER;
        wchar_t entryEventName[256]{};
        DWORD entryNameLength = GetEnvironmentVariableW(L"POCKETTTS_SAPI_ENGINE_ENTRY_EVENT",
                                                          entryEventName, static_cast<DWORD>(std::size(entryEventName)));
        if (entryNameLength > 0 && entryNameLength < std::size(entryEventName)) {
            HANDLE entryEvent = OpenEventW(EVENT_MODIFY_STATE, FALSE, entryEventName);
            if (entryEvent) { SetEvent(entryEvent); CloseHandle(entryEvent); }
        }
        wchar_t tracePath[1024]{};
        DWORD tracePathLength = GetEnvironmentVariableW(L"POCKETTTS_SAPI_FRAGMENT_TRACE",
                                                          tracePath, static_cast<DWORD>(std::size(tracePath)));
        if (!tracePathLength) {
            const std::wstring configured = ReadWorkerValue(L"SapiTracePath");
            if (!configured.empty() && configured.size() < std::size(tracePath)) {
                wcscpy_s(tracePath, configured.c_str());
                tracePathLength = static_cast<DWORD>(configured.size());
            }
        }
        if (tracePathLength > 0 && tracePathLength < std::size(tracePath)) {
            std::ofstream trace(Utf8(std::wstring(tracePath)), std::ios::app);
            LPWSTR tokenId = nullptr;
            LPWSTR tokenVoice = nullptr;
            if (token_) {
                token_->GetId(&tokenId);
                token_->GetStringValue(L"VoiceStatePath", &tokenVoice);
            }
            if (trace) trace << "pid=" << GetCurrentProcessId()
                            << " token=" << Utf8(tokenId ? tokenId : L"<none>")
                            << " voice=" << Utf8(tokenVoice ? tokenVoice : L"<none>")
                            << " output_format tag=" << (outputFormat ? outputFormat->wFormatTag : 0)
                            << " channels=" << (outputFormat ? outputFormat->nChannels : 0)
                            << " rate=" << (outputFormat ? outputFormat->nSamplesPerSec : 0)
                            << " bits=" << (outputFormat ? outputFormat->wBitsPerSample : 0)
                            << " format_id=" << (formatId == SPDFID_WaveFormatEx) << "\n";
            if (tokenId) CoTaskMemFree(tokenId);
            if (tokenVoice) CoTaskMemFree(tokenVoice);
            for (auto* fragment = fragments; trace && fragment; fragment = fragment->pNext)
                trace << "action=" << static_cast<unsigned>(fragment->State.eAction)
                      << " chars=" << fragment->ulTextLen
                      << " rate_adj=" << fragment->State.RateAdj << "\n";
        }
        wchar_t eventName[256]{};
        DWORD eventNameLength = GetEnvironmentVariableW(L"POCKETTTS_SAPI_FIRST_AUDIO_EVENT",
                                                         eventName, static_cast<DWORD>(std::size(eventName)));
        EventHandle firstAudioEvent(eventNameLength > 0 && eventNameLength < std::size(eventName)
            ? OpenEventW(EVENT_MODIFY_STATE, FALSE, eventName) : nullptr);
        bool firstAudioSignaled = false;
        ULONGLONG eventInterest = 0;
        if (FAILED(site->GetEventInterest(&eventInterest))) eventInterest = 0;
        size_t totalText = 0;
        ULONGLONG audioOffset = 0;
        long currentRate = 0;
        if (FAILED(site->GetRate(&currentRate))) currentRate = 0;
        ULONGLONG tracedPcmBytes = 0;
        unsigned tracedPcmWrites = 0;
        bool tracedPcmAbort = false;
        auto traceLine = [&](const char* label, HRESULT result = S_OK, DWORD actions = 0) {
            if (tracePathLength > 0 && tracePathLength < std::size(tracePath)) {
                std::ofstream trace(Utf8(std::wstring(tracePath)), std::ios::app);
                if (trace) trace << label << " hr=0x" << std::hex << static_cast<unsigned long>(result)
                                << std::dec << " actions=" << actions << " pcm_bytes=" << tracedPcmBytes
                                << " writes=" << tracedPcmWrites << "\n";
            }
        };
        auto pollActions = [&]() -> HRESULT {
            DWORD actions = site->GetActions();
            if (actions & SPVES_ABORT) return S_FALSE;
            if (actions & SPVES_RATE) {
                HRESULT result = site->GetRate(&currentRate);
                if (tracePathLength > 0 && tracePathLength < std::size(tracePath)) {
                    std::ofstream trace(Utf8(std::wstring(tracePath)), std::ios::app);
                    if (trace) trace << "rate_action hr=0x" << std::hex << static_cast<unsigned long>(result)
                                    << std::dec << " rate=" << currentRate << " actions_after=" << site->GetActions() << "\n";
                }
                if (FAILED(result)) return result;
            }
            if (actions & SPVES_VOLUME) {
                USHORT currentVolume = 100;
                HRESULT result = site->GetVolume(&currentVolume);
                if (FAILED(result)) return result;
            }
            return S_OK;
        };
        USHORT volume = 100;
        if (FAILED(site->GetVolume(&volume))) volume = 100;
        const double gain = static_cast<double>(std::min<USHORT>(volume, 100)) / 100.0;
        auto writeBytes = [&](const unsigned char* data, size_t size, bool generatedPcm = false) -> HRESULT {
            size_t offset = 0;
            while (offset < size) {
                HRESULT actionResult = pollActions();
                if (actionResult == S_FALSE) {
                    if (generatedPcm) {
                        tracedPcmAbort = true;
                        if (tracePathLength > 0 && tracePathLength < std::size(tracePath)) {
                            std::ofstream trace(Utf8(std::wstring(tracePath)), std::ios::app);
                            if (trace) trace << "write_abort actions=" << site->GetActions() << " offset=" << offset
                                            << " chunk_bytes=" << size << "\n";
                        }
                    }
                    return S_FALSE;
                }
                if (FAILED(actionResult)) return actionResult;
                ULONG count = static_cast<ULONG>(std::min<size_t>(32768, size - offset));
                // Some SAPI hosts consume the buffer but leave pcbWritten at zero.
                // Seed it to the requested count so a host that does not write the
                // out parameter still advances; a host that reports a partial write
                // can overwrite it with the actual count.
                ULONG done = count;
                HRESULT result = site->Write(data + offset, count, &done);
                if (generatedPcm && tracePathLength > 0 && tracePathLength < std::size(tracePath)) {
                    std::ofstream trace(Utf8(std::wstring(tracePath)), std::ios::app);
                    if (trace) trace << "write_result hr=0x" << std::hex << static_cast<unsigned long>(result)
                                    << std::dec << " requested=" << count << " accepted=" << done
                                    << " actions=" << site->GetActions() << "\n";
                }
                if (FAILED(result)) {
                    if (generatedPcm && tracePathLength > 0 && tracePathLength < std::size(tracePath)) {
                        std::ofstream trace(Utf8(std::wstring(tracePath)), std::ios::app);
                        if (trace) trace << "write_hr=0x" << std::hex << static_cast<unsigned long>(result) << std::dec
                                        << " request_bytes=" << count << "\n";
                    }
                    return result;
                }
                if (!done) done = count;
                if (generatedPcm) { tracedPcmBytes += done; ++tracedPcmWrites; }
                if (generatedPcm && !firstAudioSignaled && firstAudioEvent.h) {
                    SetEvent(firstAudioEvent.h);
                    firstAudioSignaled = true;
                }
                offset += done;
            }
            return S_OK;
        };
        static const unsigned char silence[8192] = {};
        for (auto* f = fragments; f; f = f->pNext) {
            HRESULT actionResult = pollActions();
            if (actionResult == S_FALSE) { traceLine("fragment_abort", S_OK, site->GetActions()); return S_OK; }
            if (FAILED(actionResult)) return actionResult;
            if (f->State.eAction == SPVA_Silence) {
                size_t bytes = static_cast<size_t>(f->State.SilenceMSecs) * 48;
                if (audioOffset + bytes > kMaxAudioBytes)
                    return HRESULT_FROM_WIN32(ERROR_BUFFER_OVERFLOW);
                while (bytes) {
                    size_t count = std::min(bytes, sizeof(silence));
                    HRESULT hr = writeBytes(silence, count);
                    if (hr == S_FALSE) return S_OK;
                    if (FAILED(hr)) return hr;
                    bytes -= count;
                    audioOffset += count;
                }
                continue;
            }
            if (f->State.eAction != SPVA_Speak || !f->pTextStart || !f->ulTextLen) continue;
            if (f->ulTextLen > kMaxTextChars - totalText)
                return HRESULT_FROM_WIN32(ERROR_BUFFER_OVERFLOW);
            totalText += f->ulTextLen;
            std::wstring text(f->pTextStart, f->ulTextLen);
            std::vector<unsigned char> wav;
            bool aborted = false;
            std::wstring voiceStatePath, promptSlowPath, promptNormalPath, promptFastPath, modelLanguage;
            if (token_) {
                auto readTokenValue = [&](const wchar_t* name, std::wstring& target) {
                    LPWSTR value = nullptr;
                    if (SUCCEEDED(token_->GetStringValue(name, &value)) && value) {
                        target = value;
                        CoTaskMemFree(value);
                    }
                };
                readTokenValue(L"VoiceStatePath", voiceStatePath);
                readTokenValue(L"VoicePromptSlowPath", promptSlowPath);
                readTokenValue(L"VoicePromptNormalPath", promptNormalPath);
                readTokenValue(L"VoicePromptFastPath", promptFastPath);
                readTokenValue(L"ModelLanguage", modelLanguage);
            }
            if (!IsSupportedModelLanguage(modelLanguage)) modelLanguage = GetModelLanguage();
            const long fragmentRate = ClampSapiRate(currentRate + f->State.RateAdj);
            // The exported state is already resident as a reusable voice representation and
            // avoids encoding a raw WAV prompt on every default-rate utterance. Keep the
            // uploaded audio prompts only for the slow/fast rate bands that need their pace.
            std::wstring selectedVoicePath = voiceStatePath;
            if (!promptSlowPath.empty() && !promptNormalPath.empty() && !promptFastPath.empty()) {
                switch (RateToPaceVariant(fragmentRate)) {
                case PaceVariant::Slow: selectedVoicePath = promptSlowPath; break;
                case PaceVariant::Normal: selectedVoicePath = voiceStatePath; break;
                case PaceVariant::Fast: selectedVoicePath = promptFastPath; break;
                }
            }
            // Voice Manager can pre-encode a pace prompt beside its WAV. Prefer
            // that compact state so navigation does not re-encode audio on each
            // request. Older voices continue to use their WAV prompt.
            if (selectedVoicePath.size() >= 4 &&
                _wcsicmp(selectedVoicePath.c_str() + selectedVoicePath.size() - 4, L".wav") == 0) {
                std::wstring cached = selectedVoicePath.substr(0, selectedVoicePath.size() - 4) + L".safetensors";
                if (GetFileAttributesW(cached.c_str()) != INVALID_FILE_ATTRIBUTES)
                    selectedVoicePath = std::move(cached);
            }
            const std::wstring spoken = SpokenText(text);
            const std::wstring replayKey = ReplayKey(spoken, selectedVoicePath, modelLanguage);
            const bool cacheHit = CachedReplay(replayKey, wav);
            HRESULT hr = cacheHit ? S_OK : FetchWav(spoken, selectedVoicePath, modelLanguage, site, wav, aborted);
            if (tracePathLength > 0 && tracePathLength < std::size(tracePath)) {
                std::ofstream trace(Utf8(std::wstring(tracePath)), std::ios::app);
                if (trace) trace << "fetch_hr=0x" << std::hex << static_cast<unsigned long>(hr)
                                << std::dec << " wav_bytes=" << wav.size() << " aborted=" << aborted
                                << " cache_hit=" << cacheHit << "\n";
            }
            if (FAILED(hr)) return hr;
            if (aborted) return S_OK;
            actionResult = pollActions();
            if (actionResult == S_FALSE) return S_OK;
            if (FAILED(actionResult)) return actionResult;
            size_t begin = 0, length = 0;
            hr = PcmRange(wav, begin, length);
            if (FAILED(hr)) {
                if (tracePathLength > 0 && tracePathLength < std::size(tracePath)) {
                    std::ofstream trace(Utf8(std::wstring(tracePath)), std::ios::app);
                    if (trace) trace << "pcm_parse_hr=0x" << std::hex << static_cast<unsigned long>(hr) << std::dec << "\n";
                }
                return hr;
            }
            if (!cacheHit) RememberReplay(replayKey, wav);
            const size_t trimmedLead = TrimGeneratedLeadingSilence(wav, begin, length);
            begin += trimmedLead;
            length -= trimmedLead;
            if (tracePathLength > 0 && tracePathLength < std::size(tracePath)) {
                std::ofstream trace(Utf8(std::wstring(tracePath)), std::ios::app);
                if (trace) trace << "pcm_start=" << begin << " pcm_bytes=" << length
                                << " trimmed_lead_ms=" << trimmedLead / 48
                                << " sapi_rate=" << fragmentRate
                                << "voice_prompt=" << Utf8(selectedVoicePath) << "\n";
            }
            if (audioOffset + length > kMaxAudioBytes)
                return HRESULT_FROM_WIN32(ERROR_BUFFER_OVERFLOW);
            if (gain < 1.0) {
                for (size_t offset=0; offset+1<length; offset+=2) {
                    int16_t sample = static_cast<int16_t>(
                        static_cast<uint16_t>(wav[begin+offset]) |
                        (static_cast<uint16_t>(wav[begin+offset+1])<<8));
                    sample = static_cast<int16_t>(sample*gain);
                    wav[begin+offset]=static_cast<unsigned char>(sample&0xff);
                    wav[begin+offset+1]=static_cast<unsigned char>((sample>>8)&0xff);
                }
            }
            if (eventInterest & SPFEI(SPEI_SENTENCE_BOUNDARY)) {
                SPEVENT sentence{};
                sentence.eEventId=SPEI_SENTENCE_BOUNDARY;
                sentence.elParamType=SPET_LPARAM_IS_UNDEFINED;
                sentence.ullAudioStreamOffset=audioOffset;
                sentence.wParam=text.size();
                sentence.lParam=f->ulTextSrcOffset;
                hr=site->AddEvents(&sentence,1);
                traceLine("sentence_event", hr, site->GetActions());
                if (FAILED(hr)) {
                    if (tracePathLength > 0 && tracePathLength < std::size(tracePath)) {
                        std::ofstream trace(Utf8(std::wstring(tracePath)), std::ios::app);
                        if (trace) trace << "sentence_event_hr=0x" << std::hex << static_cast<unsigned long>(hr) << std::dec << "\n";
                    }
                    return hr;
                }
            }
            size_t written=0;
            for (size_t i=0; (eventInterest & SPFEI(SPEI_WORD_BOUNDARY)) && i<text.size();) {
                if (!std::iswalnum(text[i])) { ++i; continue; }
                size_t wordStart=i++;
                while (i<text.size() && std::iswalnum(text[i])) ++i;
                size_t target=((length*wordStart/text.size())&~size_t(1));
                if (target>written) {
                    hr=writeBytes(wav.data()+begin+written,target-written,true);
                    if (hr==S_FALSE) return S_OK;
                    if (FAILED(hr)) return hr;
                    written=target;
                }
                if (eventInterest & SPFEI(SPEI_WORD_BOUNDARY)) {
                    SPEVENT e{};
                    e.eEventId=SPEI_WORD_BOUNDARY;
                    e.elParamType=SPET_LPARAM_IS_UNDEFINED;
                    e.ullAudioStreamOffset=audioOffset+written;
                    e.wParam=i-wordStart;
                    e.lParam=f->ulTextSrcOffset+static_cast<ULONG>(wordStart);
                    hr=site->AddEvents(&e,1);
                    traceLine("word_event", hr, site->GetActions());
                    if (FAILED(hr)) {
                        if (tracePathLength > 0 && tracePathLength < std::size(tracePath)) {
                            std::ofstream trace(Utf8(std::wstring(tracePath)), std::ios::app);
                            if (trace) trace << "word_event_hr=0x" << std::hex << static_cast<unsigned long>(hr) << std::dec << "\n";
                        }
                        return hr;
                    }
                }
            }
            if (written<length) {
                hr=writeBytes(wav.data()+begin+written,length-written,true);
                if (hr==S_FALSE) return S_OK;
                if (FAILED(hr)) return hr;
            }
            audioOffset+=length;
            traceLine("fragment_audio_done", S_OK, site->GetActions());
        }
        if (tracePathLength > 0 && tracePathLength < std::size(tracePath)) {
            std::ofstream trace(Utf8(std::wstring(tracePath)), std::ios::app);
            if (trace) trace << "pcm_write_bytes=" << tracedPcmBytes << " pcm_write_calls=" << tracedPcmWrites
                            << " abort=" << tracedPcmAbort << " final_actions=" << site->GetActions() << "\n";
        }
        return S_OK;
    }
};

class Factory final : public IClassFactory {
    std::atomic<ULONG> refs_{1};
public:
    STDMETHODIMP QueryInterface(REFIID iid, void** out) override {
        if (!out) return E_POINTER; *out = nullptr;
        if (iid != IID_IUnknown && iid != IID_IClassFactory) return E_NOINTERFACE;
        *out = static_cast<IClassFactory*>(this); AddRef(); return S_OK;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return ++refs_; }
    STDMETHODIMP_(ULONG) Release() override { ULONG n = --refs_; if (!n) delete this; return n; }
    STDMETHODIMP CreateInstance(IUnknown* outer, REFIID iid, void** out) override {
        if (outer) return CLASS_E_NOAGGREGATION;
        auto* engine = new (std::nothrow) Engine();
        if (!engine) return E_OUTOFMEMORY;
        HRESULT hr = engine->QueryInterface(iid, out); engine->Release(); return hr;
    }
    STDMETHODIMP LockServer(BOOL lock) override { if (lock) ++gLocks; else --gLocks; return S_OK; }
};
}

extern "C" HRESULT __stdcall DllGetClassObject(REFCLSID clsid, REFIID iid, void** out) {
    if (clsid != kClsid) return CLASS_E_CLASSNOTAVAILABLE;
    auto* factory = new (std::nothrow) Factory();
    if (!factory) return E_OUTOFMEMORY;
    HRESULT hr = factory->QueryInterface(iid, out); factory->Release(); return hr;
}
extern "C" HRESULT __stdcall DllCanUnloadNow() { return (!gObjects && !gLocks) ? S_OK : S_FALSE; }
