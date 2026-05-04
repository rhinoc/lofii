#include "CubismAllocator.hpp"

#include <cstdlib>

using namespace Csm;

void* CubismAllocator::Allocate(const csmSizeType size)
{
    return std::malloc(size);
}

void CubismAllocator::Deallocate(void* memory)
{
    std::free(memory);
}

void* CubismAllocator::AllocateAligned(const csmSizeType size, const csmUint32 alignment)
{
    size_t offset = alignment - 1 + sizeof(void*);
    void* allocation = Allocate(size + static_cast<csmUint32>(offset));
    size_t alignedAddress = reinterpret_cast<size_t>(allocation) + sizeof(void*);
    size_t shift = alignedAddress % alignment;

    if (shift)
    {
        alignedAddress += (alignment - shift);
    }

    void** preamble = reinterpret_cast<void**>(alignedAddress);
    preamble[-1] = allocation;
    return reinterpret_cast<void*>(alignedAddress);
}

void CubismAllocator::DeallocateAligned(void* alignedMemory)
{
    void** preamble = static_cast<void**>(alignedMemory);
    Deallocate(preamble[-1]);
}
