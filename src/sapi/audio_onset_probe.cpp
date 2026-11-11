#include <windows.h>
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <ksmedia.h>
#include <functiondiscoverykeys_devpkey.h>
#include <algorithm>
#include <cstdio>
#include <chrono>
#include <thread>
#include <cmath>

static long long nowMs() {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::system_clock::now().time_since_epoch()).count();
}

int wmain() {
    if (FAILED(CoInitializeEx(nullptr, COINIT_MULTITHREADED))) return 1;
    IMMDeviceEnumerator* enumerator = nullptr;
    IMMDevice* device = nullptr;
    IAudioClient* client = nullptr;
    IAudioCaptureClient* capture = nullptr;
    WAVEFORMATEX* format = nullptr;
    HRESULT hr = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
        __uuidof(IMMDeviceEnumerator), reinterpret_cast<void**>(&enumerator));
    if (SUCCEEDED(hr)) hr = enumerator->GetDefaultAudioEndpoint(eRender, eConsole, &device);
    if (SUCCEEDED(hr)) hr = device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
        reinterpret_cast<void**>(&client));
    if (SUCCEEDED(hr)) hr = client->GetMixFormat(&format);
    if (SUCCEEDED(hr)) hr = client->Initialize(AUDCLNT_SHAREMODE_SHARED,
        AUDCLNT_STREAMFLAGS_LOOPBACK, 0, 0, format, nullptr);
    if (SUCCEEDED(hr)) hr = client->GetService(__uuidof(IAudioCaptureClient),
        reinterpret_cast<void**>(&capture));
    if (SUCCEEDED(hr)) hr = client->Start();
    if (FAILED(hr)) { std::printf("audio_probe_error=0x%08lx\n", static_cast<unsigned long>(hr)); return 2; }
    const bool isFloat = format->wFormatTag == WAVE_FORMAT_IEEE_FLOAT ||
        (format->wFormatTag == WAVE_FORMAT_EXTENSIBLE &&
         reinterpret_cast<WAVEFORMATEXTENSIBLE*>(format)->SubFormat == KSDATAFORMAT_SUBTYPE_IEEE_FLOAT);
    std::printf("ready_epoch_ms=%lld channels=%u bits=%u float=%d\n", nowMs(),
        format->nChannels, format->wBitsPerSample, isFloat ? 1 : 0);
    std::fflush(stdout);
    long long lastSound = 0;
    bool sounding = false;
    const long long end = nowMs() + 90000;
    while (nowMs() < end) {
        UINT32 packet = 0;
        while (SUCCEEDED(capture->GetNextPacketSize(&packet)) && packet) {
            BYTE* data = nullptr;
            UINT32 frames = 0;
            DWORD flags = 0;
            if (FAILED(capture->GetBuffer(&data, &frames, &flags, nullptr, nullptr))) break;
            double peak = 0;
            if (!(flags & AUDCLNT_BUFFERFLAGS_SILENT) && data) {
                const size_t count = static_cast<size_t>(frames) * format->nChannels;
                if (isFloat && format->wBitsPerSample == 32) {
                    const float* samples = reinterpret_cast<const float*>(data);
                    for (size_t i = 0; i < count; ++i) peak = (std::max)(peak, static_cast<double>(std::fabs(samples[i])));
                } else if (format->wBitsPerSample == 16) {
                    const short* samples = reinterpret_cast<const short*>(data);
                    for (size_t i = 0; i < count; ++i) peak = (std::max)(peak, std::fabs(samples[i] / 32768.0));
                }
            }
            const long long stamp = nowMs();
            if (peak > 0.01) {
                if (!sounding && stamp - lastSound > 300) {
                    std::printf("onset_epoch_ms=%lld peak=%.3f\n", stamp, peak);
                    std::fflush(stdout);
                }
                lastSound = stamp;
                sounding = true;
            } else if (stamp - lastSound > 300) sounding = false;
            capture->ReleaseBuffer(frames);
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(5));
    }
    client->Stop();
    CoTaskMemFree(format);
    capture->Release(); client->Release(); device->Release(); enumerator->Release();
    CoUninitialize();
    return 0;
}
