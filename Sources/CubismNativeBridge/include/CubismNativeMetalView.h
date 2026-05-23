#import <AppKit/AppKit.h>
#import <MetalKit/MetalKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CubismNativeMetalView : MTKView

@property (nonatomic, readonly, getter=isCubismReady) BOOL cubismReady;

- (instancetype)initWithFrame:(CGRect)frameRect device:(nullable id<MTLDevice>)device NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithFrame:(NSRect)frameRect
               modelDirectory:(NSString *)modelDirectory
                    modelJSON:(NSString *)modelJSON NS_DESIGNATED_INITIALIZER;

- (void)applyParameterValues:(NSDictionary<NSString *, NSNumber *> *)parameterValues;
- (void)applyMouseCursorXRatio:(double)xRatio yRatio:(double)yRatio mouseMirror:(BOOL)mouseMirror;
- (void)setCubismAnimating:(BOOL)animating;

@end

@interface CubismNativeMetalRenderer : NSObject

@property (nonatomic, readonly, getter=isCubismReady) BOOL cubismReady;

- (instancetype)initWithDevice:(id<MTLDevice>)device
                modelDirectory:(NSString *)modelDirectory
                     modelJSON:(NSString *)modelJSON NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)resizeToWidth:(NSUInteger)width height:(NSUInteger)height;
- (void)applyParameterValues:(NSDictionary<NSString *, NSNumber *> *)parameterValues;
- (void)applyMouseCursorXRatio:(double)xRatio yRatio:(double)yRatio mouseMirror:(BOOL)mouseMirror;
/// Starts a random motion from the model's motion list or discovered `.motion3.json` files.
- (BOOL)tryStartRandomTapMotion;
/// Starts a random idle motion, preferring `idle` / `Idle` groups and falling back to all recognized motions.
- (BOOL)tryStartRandomIdleMotion;
/// Returns the visible Live2D drawable hit rect inside a full Bongo stage rect.
/// The input and output share the same coordinate system.
- (CGRect)modelDrawRectForStageRect:(CGRect)stageRect;
- (void)drawWithCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
          renderPassDescriptor:(MTLRenderPassDescriptor *)renderPassDescriptor
                      viewport:(MTLViewport)viewport
                     deltaTime:(double)deltaTime;

@end

NS_ASSUME_NONNULL_END
