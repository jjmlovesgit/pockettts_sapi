#include <algorithm>
#include <cstdint>
#include <new>
#include <vector>
#include "SoundTouch.h"

extern "C" __declspec(dllexport) int __cdecl PocketTempoPcm16(
    const int16_t* input, size_t inputSamples, uint32_t sampleRate, double tempo,
    int16_t** output, size_t* outputSamples) {
    if (!input || inputSamples < 2 || sampleRate < 8000 || sampleRate > 96000 ||
        tempo < 0.70 || tempo > 1.40 || !output || !outputSamples) return 1;
    *output = nullptr;
    *outputSamples = 0;
    try {
        std::vector<float> floatInput(input, input + inputSamples);
        soundtouch::SoundTouch processor;
        processor.setSampleRate(sampleRate);
        processor.setChannels(1);
        processor.setTempo(tempo);
        processor.putSamples(floatInput.data(), static_cast<uint>(floatInput.size()));
        processor.flush();
        std::vector<float> block(8192);
        std::vector<int16_t> stretched;
        for (;;) {
            const uint count=processor.receiveSamples(block.data(), static_cast<uint>(block.size()));
            if (!count) break;
            for (uint i=0;i<count;++i)
                stretched.push_back(static_cast<int16_t>(std::clamp(block[i],-32768.0f,32767.0f)));
        }
        if (stretched.empty()) return 2;
        auto* memory = new(std::nothrow) int16_t[stretched.size()];
        if (!memory) return 3;
        std::copy(stretched.begin(),stretched.end(),memory);
        *output=memory;
        *outputSamples=stretched.size();
        return 0;
    } catch (...) { return 4; }
}

extern "C" __declspec(dllexport) void __cdecl PocketTempoFree(int16_t* samples) {
    delete[] samples;
}
