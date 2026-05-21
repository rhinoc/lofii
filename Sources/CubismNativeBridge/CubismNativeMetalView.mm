#import "CubismNativeMetalView.h"

#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <QuartzCore/QuartzCore.h>

#include "CubismAllocator.hpp"
#include "CubismFramework.hpp"
#include "Effect/CubismEyeBlink.hpp"
#include "Id/CubismIdManager.hpp"
#include "CubismModelSettingJson.hpp"
#include "Math/CubismMatrix44.hpp"
#include "Math/CubismModelMatrix.hpp"
#include "Model/CubismModel.hpp"
#include "Model/CubismUserModel.hpp"
#include "Rendering/Metal/CubismRenderer_Metal.hpp"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <memory>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

using namespace Live2D::Cubism::Framework;

namespace {

CubismAllocator gCubismAllocator;
bool gCubismFrameworkStarted = false;

bool ReadFileBytes(const std::string& path, std::vector<csmByte>& outBytes)
{
    std::ifstream file(path, std::ios::binary | std::ios::ate);

    if (!file)
    {
        return false;
    }

    const std::streamsize size = file.tellg();

    if (size <= 0)
    {
        return false;
    }

    file.seekg(0, std::ios::beg);
    outBytes.resize(static_cast<size_t>(size));
    return static_cast<bool>(file.read(reinterpret_cast<char*>(outBytes.data()), size));
}

bool EnsureCubismFramework()
{
    if (gCubismFrameworkStarted)
    {
        return true;
    }

    CubismFramework::Option option;
    std::memset(&option, 0, sizeof(option));
    option.LoggingLevel = CubismFramework::Option::LogLevel_Off;

    if (!CubismFramework::StartUp(&gCubismAllocator, &option))
    {
        return false;
    }

    CubismFramework::Initialize();
    gCubismFrameworkStarted = true;
    return true;
}

/// App sends 0/1 for these; map into each model’s actual min/max so non–0–1 ranges still react.
bool IsBongoBinaryStyleParameterId(const std::string& parameterId)
{
    return parameterId == "CatParamLeftHandDown"
        || parameterId == "CatParamRightHandDown"
        || parameterId == "ParamMouseLeftDown"
        || parameterId == "ParamMouseRightDown";
}

csmFloat32 ResolveBongoBinaryParameterValue(CubismModel* model, csmInt32 index, csmFloat32 normalized01)
{
    if (model == nullptr || index < 0)
    {
        return normalized01;
    }

    const csmFloat32 minV = model->GetParameterMinimumValue(index);
    const csmFloat32 maxV = model->GetParameterMaximumValue(index);
    const csmFloat32 lo = std::min(minV, maxV);
    const csmFloat32 hi = std::max(minV, maxV);
    const csmFloat32 span = hi - lo;
    if (span <= 1e-5f)
    {
        return normalized01;
    }

    const csmFloat32 t = std::max(0.0f, std::min(1.0f, normalized01));
    return lo + t * span;
}

class StaticCubismMetalModel final : public CubismUserModel
{
public:
    struct ParameterTarget
    {
        csmInt32 index = -1;
        csmFloat32 target = 0.0f;
        csmFloat32 current = 0.0f;
        bool hasCurrent = false;
        bool smoothing = false;
    };

    ~StaticCubismMetalModel() override
    {
        DeleteRenderer();
        delete _modelSetting;
    }

    bool LoadAssets(const std::string& modelDirectory, const std::string& modelJSONName, csmUint32 width, csmUint32 height)
    {
        _tapMotionBusy = false;
        _modelDirectory = modelDirectory;

        std::vector<csmByte> modelJsonBytes;
        if (!ReadFileBytes(_modelDirectory + "/" + modelJSONName, modelJsonBytes))
        {
            return false;
        }

        delete _modelSetting;
        _modelSetting = new CubismModelSettingJson(
            modelJsonBytes.data(),
            static_cast<csmSizeInt>(modelJsonBytes.size())
        );

        std::vector<csmByte> mocBytes;
        if (!ReadFileBytes(_modelDirectory + "/" + _modelSetting->GetModelFileName(), mocBytes))
        {
            return false;
        }

        LoadModel(mocBytes.data(), static_cast<csmSizeInt>(mocBytes.size()));

        if (GetModel() == nullptr)
        {
            return false;
        }

        _layout.Clear();
        _hasLayout = _modelSetting->GetLayoutMap(_layout);
        RebuildParameterIndexCache();
        GetModel()->SaveParameters();
        CubismEyeBlink::Delete(_eyeBlink);
        _eyeBlink = CubismEyeBlink::Create(_modelSetting);

        DeleteRenderer();
        CreateRenderer(width, height);
        return true;
    }

    void ResizeRenderer(csmUint32 width, csmUint32 height)
    {
        DeleteRenderer();
        CreateRenderer(width, height);
    }

    csmInt32 GetTextureCountValue() const
    {
        return _modelSetting ? _modelSetting->GetTextureCount() : 0;
    }

    std::string GetTexturePath(csmInt32 index) const
    {
        return _modelDirectory + "/" + _modelSetting->GetTextureFileName(index);
    }

    void BindTextureAtIndex(csmInt32 index, id<MTLTexture> texture)
    {
        if (auto* renderer = GetRenderer<Rendering::CubismRenderer_Metal>())
        {
            renderer->BindTexture(index, texture);
            renderer->IsPremultipliedAlpha(false);
        }
    }

    void SetParameterTargets(const std::unordered_map<std::string, double>& parameterValues)
    {
        for (const auto& entry : parameterValues)
        {
            SetParameterTarget(entry.first, static_cast<csmFloat32>(entry.second), IsMouseFollowParameter(entry.first));
        }
    }

    void SetMouseCursor(csmFloat32 xRatio, csmFloat32 yRatio, bool mouseMirror)
    {
        SetMouseParameterTarget("ParamMouseX", xRatio, yRatio, mouseMirror);
        SetMouseParameterTarget("ParamMouseY", xRatio, yRatio, mouseMirror);
        SetMouseParameterTarget("ParamAngleX", xRatio, yRatio, mouseMirror);
        SetMouseParameterTarget("ParamAngleY", xRatio, yRatio, mouseMirror);
        SetMouseParameterTarget("ParamAngleZ", xRatio, yRatio, mouseMirror);
        SetMouseParameterTarget("ParamEyeBallX", xRatio, yRatio, mouseMirror);
        SetMouseParameterTarget("ParamEyeBallY", xRatio, yRatio, mouseMirror);
    }

    /// Picks **one motion at random** from every motion group in `model3.json` (deduped by file path), one-shot (`SetLoop(false)`). Returns `false` while a tap motion is already playing.
    bool TryStartRandomTapMotion()
    {
        if (_tapMotionBusy)
        {
            return false;
        }
        if (GetModel() == nullptr || _modelSetting == nullptr || _motionManager == nullptr)
        {
            return false;
        }

        CubismModelSettingJson* modelSetting = _modelSetting;

        struct MotionPick
        {
            const csmChar* group;
            csmInt32 index;
            std::string path;
        };

        std::vector<MotionPick> pool;
        std::unordered_set<std::string> seenPaths;

        const csmInt32 groupCount = modelSetting->GetMotionGroupCount();
        for (csmInt32 gi = 0; gi < groupCount; ++gi)
        {
            const csmChar* groupName = modelSetting->GetMotionGroupName(gi);
            if (groupName == nullptr)
            {
                continue;
            }
            const csmInt32 motionCount = modelSetting->GetMotionCount(groupName);
            for (csmInt32 mi = 0; mi < motionCount; ++mi)
            {
                const csmChar* rel = modelSetting->GetMotionFileName(groupName, mi);
                if (rel == nullptr || rel[0] == '\0')
                {
                    continue;
                }
                const std::string path = _modelDirectory + "/" + rel;
                if (!seenPaths.insert(path).second)
                {
                    continue;
                }
                pool.push_back(MotionPick{groupName, mi, path});
            }
        }

        if (pool.empty())
        {
            return false;
        }

        const MotionPick& choice = pool[arc4random_uniform(static_cast<uint32_t>(pool.size()))];

        std::vector<csmByte> motionBytes;
        if (!ReadFileBytes(choice.path, motionBytes))
        {
            return false;
        }

        const csmChar* fileName = modelSetting->GetMotionFileName(choice.group, choice.index);
        ACubismMotion* motion = LoadMotion(
            motionBytes.data(),
            static_cast<csmSizeInt>(motionBytes.size()),
            (fileName != nullptr && fileName[0] != '\0') ? fileName : choice.path.c_str(),
            nullptr,
            nullptr,
            modelSetting,
            choice.group,
            choice.index,
            false);

        if (motion == nullptr)
        {
            return false;
        }

        motion->SetLoop(false);
        motion->SetFinishedMotionHandlerAndMotionCustomData(&StaticCubismMetalModel::OnTapMotionFinished, this);

        _tapMotionBusy = true;
        _motionManager->StartMotionPriority(motion, true, 3);
        return true;
    }

    void UpdateFrame(csmFloat32 deltaTimeSeconds)
    {
        CubismModel* model = GetModel();
        if (model == nullptr)
        {
            return;
        }

        model->LoadParameters();

        const csmFloat32 safeDelta = std::max<csmFloat32>(0.0f, std::min<csmFloat32>(deltaTimeSeconds, 1.0f / 15.0f));

        if (_motionManager != nullptr)
        {
            _motionManager->UpdateMotion(model, safeDelta);
        }

        const csmFloat32 mouseAlpha = 1.0f - std::exp(-safeDelta * 34.0f);
        for (auto& entry : _targetParameterValues)
        {
            ParameterTarget& target = entry.second;
            if (target.index < 0)
            {
                continue;
            }

            csmFloat32 value = target.target;
            if (IsBongoBinaryStyleParameterId(entry.first))
            {
                value = ResolveBongoBinaryParameterValue(model, target.index, target.target);
            }
            if (target.smoothing)
            {
                if (!target.hasCurrent)
                {
                    target.current = target.target;
                    target.hasCurrent = true;
                }
                else
                {
                    target.current += (target.target - target.current) * mouseAlpha;
                }
                value = target.current;
            }
            model->SetParameterValue(target.index, value);
        }

        model->SaveParameters();
        if (_eyeBlink != nullptr)
        {
            _eyeBlink->UpdateParameters(model, safeDelta);
        }
        model->Update();
    }

    void Draw(id<MTLCommandBuffer> commandBuffer, MTLRenderPassDescriptor* renderPassDescriptor, const MTLViewport& viewport)
    {
        CubismModel* model = GetModel();
        auto* renderer = GetRenderer<Rendering::CubismRenderer_Metal>();

        if (model == nullptr || renderer == nullptr)
        {
            return;
        }

        renderer->StartFrame(commandBuffer, renderPassDescriptor);

        // Mirror the web bundle's `Live2DSprite`/`ModelRenderer.render` placement
        // exactly. In the web build the model is a Pixi sprite with anchor=(0.5, 1)
        // and position=(stageW/2, stageH), scale=min(stageW/cw, stageH/ch). Pixi
        // then passes the sprite's *bounds* as the gl viewport so the model paints
        // only inside that rect (which has the model's canvas aspect, not the
        // stage aspect), and the projection's aspect-correction term cancels out
        // because viewport-aspect == canvas-aspect.
        //
        // SwiftUI already pins this MTKView to the stage rect, so the incoming
        // `viewport` argument equals the stage rect in pixels.
        const float stageW = static_cast<float>(viewport.width);
        const float stageH = static_cast<float>(viewport.height);
        const float cw = model->GetCanvasWidth();
        const float ch = model->GetCanvasHeight();

        MTLViewport modelViewport = viewport;
        if (stageW > 0.0f && stageH > 0.0f && cw > 0.0f && ch > 0.0f)
        {
            const float scale = std::min(stageW / cw, stageH / ch);
            const float modelW = cw * scale;
            const float modelH = ch * scale;
            modelViewport.originX = viewport.originX + (stageW - modelW) * 0.5f;
            // Metal viewport has y-down origin (top-left). Bottom-anchor places
            // the model so its lower edge meets the stage's lower edge.
            modelViewport.originY = viewport.originY + (stageH - modelH);
            modelViewport.width = modelW;
            modelViewport.height = modelH;
        }
        renderer->SetRenderViewport(modelViewport);

        // Now viewport-aspect == canvas-aspect, so `Scale(vh/vw, 1)` (web's
        // aspect-correction) becomes `Scale(ch/cw, 1)` for landscape canvases:
        // exactly the same x-shrink that the default `CubismModelMatrix` applies
        // anyway (SetHeight(2) → scaleX=scaleY=2/ch, so canvas width in NDC
        // = 2*cw/ch). Combined the model fills [-cw/ch, cw/ch] × [0, 2] minus
        // the projection scale: [-1, 1] × [0, 2*cw/ch]. We only need the default
        // projection-Scale form so canvas-NDC aspect matches the (now canvas-shaped)
        // viewport.
        const float vw = static_cast<float>(modelViewport.width);
        const float vh = static_cast<float>(modelViewport.height);

        CubismMatrix44 projection;
        if (vw > 0.0f && vh > 0.0f)
        {
            if (vw < vh)
            {
                projection.Scale(1.0f, vw / vh);
            }
            else
            {
                projection.Scale(vh / vw, 1.0f);
            }
        }

        CubismModelMatrix modelMatrix(cw, ch);
        if (_hasLayout)
        {
            modelMatrix.SetupFromLayout(_layout);
        }
        projection.MultiplyByMatrix(&modelMatrix);

        renderer->SetMvpMatrix(&projection);
        renderer->DrawModel();
    }

    CGRect ModelDrawRectForStageRect(CGRect stageRect)
    {
        CubismModel* model = GetModel();
        if (model == nullptr || stageRect.size.width <= 0.0 || stageRect.size.height <= 0.0)
        {
            return CGRectZero;
        }

        const CGFloat cw = static_cast<CGFloat>(model->GetCanvasWidth());
        const CGFloat ch = static_cast<CGFloat>(model->GetCanvasHeight());
        if (cw <= 0.0 || ch <= 0.0)
        {
            return stageRect;
        }

        const CGFloat scale = std::min(stageRect.size.width / cw, stageRect.size.height / ch);
        const CGFloat modelW = cw * scale;
        const CGFloat modelH = ch * scale;
        return CGRectMake(
            stageRect.origin.x + (stageRect.size.width - modelW) * 0.5,
            stageRect.origin.y,
            modelW,
            modelH
        );
    }

    CGRect VisibleDrawableRectForStageRect(CGRect stageRect)
    {
        CubismModel* model = GetModel();
        const CGRect modelRect = ModelDrawRectForStageRect(stageRect);
        if (model == nullptr || CGRectIsEmpty(modelRect))
        {
            return modelRect;
        }

        const float vw = static_cast<float>(modelRect.size.width);
        const float vh = static_cast<float>(modelRect.size.height);
        if (vw <= 0.0f || vh <= 0.0f)
        {
            return modelRect;
        }

        const float cw = model->GetCanvasWidth();
        const float ch = model->GetCanvasHeight();
        CubismMatrix44 projection;
        if (vw < vh)
        {
            projection.Scale(1.0f, vw / vh);
        }
        else
        {
            projection.Scale(vh / vw, 1.0f);
        }

        CubismModelMatrix modelMatrix(cw, ch);
        if (_hasLayout)
        {
            modelMatrix.SetupFromLayout(_layout);
        }
        projection.MultiplyByMatrix(&modelMatrix);

        bool hasBounds = false;
        CGFloat minX = 0.0;
        CGFloat minY = 0.0;
        CGFloat maxX = 0.0;
        CGFloat maxY = 0.0;

        const csmInt32 drawableCount = model->GetDrawableCount();
        for (csmInt32 i = 0; i < drawableCount; ++i)
        {
            if (!model->GetDrawableDynamicFlagIsVisible(i) || model->GetDrawableOpacity(i) <= 0.01f)
            {
                continue;
            }

            const csmInt32 vertexCount = model->GetDrawableVertexCount(i);
            const csmFloat32* vertices = model->GetDrawableVertices(i);
            if (vertexCount <= 0 || vertices == nullptr)
            {
                continue;
            }

            for (csmInt32 j = 0; j < vertexCount; ++j)
            {
                const csmFloat32 vx = vertices[Constant::VertexOffset + j * Constant::VertexStep];
                const csmFloat32 vy = vertices[Constant::VertexOffset + j * Constant::VertexStep + 1];
                const csmFloat32 clipX = projection.TransformX(vx);
                const csmFloat32 clipY = projection.TransformY(vy);
                if (!std::isfinite(clipX) || !std::isfinite(clipY))
                {
                    continue;
                }

                const CGFloat px = modelRect.origin.x + (static_cast<CGFloat>(clipX) + 1.0) * 0.5 * modelRect.size.width;
                const CGFloat py = modelRect.origin.y + (static_cast<CGFloat>(clipY) + 1.0) * 0.5 * modelRect.size.height;
                if (!hasBounds)
                {
                    minX = maxX = px;
                    minY = maxY = py;
                    hasBounds = true;
                }
                else
                {
                    minX = std::min(minX, px);
                    minY = std::min(minY, py);
                    maxX = std::max(maxX, px);
                    maxY = std::max(maxY, py);
                }
            }
        }

        if (!hasBounds || maxX <= minX || maxY <= minY)
        {
            return modelRect;
        }

        const CGFloat hitSlop = 6.0;
        CGRect rect = CGRectInset(CGRectMake(minX, minY, maxX - minX, maxY - minY), -hitSlop, -hitSlop);
        return CGRectIntersection(rect, modelRect);
    }

private:
    static void OnTapMotionFinished(ACubismMotion* motion)
    {
        void* raw = motion ? motion->GetFinishedMotionCustomData() : nullptr;
        auto* self = static_cast<StaticCubismMetalModel*>(raw);
        if (self != nullptr)
        {
            self->handleTapMotionFinished();
        }
    }

    void handleTapMotionFinished()
    {
        _tapMotionBusy = false;
    }

    void RebuildParameterIndexCache()
    {
        _parameterIndices.clear();
        CubismModel* model = GetModel();
        if (model == nullptr)
        {
            return;
        }

        const csmInt32 count = model->GetParameterCount();
        for (csmInt32 i = 0; i < count; ++i)
        {
            const CubismIdHandle id = model->GetParameterId(i);
            if (id != nullptr)
            {
                _parameterIndices[std::string(id->GetString().GetRawString())] = i;
            }
        }
    }

    csmInt32 FindParameterIndex(const std::string& parameterId) const
    {
        const auto found = _parameterIndices.find(parameterId);
        return found == _parameterIndices.end() ? -1 : found->second;
    }

    void SetParameterTarget(const std::string& parameterId, csmFloat32 value, bool smoothing)
    {
        ParameterTarget& target = _targetParameterValues[parameterId];
        target.index = FindParameterIndex(parameterId);
        target.target = value;
        target.smoothing = smoothing;
    }

    void SetMouseParameterTarget(const char* parameterId, csmFloat32 xRatio, csmFloat32 yRatio, bool mouseMirror)
    {
        CubismModel* model = GetModel();
        if (model == nullptr)
        {
            return;
        }

        const std::string id(parameterId);
        const csmInt32 index = FindParameterIndex(id);
        if (index < 0)
        {
            return;
        }

        const csmFloat32 minValue = model->GetParameterMinimumValue(index);
        const csmFloat32 maxValue = model->GetParameterMaximumValue(index);
        const bool isXAxis = !id.empty() && id.back() == 'X';
        const bool isYAxis = !id.empty() && id.back() == 'Y';
        const bool isZAxis = !id.empty() && id.back() == 'Z';

        csmFloat32 value = 0.0f;
        if (isZAxis)
        {
            const csmFloat32 dragX = 1.0f - 2.0f * xRatio;
            const csmFloat32 dragY = 1.0f - 2.0f * yRatio;
            value = dragX * dragY * minValue;
        }
        else
        {
            const csmFloat32 ratio = isXAxis ? xRatio : yRatio;
            value = maxValue - ratio * (maxValue - minValue);
        }

        if (!isYAxis && mouseMirror)
        {
            value *= -1.0f;
        }

        SetParameterTarget(id, value, true);
    }

    bool IsMouseFollowParameter(const std::string& parameterId) const
    {
        return parameterId == "ParamMouseX"
            || parameterId == "ParamMouseY"
            || parameterId == "ParamAngleX"
            || parameterId == "ParamAngleY"
            || parameterId == "ParamAngleZ"
            || parameterId == "ParamEyeBallX"
            || parameterId == "ParamEyeBallY";
    }

    CubismModelSettingJson* _modelSetting = nullptr;
    std::string _modelDirectory;
    csmMap<csmString, csmFloat32> _layout;
    std::unordered_map<std::string, csmInt32> _parameterIndices;
    std::unordered_map<std::string, ParameterTarget> _targetParameterValues;
    bool _hasLayout = false;
    bool _tapMotionBusy = false;
};

} // namespace

@interface CubismNativeMetalRenderer ()
- (void)loadCubismModelWithWidth:(NSUInteger)width height:(NSUInteger)height;
- (void)bindTextures;
@end

@implementation CubismNativeMetalRenderer
{
    std::unique_ptr<StaticCubismMetalModel> _model;
    id<MTLDevice> _device;
    NSMutableArray<id<MTLTexture>> *_textures;
    NSString *_modelDirectory;
    NSString *_modelJSON;
    BOOL _cubismReady;
    NSUInteger _rendererWidth;
    NSUInteger _rendererHeight;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device
                modelDirectory:(NSString *)modelDirectory
                     modelJSON:(NSString *)modelJSON
{
    self = [super init];
    if (!self)
    {
        return nil;
    }

    _device = device;
    _modelDirectory = [modelDirectory copy];
    _modelJSON = [modelJSON copy];
    _textures = [NSMutableArray array];
    _rendererWidth = 512;
    _rendererHeight = 512;

    if (_device)
    {
        Rendering::CubismRenderer_Metal::SetConstantSettings(_device);
        [self loadCubismModelWithWidth:_rendererWidth height:_rendererHeight];
    }

    return self;
}

- (BOOL)isCubismReady
{
    return _cubismReady;
}

- (void)resizeToWidth:(NSUInteger)width height:(NSUInteger)height
{
    if (!_cubismReady || !_model || width == 0 || height == 0)
    {
        return;
    }

    if (_rendererWidth == width && _rendererHeight == height)
    {
        return;
    }

    _rendererWidth = width;
    _rendererHeight = height;
    _model->ResizeRenderer(static_cast<csmUint32>(width), static_cast<csmUint32>(height));
    [self bindTextures];
}

- (void)applyParameterValues:(NSDictionary<NSString *, NSNumber *> *)parameterValues
{
    if (_cubismReady && _model)
    {
        std::unordered_map<std::string, double> parameters;
        parameters.reserve(parameterValues.count);
        for (NSString *key in parameterValues)
        {
            parameters.emplace(std::string(key.UTF8String), parameterValues[key].doubleValue);
        }
        _model->SetParameterTargets(parameters);
    }
}

- (void)applyMouseCursorXRatio:(double)xRatio yRatio:(double)yRatio mouseMirror:(BOOL)mouseMirror
{
    if (!_cubismReady || !_model)
    {
        return;
    }

    _model->SetMouseCursor(
        static_cast<csmFloat32>(std::max(0.0, std::min(1.0, xRatio))),
        static_cast<csmFloat32>(std::max(0.0, std::min(1.0, yRatio))),
        mouseMirror
    );
}

- (BOOL)tryStartRandomTapMotion
{
    if (!_cubismReady || !_model)
    {
        return NO;
    }

    return _model->TryStartRandomTapMotion() ? YES : NO;
}

- (CGRect)modelDrawRectForStageRect:(CGRect)stageRect
{
    if (!_cubismReady || !_model)
    {
        return CGRectZero;
    }

    return _model->VisibleDrawableRectForStageRect(stageRect);
}

- (void)drawWithCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
          renderPassDescriptor:(MTLRenderPassDescriptor *)renderPassDescriptor
                      viewport:(MTLViewport)viewport
                     deltaTime:(double)deltaTime
{
    if (!_cubismReady || !_model || !commandBuffer || !renderPassDescriptor)
    {
        return;
    }

    const csmFloat32 safeDelta = static_cast<csmFloat32>(std::max(0.0, std::min(deltaTime, 1.0 / 15.0)));
    _model->UpdateFrame(safeDelta);
    _model->Draw(commandBuffer, renderPassDescriptor, viewport);
}

- (void)loadCubismModelWithWidth:(NSUInteger)width height:(NSUInteger)height
{
    if (!_modelDirectory.length || !_modelJSON.length || !_device)
    {
        return;
    }

    if (!EnsureCubismFramework())
    {
        NSLog(@"[CubismNative] failed to start framework");
        return;
    }

    _model = std::make_unique<StaticCubismMetalModel>();
    const bool loaded = _model->LoadAssets(
        std::string(_modelDirectory.UTF8String),
        std::string(_modelJSON.UTF8String),
        static_cast<csmUint32>(std::max<NSUInteger>(width, 1)),
        static_cast<csmUint32>(std::max<NSUInteger>(height, 1))
    );

    if (!loaded)
    {
        NSLog(@"[CubismNative] failed to load model assets");
        _model.reset();
        return;
    }

    [self bindTextures];
    _cubismReady = YES;
}

- (void)bindTextures
{
    if (!_model || !_device)
    {
        return;
    }

    [_textures removeAllObjects];

    MTKTextureLoader *loader = [[MTKTextureLoader alloc] initWithDevice:_device];
    NSDictionary *options = @{
        MTKTextureLoaderOptionSRGB: @NO,
    };

    for (csmInt32 index = 0; index < _model->GetTextureCountValue(); ++index)
    {
        NSString *texturePath = [NSString stringWithUTF8String:_model->GetTexturePath(index).c_str()];
        NSURL *textureURL = [NSURL fileURLWithPath:texturePath];
        NSError *error = nil;
        id<MTLTexture> texture = [loader newTextureWithContentsOfURL:textureURL options:options error:&error];

        if (!texture)
        {
            NSLog(@"[CubismNative] texture load failed: %@ %@", texturePath, error.localizedDescription);
            continue;
        }

        [_textures addObject:texture];
        _model->BindTextureAtIndex(index, texture);
    }
}

@end

@interface CubismNativeMetalView () <MTKViewDelegate>
@end

@implementation CubismNativeMetalView
{
    std::unique_ptr<StaticCubismMetalModel> _model;
    id<MTLCommandQueue> _commandQueue;
    NSMutableArray<id<MTLTexture>> *_textures;
    NSString *_modelDirectory;
    NSString *_modelJSON;
    BOOL _cubismReady;
    CFTimeInterval _lastFrameTime;
}

- (instancetype)initWithFrame:(CGRect)frameRect device:(nullable id<MTLDevice>)device
{
    NSAssert(NO, @"Use -initWithFrame:modelDirectory:modelJSON: instead");
    return nil;
}

- (instancetype)initWithFrame:(NSRect)frameRect
               modelDirectory:(NSString *)modelDirectory
                    modelJSON:(NSString *)modelJSON
{
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();

    self = [super initWithFrame:frameRect device:device];
    if (!self)
    {
        return nil;
    }

    _modelDirectory = [modelDirectory copy];
    _modelJSON = [modelJSON copy];
    _textures = [NSMutableArray array];

    self.delegate = self;
    self.preferredFramesPerSecond = 60;
    self.enableSetNeedsDisplay = NO;
    self.paused = NO;
    self.framebufferOnly = NO;
    self.clearColor = MTLClearColorMake(0, 0, 0, 0);
    self.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
    // Cubism's Metal pipeline state hard-codes
    // `renderPipelineDescriptor.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float`
    // (see CubismShader_Metal.mm). The render-pass attachment format MUST match, otherwise
    // Metal silently drops draw calls. MTKView defaults to `MTLPixelFormatInvalid` (no depth),
    // so we have to opt in here and let MTKView own the depth texture.
    self.depthStencilPixelFormat = MTLPixelFormatDepth32Float;
    self.clearDepth = 1.0;
    self.sampleCount = 1;
    self.layer.opaque = NO;

    if (!device)
    {
        return self;
    }

    _commandQueue = [device newCommandQueue];
    Rendering::CubismRenderer_Metal::SetConstantSettings(device);
    [self loadCubismModel];
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    return [self initWithFrame:NSZeroRect modelDirectory:@"" modelJSON:@""];
}

- (BOOL)isCubismReady
{
    return _cubismReady;
}

- (void)applyParameterValues:(NSDictionary<NSString *,NSNumber *> *)parameterValues
{
    if (_cubismReady && _model)
    {
        std::unordered_map<std::string, double> parameters;
        parameters.reserve(parameterValues.count);
        for (NSString *key in parameterValues)
        {
            parameters.emplace(std::string(key.UTF8String), parameterValues[key].doubleValue);
        }
        _model->SetParameterTargets(parameters);
    }

    if (self.paused)
    {
        [self draw];
    }
}

- (void)applyMouseCursorXRatio:(double)xRatio yRatio:(double)yRatio mouseMirror:(BOOL)mouseMirror
{
    if (!_cubismReady || !_model)
    {
        return;
    }

    _model->SetMouseCursor(
        static_cast<csmFloat32>(std::max(0.0, std::min(1.0, xRatio))),
        static_cast<csmFloat32>(std::max(0.0, std::min(1.0, yRatio))),
        mouseMirror
    );

    if (self.paused)
    {
        [self draw];
    }
}

- (void)setCubismAnimating:(BOOL)animating
{
    self.paused = !animating;
    self.enableSetNeedsDisplay = !animating;

    if (!animating)
    {
        [self draw];
    }
}

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size
{
    if (!_cubismReady || !_model || size.width <= 0 || size.height <= 0)
    {
        return;
    }

    _model->ResizeRenderer(static_cast<csmUint32>(size.width), static_cast<csmUint32>(size.height));
    [self bindTextures];
}

- (void)drawInMTKView:(MTKView *)view
{
    if (!_cubismReady || !_model || !view.currentDrawable || !view.currentRenderPassDescriptor)
    {
        return;
    }

    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    if (!commandBuffer)
    {
        return;
    }

    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> _Nonnull buf) {
        if (buf.error)
        {
            NSLog(@"[CubismNative] commandBuffer error: %@", buf.error);
        }
    }];

    MTLViewport viewport = {
        0.0,
        0.0,
        static_cast<double>(view.drawableSize.width),
        static_cast<double>(view.drawableSize.height),
        0.0,
        1.0
    };

    const CFTimeInterval now = CACurrentMediaTime();
    const csmFloat32 deltaTimeSeconds = _lastFrameTime > 0
        ? static_cast<csmFloat32>(now - _lastFrameTime)
        : 1.0f / 60.0f;
    _lastFrameTime = now;

    _model->UpdateFrame(deltaTimeSeconds);
    _model->Draw(commandBuffer, view.currentRenderPassDescriptor, viewport);
    [commandBuffer presentDrawable:view.currentDrawable];
    [commandBuffer commit];
}

- (void)loadCubismModel
{
    if (!_modelDirectory.length || !_modelJSON.length || !self.device)
    {
        return;
    }

    if (!EnsureCubismFramework())
    {
        NSLog(@"[CubismNative] failed to start framework");
        return;
    }

    _model = std::make_unique<StaticCubismMetalModel>();
    const CGSize drawableSize = self.drawableSize.width > 0 && self.drawableSize.height > 0
        ? self.drawableSize
        : CGSizeMake(512, 512);

    const bool loaded = _model->LoadAssets(
        std::string(_modelDirectory.UTF8String),
        std::string(_modelJSON.UTF8String),
        static_cast<csmUint32>(drawableSize.width),
        static_cast<csmUint32>(drawableSize.height)
    );

    if (!loaded)
    {
        NSLog(@"[CubismNative] failed to load model assets");
        _model.reset();
        return;
    }

    [self bindTextures];
    _cubismReady = YES;
}

- (void)bindTextures
{
    if (!_model || !self.device)
    {
        return;
    }

    [_textures removeAllObjects];

    MTKTextureLoader *loader = [[MTKTextureLoader alloc] initWithDevice:self.device];
    NSDictionary *options = @{
        MTKTextureLoaderOptionSRGB: @NO,
    };

    for (csmInt32 index = 0; index < _model->GetTextureCountValue(); ++index)
    {
        NSString *texturePath = [NSString stringWithUTF8String:_model->GetTexturePath(index).c_str()];
        NSURL *textureURL = [NSURL fileURLWithPath:texturePath];
        NSError *error = nil;
        id<MTLTexture> texture = [loader newTextureWithContentsOfURL:textureURL options:options error:&error];

        if (!texture)
        {
            NSLog(@"[CubismNative] texture load failed: %@ %@", texturePath, error.localizedDescription);
            continue;
        }

        [_textures addObject:texture];
        _model->BindTextureAtIndex(index, texture);
    }
}

@end
