#include <GL/glew.h>

#import "Live2DBridge.h"
#import <Foundation/Foundation.h>

#include <memory>

#include "CompanionLive2DModel.hpp"
#include "LAppAllocator_Common.hpp"
#include "LAppPal.hpp"

using namespace Live2D::Cubism::Framework;

namespace {
bool gCubismInitialized = false;
LAppAllocator_Common gAllocator;
CubismFramework::Option gOption;
}

@interface CompanionLive2DView ()
@property (nonatomic, strong) NSTimer *renderTimer;
@property (nonatomic, strong) NSTrackingArea *trackingArea;
@end

@implementation CompanionLive2DView {
    std::unique_ptr<CompanionLive2DModel> _model;
    std::unique_ptr<LAppView_Common> _view;
    NSSize _lastDrawableSize;
    NSPoint _mouseDownPoint;
    BOOL _draggedSinceMouseDown;
}

- (nullable NSString *)resolvedModelFileName
{
    NSError *error = nil;
    NSArray<NSString *> *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.assetRootPath error:&error];
    if (!contents || error) {
        NSLog(@"Failed to list model directory %@: %@", self.assetRootPath, error.localizedDescription);
        return nil;
    }

    NSArray<NSString *> *modelFiles = [contents filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *fileName, NSDictionary<NSString *,id> * _Nullable bindings) {
        return [fileName hasSuffix:@".model3.json"];
    }]];

    return [[modelFiles sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)] firstObject];
}

- (void)loadCurrentModel
{
    NSString *modelFileName = [self resolvedModelFileName];
    if (!modelFileName) {
        return;
    }

    [[self openGLContext] makeCurrentContext];
    _model.reset();

    std::string modelDir = std::string([self.assetRootPath UTF8String]) + "/";
    _model = std::make_unique<CompanionLive2DModel>(modelDir);
    _model->LoadAssets([modelFileName UTF8String], (csmUint32)self.bounds.size.width, (csmUint32)self.bounds.size.height);
    [self loadAdditionalExpressionsFromDisk];
    _model->SetPassiveIdle(self.passiveIdle);
    _model->SetPresenceState((CompanionLive2DModel::PresenceState)self.presenceState);
    _model->SetEmotionState((CompanionLive2DModel::EmotionState)self.emotionState);
    _model->SetDragActive(self.draggingActive);
    _model->SetManualEmotionPreview(self.manualEmotionPreview);
    [self applyEmotionExpressionMap];

    if (self.modelAspectRatioHandler) {
        self.modelAspectRatioHandler(_model->GetContentAspectRatio());
    }
}

- (void)loadAdditionalExpressionsFromDisk
{
    if (!_model) {
        return;
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSDirectoryEnumerator<NSString *> *enumerator = [fileManager enumeratorAtPath:self.assetRootPath];
    for (NSString *relativePath in enumerator) {
        if (![relativePath hasSuffix:@".exp3.json"]) {
            continue;
        }

        NSString *absolutePath = [self.assetRootPath stringByAppendingPathComponent:relativePath];
        NSString *fileName = absolutePath.lastPathComponent;
        _model->AddExpressionFile(std::string(fileName.UTF8String), std::string(absolutePath.UTF8String));
    }
}

- (void)applyEmotionExpressionMap
{
    if (!_model || !self.emotionExpressionMap) {
        return;
    }

    auto setHints = ^(NSString *key, CompanionLive2DModel::EmotionState state) {
        NSArray<NSString *> *values = self.emotionExpressionMap[key];
        if (!values) {
            return;
        }

        std::vector<std::string> hints;
        hints.reserve(values.count);
        for (NSString *value in values) {
            hints.push_back(std::string(value.UTF8String));
        }
        _model->SetEmotionExpressionHints(state, hints);
    };

    setHints(@"neutral", CompanionLive2DModel::EmotionState::Neutral);
    setHints(@"happy", CompanionLive2DModel::EmotionState::Happy);
    setHints(@"excited", CompanionLive2DModel::EmotionState::Excited);
    setHints(@"shy", CompanionLive2DModel::EmotionState::Shy);
    setHints(@"thinking", CompanionLive2DModel::EmotionState::Thinking);
    setHints(@"sleepy", CompanionLive2DModel::EmotionState::Sleepy);
    setHints(@"angry", CompanionLive2DModel::EmotionState::Angry);
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    NSOpenGLPixelFormatAttribute attrs[] = {
        NSOpenGLPFAOpenGLProfile, NSOpenGLProfileVersionLegacy,
        NSOpenGLPFAColorSize, 24,
        NSOpenGLPFAAlphaSize, 8,
        NSOpenGLPFADoubleBuffer,
        NSOpenGLPFAAccelerated,
        0
    };
    NSOpenGLPixelFormat *format = [[NSOpenGLPixelFormat alloc] initWithAttributes:attrs];
    self = [super initWithFrame:frameRect pixelFormat:format];
    if (self) {
        _assetRootPath = [NSFileManager.defaultManager.currentDirectoryPath stringByAppendingPathComponent:@"Assets/shizuku/runtime"];
        self.wantsBestResolutionOpenGLSurface = YES;
        _lastDrawableSize = NSZeroSize;
    }
    return self;
}

- (BOOL)isOpaque { return NO; }

- (void)prepareOpenGL
{
    [super prepareOpenGL];
    [[self openGLContext] makeCurrentContext];

    GLint opaque = 0;
    [[self openGLContext] setValues:&opaque forParameter:NSOpenGLCPSurfaceOpacity];
    GLint swapInt = 1;
    [[self openGLContext] setValues:&swapInt forParameter:NSOpenGLCPSwapInterval];

    glewExperimental = GL_TRUE;
    const GLenum glewError = glewInit();
    if (glewError != GLEW_OK) {
        NSLog(@"GLEW init failed: %s", glewGetErrorString(glewError));
        return;
    }

    if (!gCubismInitialized) {
        gOption.LogFunction = LAppPal::PrintMessageLn;
        gOption.LoggingLevel = CubismFramework::Option::LogLevel_Verbose;
        gOption.LoadFileFunction = LAppPal::LoadFileAsBytes;
        gOption.ReleaseBytesFunction = LAppPal::ReleaseBytes;
        CubismFramework::StartUp(&gAllocator, &gOption);
        CubismFramework::Initialize();
        gCubismInitialized = true;
    }

    LAppPal::SetExecutableAbsolutePath(std::string([NSFileManager.defaultManager.currentDirectoryPath UTF8String]) + "/");

    _view = std::make_unique<LAppView_Common>();
    _view->Initialize((int)self.bounds.size.width, (int)self.bounds.size.height);
    [self loadCurrentModel];

    glDisable(GL_DEPTH_TEST);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
}

- (void)startRenderer
{
    [self stopRenderer];
    NSTimer *timer = [NSTimer timerWithTimeInterval:(1.0 / 60.0)
                                             target:self
                                           selector:@selector(renderTick)
                                           userInfo:nil
                                            repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    self.renderTimer = timer;
}

- (void)stopRenderer
{
    [self.renderTimer invalidate];
    self.renderTimer = nil;
}

- (void)reloadModel
{
    if (!_view) {
        return;
    }
    [self loadCurrentModel];
    [self setNeedsDisplay:YES];
}

- (void)renderTick
{
    if (!self.window || self.isHidden) {
        return;
    }

    [self setNeedsDisplayInRect:self.bounds];
    [self displayIfNeeded];
}

- (void)reshape
{
    [super reshape];
    [self syncDrawableSize];
}

- (void)drawRect:(NSRect)dirtyRect
{
    [super drawRect:dirtyRect];
    if (!_model) { return; }

    [[self openGLContext] makeCurrentContext];
    LAppPal::UpdateTime();
    [self syncDrawableSize];

    NSRect backingBounds = [self convertRectToBacking:self.bounds];
    glViewport(0, 0, (GLsizei)backingBounds.size.width, (GLsizei)backingBounds.size.height);
    glClearColor(0.0f, 0.0f, 0.0f, 0.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    _model->UpdateAndDraw((int)self.bounds.size.width, (int)self.bounds.size.height, _view.get());
    [[self openGLContext] flushBuffer];
}

- (void)setFrameSize:(NSSize)newSize
{
    [super setFrameSize:newSize];
    [self syncDrawableSize];
}

- (void)setFrame:(NSRect)frameRect
{
    [super setFrame:frameRect];
    [self syncDrawableSize];
}

- (void)syncDrawableSize
{
    if (!_view) {
        return;
    }

    [[self openGLContext] update];

    NSRect backingBounds = [self convertRectToBacking:self.bounds];
    NSSize drawableSize = backingBounds.size;
    if (drawableSize.width <= 0 || drawableSize.height <= 0) {
        return;
    }

    if (NSEqualSizes(_lastDrawableSize, drawableSize)) {
        return;
    }

    _lastDrawableSize = drawableSize;
    _view->Initialize((int)drawableSize.width, (int)drawableSize.height);
    if (_model) {
        _model->SetRenderTargetSize((csmUint32)drawableSize.width, (csmUint32)drawableSize.height);
    }
}

- (void)setPresenceState:(NSInteger)presenceState
{
    _presenceState = presenceState;
    if (_model) {
        _model->SetPresenceState((CompanionLive2DModel::PresenceState)presenceState);
    }
}

- (void)setPassiveIdle:(BOOL)passiveIdle
{
    _passiveIdle = passiveIdle;
    if (_model) {
        _model->SetPassiveIdle(passiveIdle);
    }
}

- (void)setEmotionState:(NSInteger)emotionState
{
    _emotionState = emotionState;
    if (_model) {
        _model->SetEmotionState((CompanionLive2DModel::EmotionState)emotionState);
    }
}

- (void)setDraggingActive:(BOOL)draggingActive
{
    _draggingActive = draggingActive;
    if (_model) {
        _model->SetDragActive(draggingActive);
    }
}

- (void)setManualEmotionPreview:(BOOL)manualEmotionPreview
{
    _manualEmotionPreview = manualEmotionPreview;
    if (_model) {
        _model->SetManualEmotionPreview(manualEmotionPreview);
    }
}

- (void)setEmotionExpressionMap:(NSDictionary<NSString *,NSArray<NSString *> *> *)emotionExpressionMap
{
    _emotionExpressionMap = [emotionExpressionMap copy];
    [self applyEmotionExpressionMap];
}

- (void)triggerExpressionHints:(NSArray<NSString *> *)hints
{
    if (!_model || hints.count == 0) {
        return;
    }

    std::vector<std::string> nativeHints;
    nativeHints.reserve(hints.count);
    for (NSString *hint in hints) {
        if (hint.length == 0) {
            continue;
        }
        nativeHints.push_back(std::string(hint.UTF8String));
    }

    if (_model->TriggerExpressionHints(nativeHints)) {
        [self setNeedsDisplay:YES];
    }
}

- (void)triggerMotionGroup:(NSString *)groupName
{
    if (!_model || groupName.length == 0) {
        return;
    }

    if (_model->TriggerMotionGroup(std::string(groupName.UTF8String))) {
        [self setNeedsDisplay:YES];
    }
}

- (void)updateTrackingAreas
{
    [super updateTrackingAreas];
    if (self.trackingArea) {
        [self removeTrackingArea:self.trackingArea];
    }
    self.trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                     options:NSTrackingActiveAlways | NSTrackingMouseMoved | NSTrackingInVisibleRect
                                                       owner:self
                                                    userInfo:nil];
    [self addTrackingArea:self.trackingArea];
}

- (void)mouseMoved:(NSEvent *)event { [self updateLook:event]; }
- (void)mouseDragged:(NSEvent *)event
{
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    CGFloat dx = point.x - _mouseDownPoint.x;
    CGFloat dy = point.y - _mouseDownPoint.y;
    if ((dx * dx + dy * dy) > 25.0) {
        _draggedSinceMouseDown = YES;
    }
    [self updateLook:event];
}

- (void)mouseDown:(NSEvent *)event
{
    _mouseDownPoint = [self convertPoint:event.locationInWindow fromView:nil];
    _draggedSinceMouseDown = NO;
    [self updateLook:event];
}

- (void)mouseUp:(NSEvent *)event
{
    [self updateLook:event];
    if (!_draggedSinceMouseDown) {
        if (_model) {
            _model->TriggerTapMotion();
        }
        if (self.tapHandler) {
            self.tapHandler();
        }
    }
    [super mouseUp:event];
}

- (void)scrollWheel:(NSEvent *)event
{
    if (self.scrollHandler) {
        CGFloat deltaY = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY;
        self.scrollHandler(deltaY);
    }
}

- (void)mouseExited:(NSEvent *)event
{
    [super mouseExited:event];
}

- (void)updateLook:(NSEvent *)event
{
    if (!_model || !_view) { return; }
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    _model->SetLookTarget(_view->TransformViewX(point.x), _view->TransformViewY(point.y));
}

- (void)dealloc
{
    [self stopRenderer];
}

@end
