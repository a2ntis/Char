#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CompanionLive2DView : NSOpenGLView
@property (nonatomic, copy) NSString *assetRootPath;
@property (nonatomic) BOOL passiveIdle;
@property (nonatomic, copy) NSDictionary<NSString *, NSArray<NSString *> *> *emotionExpressionMap;
@property (nonatomic, copy, nullable) void (^modelAspectRatioHandler)(CGFloat aspectRatio);
@property (nonatomic, copy, nullable) dispatch_block_t tapHandler;
@property (nonatomic, copy, nullable) void (^scrollHandler)(CGFloat deltaY);
@property (nonatomic) NSInteger presenceState;
@property (nonatomic) NSInteger emotionState;
@property (nonatomic) BOOL draggingActive;
@property (nonatomic) BOOL manualEmotionPreview;
- (void)triggerExpressionHints:(NSArray<NSString *> *)hints;
- (void)triggerMotionGroup:(NSString *)groupName;
- (void)startRenderer;
- (void)stopRenderer;
- (void)reloadModel;
@end

NS_ASSUME_NONNULL_END
