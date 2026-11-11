#define NOMINMAX
#include <windows.h>
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <cwchar>
#include <fstream>
#include <iostream>
#include <iterator>
#include <string>
#include <vector>
#include "soundtouch_adapter.h"

static uint32_t Read32(const std::vector<unsigned char>& b, size_t p) {
    return static_cast<uint32_t>(b[p]) | (static_cast<uint32_t>(b[p+1]) << 8) |
           (static_cast<uint32_t>(b[p+2]) << 16) | (static_cast<uint32_t>(b[p+3]) << 24);
}
static void Write32(std::vector<unsigned char>& b, size_t p, uint32_t v) {
    for (int i=0; i<4; ++i) b[p+i] = static_cast<unsigned char>((v >> (8*i)) & 0xff);
}

static std::vector<int16_t> ResampleMono24k(const std::vector<int16_t>& input, uint32_t sourceRate) {
    constexpr uint32_t targetRate = 24000;
    constexpr int radius = 20;
    constexpr double pi = 3.14159265358979323846;
    if (sourceRate == targetRate) return input;
    const size_t outputCount = static_cast<size_t>(
        (static_cast<uint64_t>(input.size()) * targetRate + sourceRate / 2) / sourceRate);
    std::vector<int16_t> output(outputCount);
    const double cutoff = std::min(1.0, static_cast<double>(targetRate) / sourceRate) * 0.94;
    for (size_t i = 0; i < outputCount; ++i) {
        const double position = static_cast<double>(i) * sourceRate / targetRate;
        const int64_t center = static_cast<int64_t>(position);
        double sum = 0.0, weightSum = 0.0;
        for (int64_t frame = center - radius + 1; frame <= center + radius; ++frame) {
            if (frame < 0 || static_cast<size_t>(frame) >= input.size()) continue;
            const double distance = position - static_cast<double>(frame);
            const double windowPosition = distance / radius;
            if (std::abs(windowPosition) >= 1.0) continue;
            const double x = cutoff * distance;
            const double sinc = std::abs(x) < 1e-12 ? 1.0 : std::sin(pi * x) / (pi * x);
            const double window = 0.5 + 0.5 * std::cos(pi * windowPosition);
            const double weight = cutoff * sinc * window;
            sum += input[static_cast<size_t>(frame)] * weight;
            weightSum += weight;
        }
        const double sample = weightSum == 0.0 ? 0.0 : sum / weightSum;
        output[i] = static_cast<int16_t>(std::clamp(sample, -32768.0, 32767.0));
    }
    return output;
}

int wmain(int argc, wchar_t** argv) {
    if (argc != 4 && argc != 5) {
        std::wcerr << L"Usage: pocket_prompt_rate.exe input.wav output.wav speed(0.70-1.40) [max-seconds]\n";
        return 2;
    }
    wchar_t* end = nullptr;
    const double speed = wcstod(argv[3], &end);
    if (!end || *end || speed < 0.70 || speed > 1.40) {
        std::wcerr << L"Speed must be between 0.70 and 1.40.\n";
        return 2;
    }
    double maxSeconds = 0.0;
    if (argc == 5) {
        maxSeconds = wcstod(argv[4], &end);
        if (!end || *end || maxSeconds < 3.0 || maxSeconds > 30.0) {
            std::wcerr << L"Maximum excerpt must be between 3 and 30 seconds.\n";
            return 2;
        }
    }
    std::ifstream in(argv[1], std::ios::binary);
    if (!in) { std::wcerr << L"Cannot open input WAV.\n"; return 1; }
    std::vector<unsigned char> wav((std::istreambuf_iterator<char>(in)), {});
    if (wav.size() < 44 || memcmp(wav.data(), "RIFF", 4) || memcmp(wav.data()+8, "WAVE", 4)) {
        std::wcerr << L"Input must be a RIFF/WAVE file.\n"; return 1;
    }
    size_t fmt=0, data=0, dataSizePos=0;
    for (size_t p=12; p+8<=wav.size();) {
        const uint32_t n=Read32(wav,p+4);
        if (n > wav.size()-p-8) { std::wcerr << L"Invalid WAV chunk.\n"; return 1; }
        if (!memcmp(wav.data()+p,"fmt ",4)) fmt=p+8;
        if (!memcmp(wav.data()+p,"data",4)) { data=p+8; dataSizePos=p+4; break; }
        p += 8 + n + (n & 1);
    }
    if (!fmt || !data || fmt+16>wav.size() || dataSizePos+4>wav.size() ||
        wav[fmt]!=1 || wav[fmt+1]!=0 || (wav[fmt+2]!=1 && wav[fmt+2]!=2) || wav[fmt+3]!=0 ||
        wav[fmt+14]!=16 || wav[fmt+15]!=0) {
        std::wcerr << L"Input WAV must be 16-bit PCM with one or two channels.\n"; return 1;
    }
    const uint16_t channels=static_cast<uint16_t>(wav[fmt+2] | (wav[fmt+3]<<8));
    const uint32_t sampleRate=Read32(wav,fmt+4);
    const uint16_t blockAlign=static_cast<uint16_t>(wav[fmt+12] | (wav[fmt+13]<<8));
    if(sampleRate<8000 || sampleRate>96000 || blockAlign!=channels*2) {
        std::wcerr << L"Input WAV sample rate or block alignment is unsupported.\n"; return 1;
    }
    const size_t inputBytes=Read32(wav,dataSizePos);
    if (inputBytes < blockAlign*2 || data+inputBytes>wav.size() || (inputBytes % blockAlign)) {
        std::wcerr << L"WAV audio data is empty, truncated, or too short.\n"; return 1;
    }
    const size_t frameCount=inputBytes/blockAlign;
    std::vector<int16_t> samples(frameCount);
    for(size_t frame=0;frame<frameCount;++frame) {
        int32_t mixed=0;
        for(size_t channel=0;channel<channels;++channel) {
            const size_t p=data+frame*blockAlign+channel*2;
            mixed+=static_cast<int16_t>(static_cast<uint16_t>(wav[p]) |
                                       (static_cast<uint16_t>(wav[p+1])<<8));
        }
        samples[frame]=static_cast<int16_t>(mixed/channels);
    }
    if (maxSeconds > 0.0) {
        const size_t maxFrames = static_cast<size_t>(maxSeconds * sampleRate);
        if (samples.size() > maxFrames) samples.resize(maxFrames);
    }
    std::vector<int16_t> stretched;
    int16_t* processed=nullptr;
    size_t processedSamples=0;
    const int processResult=PocketTempoPcm16(samples.data(),samples.size(),sampleRate,speed,&processed,&processedSamples);
    if (processResult || !processed || !processedSamples) { std::wcerr << L"Could not time-stretch this prompt.\n"; return 1; }
    try { stretched.assign(processed,processed+processedSamples); }
    catch (...) { PocketTempoFree(processed); std::wcerr << L"Not enough memory to process this prompt.\n"; return 1; }
    PocketTempoFree(processed);
    std::vector<int16_t> normalized;
    try { normalized = ResampleMono24k(stretched, sampleRate); }
    catch (...) { std::wcerr << L"Could not resample prompt to 24 kHz mono.\n"; return 1; }
    const size_t outputBytes=normalized.size()*2;
    if (outputBytes > 50*1024*1024 || wav.size()-inputBytes+outputBytes > UINT32_MAX) {
        std::wcerr << L"Stretched WAV exceeds the supported size.\n"; return 1;
    }
    std::vector<unsigned char> out;
    out.reserve(wav.size()-inputBytes+outputBytes);
    out.insert(out.end(),wav.begin(),wav.begin()+data);
    for (const int16_t sample:normalized) {
        const uint16_t v=static_cast<uint16_t>(sample);
        out.push_back(static_cast<unsigned char>(v&0xff));
        out.push_back(static_cast<unsigned char>(v>>8));
    }
    out.insert(out.end(),wav.begin()+data+inputBytes,wav.end());
    Write32(out,4,static_cast<uint32_t>(out.size()-8));
    Write32(out,dataSizePos,static_cast<uint32_t>(outputBytes));
    out[fmt+2]=1; out[fmt+3]=0;
    Write32(out,fmt+4,24000);
    Write32(out,fmt+8,24000*2);
    out[fmt+12]=2; out[fmt+13]=0;
    std::ofstream output(argv[2],std::ios::binary|std::ios::trunc);
    if (!output || !output.write(reinterpret_cast<const char*>(out.data()),static_cast<std::streamsize>(out.size()))) {
        std::wcerr << L"Could not write stretched WAV.\n"; return 1;
    }
    std::wcout << L"WAV prompt prepared at " << speed << L"x playback pace.\n";
    return 0;
}
