#include "CubismNativeBridge.h"

#include "CubismAllocator.hpp"
#include "CubismFramework.hpp"
#include "Model/CubismMoc.hpp"
#include "Live2DCubismCore.h"

#include <algorithm>
#include <cstring>
#include <fstream>
#include <mutex>
#include <string>
#include <vector>

namespace {

CubismAllocator gAllocator;
std::mutex gMutex;
bool gFrameworkStarted = false;

void CopyError(char* destination, const std::string& message)
{
    if (!destination)
    {
        return;
    }

    std::strncpy(destination, message.c_str(), 511);
    destination[511] = '\0';
}

bool EnsureFrameworkStarted(std::string& error)
{
    if (gFrameworkStarted)
    {
        return true;
    }

    Live2D::Cubism::Framework::CubismFramework::Option option;
    std::memset(&option, 0, sizeof(option));
    option.LoggingLevel = Live2D::Cubism::Framework::CubismFramework::Option::LogLevel_Off;

    if (!Live2D::Cubism::Framework::CubismFramework::StartUp(&gAllocator, &option))
    {
        error = "CubismFramework::StartUp failed";
        return false;
    }

    Live2D::Cubism::Framework::CubismFramework::Initialize();
    gFrameworkStarted = true;
    return true;
}

bool ReadFileBytes(const char* path, std::vector<Live2D::Cubism::Framework::csmByte>& outBytes, std::string& error)
{
    std::ifstream file(path, std::ios::binary | std::ios::ate);

    if (!file)
    {
        error = "Failed to open moc3 file";
        return false;
    }

    const std::streamsize size = file.tellg();

    if (size <= 0)
    {
        error = "moc3 file is empty";
        return false;
    }

    file.seekg(0, std::ios::beg);
    outBytes.resize(static_cast<size_t>(size));

    if (!file.read(reinterpret_cast<char*>(outBytes.data()), size))
    {
        error = "Failed to read moc3 file";
        return false;
    }

    return true;
}

} // namespace

bool CubismNativeCopyDiagnostics(const char* mocPath, CubismNativeDiagnostics* outDiagnostics)
{
    if (!outDiagnostics)
    {
        return false;
    }

    std::memset(outDiagnostics, 0, sizeof(*outDiagnostics));

    if (!mocPath || mocPath[0] == '\0')
    {
        CopyError(outDiagnostics->errorMessage, "mocPath is empty");
        return false;
    }

    std::lock_guard<std::mutex> lock(gMutex);
    std::string error;

    if (!EnsureFrameworkStarted(error))
    {
        CopyError(outDiagnostics->errorMessage, error);
        return false;
    }

    outDiagnostics->frameworkStarted = Live2D::Cubism::Framework::CubismFramework::IsStarted();
    outDiagnostics->frameworkInitialized = Live2D::Cubism::Framework::CubismFramework::IsInitialized();
    outDiagnostics->coreVersion = Live2D::Cubism::Core::csmGetVersion();
    outDiagnostics->latestMocVersion = static_cast<uint32_t>(Live2D::Cubism::Framework::CubismMoc::GetLatestMocVersion());

    std::vector<Live2D::Cubism::Framework::csmByte> mocBytes;

    if (!ReadFileBytes(mocPath, mocBytes, error))
    {
        CopyError(outDiagnostics->errorMessage, error);
        return false;
    }

    outDiagnostics->mocVersion = static_cast<uint32_t>(
        Live2D::Cubism::Framework::CubismMoc::GetMocVersionFromBuffer(
            mocBytes.data(),
            static_cast<Live2D::Cubism::Framework::csmSizeInt>(mocBytes.size())
        )
    );

    outDiagnostics->mocConsistent = Live2D::Cubism::Framework::CubismMoc::HasMocConsistencyFromUnrevivedMoc(
        mocBytes.data(),
        static_cast<Live2D::Cubism::Framework::csmSizeInt>(mocBytes.size())
    );

    Live2D::Cubism::Framework::CubismMoc* moc = Live2D::Cubism::Framework::CubismMoc::Create(
        mocBytes.data(),
        static_cast<Live2D::Cubism::Framework::csmSizeInt>(mocBytes.size())
    );

    if (!moc)
    {
        CopyError(outDiagnostics->errorMessage, "CubismMoc::Create failed");
        return false;
    }

    outDiagnostics->mocLoaded = true;
    outDiagnostics->mocVersion = static_cast<uint32_t>(moc->GetMocVersion());
    Live2D::Cubism::Framework::CubismMoc::Delete(moc);
    return true;
}

void CubismNativeShutdown(void)
{
    std::lock_guard<std::mutex> lock(gMutex);

    if (!gFrameworkStarted)
    {
        return;
    }

    if (Live2D::Cubism::Framework::CubismFramework::IsInitialized())
    {
        Live2D::Cubism::Framework::CubismFramework::Dispose();
    }

    Live2D::Cubism::Framework::CubismFramework::CleanUp();
    gFrameworkStarted = false;
}
