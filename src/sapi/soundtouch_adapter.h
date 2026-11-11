#pragma once
#include <cstddef>
#include <cstdint>

extern "C" __declspec(dllimport) int __cdecl PocketTempoPcm16(
    const int16_t* input, size_t inputSamples, uint32_t sampleRate, double tempo,
    int16_t** output, size_t* outputSamples);
extern "C" __declspec(dllimport) void __cdecl PocketTempoFree(int16_t* samples);
