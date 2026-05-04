#pragma once

#include <stdbool.h>
#include <stdint.h>

#if __OBJC__
#import "CubismNativeMetalView.h"
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct CubismNativeDiagnostics {
    bool frameworkStarted;
    bool frameworkInitialized;
    bool mocLoaded;
    bool mocConsistent;
    uint32_t coreVersion;
    uint32_t latestMocVersion;
    uint32_t mocVersion;
    char errorMessage[512];
} CubismNativeDiagnostics;

bool CubismNativeCopyDiagnostics(const char *mocPath, CubismNativeDiagnostics *outDiagnostics);
void CubismNativeShutdown(void);

#ifdef __cplusplus
}
#endif

#if defined(__OBJC__)
#import "CubismNativeMetalView.h"
#endif
