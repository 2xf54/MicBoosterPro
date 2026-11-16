#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AudioUnit/AudioUnit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <math.h>
#import "fishhook.h"

// UserDefaults keys
static NSString *const kMicBoostEnabledKey   = @"MB_MicBoostEnabled";
static NSString *const kMicBoostGainKey      = @"MB_MicBoostGain";
static NSString *const kMicBoostBypassVPOKey = @"MB_MicBoostBypassVPO";
static NSString *const kMicBoostHardClipKey  = @"MB_MicBoostHardClip";

static BOOL gBoostEnabled   = YES;
static float gBoostGain     = 8.0f;   // 1.0x to 20.0x
static BOOL gBypassVPO      = YES;    // Disable iOS AGC / VoiceProcessing limiter
static BOOL gHardClip       = YES;    // Max raw loudness

static void MBLoadSettings(void) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if ([ud objectForKey:kMicBoostEnabledKey] != nil) {
        gBoostEnabled = [ud boolForKey:kMicBoostEnabledKey];
    }
    if ([ud objectForKey:kMicBoostGainKey] != nil) {
        float g = [ud floatForKey:kMicBoostGainKey];
        if (g >= 1.0f && g <= 25.0f) gBoostGain = g;
    }
    if ([ud objectForKey:kMicBoostBypassVPOKey] != nil) {
        gBypassVPO = [ud boolForKey:kMicBoostBypassVPOKey];
    }
    if ([ud objectForKey:kMicBoostHardClipKey] != nil) {
        gHardClip = [ud boolForKey:kMicBoostHardClipKey];
    }
}

static void MBSaveSettings(void) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:gBoostEnabled forKey:kMicBoostEnabledKey];
    [ud setFloat:gBoostGain forKey:kMicBoostGainKey];
    [ud setBool:gBypassVPO forKey:kMicBoostBypassVPOKey];
    [ud setBool:gHardClip forKey:kMicBoostHardClipKey];
    [ud synchronize];
}

// Track stream format per AudioUnit (simple small lock-free-friendly table)
#define MAX_TRACKED_UNITS 16
typedef struct {
    AudioUnit unit;
    AudioStreamBasicDescription format;
    BOOL hasFormat;
} TrackedUnitFormat;

static TrackedUnitFormat gUnitFormats[MAX_TRACKED_UNITS];

static void MBSetUnitFormat(AudioUnit unit, const AudioStreamBasicDescription *fmt) {
    if (!unit || !fmt) return;
    for (int i = 0; i < MAX_TRACKED_UNITS; i++) {
        if (gUnitFormats[i].unit == unit || gUnitFormats[i].unit == NULL) {
            gUnitFormats[i].unit = unit;
            gUnitFormats[i].format = *fmt;
            gUnitFormats[i].hasFormat = YES;
            return;
        }
    }
}

static BOOL MBGetUnitFormat(AudioUnit unit, AudioStreamBasicDescription *outFmt) {
    if (!unit || !outFmt) return NO;
    for (int i = 0; i < MAX_TRACKED_UNITS; i++) {
        if (gUnitFormats[i].unit == unit && gUnitFormats[i].hasFormat) {
            *outFmt = gUnitFormats[i].format;
            return YES;
        }
    }
    // Query directly if not cached
    UInt32 size = sizeof(AudioStreamBasicDescription);
    if (AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, outFmt, &size) == noErr) {
        MBSetUnitFormat(unit, outFmt);
        return YES;
    }
    return NO;
}

// Original C AudioToolbox functions
static OSStatus (*orig_AudioUnitSetProperty)(AudioUnit inUnit,
                                            AudioUnitPropertyID inID,
                                            AudioUnitScope inScope,
                                            AudioUnitElement inElement,
                                            const void *inData,
                                            UInt32 inDataSize) = NULL;

static OSStatus (*orig_AudioUnitRender)(AudioUnit inUnit,
                                        AudioUnitRenderActionFlags *ioActionFlags,
                                        const AudioTimeStamp *inTimeStamp,
                                        UInt32 inOutputBusNumber,
                                        UInt32 inNumberFrames,
                                        AudioBufferList *ioData) = NULL;

static OSStatus hooked_AudioUnitSetProperty(AudioUnit inUnit,
                                            AudioUnitPropertyID inID,
                                            AudioUnitScope inScope,
                                            AudioUnitElement inElement,
                                            const void *inData,
                                            UInt32 inDataSize) {
    // Capture input bus 1 output format
    if (inID == kAudioUnitProperty_StreamFormat &&
        inScope == kAudioUnitScope_Output &&
        inElement == 1 &&
        inData != NULL &&
        inDataSize >= sizeof(AudioStreamBasicDescription)) {
        MBSetUnitFormat(inUnit, (const AudioStreamBasicDescription *)inData);
    }

    // Force-disable iOS VoiceProcessing AGC when boost/bypass is active
    if (gBoostEnabled && gBypassVPO && inData != NULL && inDataSize >= sizeof(UInt32)) {
        if (inID == kAUVoiceIOProperty_VoiceProcessingEnableAGC) {
            UInt32 disabled = 0;
            return orig_AudioUnitSetProperty(inUnit, inID, inScope, inElement, &disabled, sizeof(disabled));
        }
        if (inID == kAUVoiceIOProperty_BypassVoiceProcessing) {
            UInt32 bypass = 1;
            return orig_AudioUnitSetProperty(inUnit, inID, inScope, inElement, &bypass, sizeof(bypass));
        }
    }

    return orig_AudioUnitSetProperty(inUnit, inID, inScope, inElement, inData, inDataSize);
}

static OSStatus hooked_AudioUnitRender(AudioUnit inUnit,
                                       AudioUnitRenderActionFlags *ioActionFlags,
                                       const AudioTimeStamp *inTimeStamp,
                                       UInt32 inOutputBusNumber,
                                       UInt32 inNumberFrames,
                                       AudioBufferList *ioData) {
    OSStatus status = orig_AudioUnitRender(inUnit, ioActionFlags, inTimeStamp, inOutputBusNumber, inNumberFrames, ioData);
    if (status != noErr || !gBoostEnabled || inOutputBusNumber != 1 || ioData == NULL) {
        return status;
    }

    float gain = gBoostGain;
    if (gain <= 1.01f) {
        return status;
    }

    AudioStreamBasicDescription fmt;
    BOOL hasFmt = MBGetUnitFormat(inUnit, &fmt);
    BOOL isFloat = hasFmt ? ((fmt.mFormatFlags & kAudioFormatFlagIsFloat) != 0) : NO;
    UInt32 bitsPerChannel = hasFmt ? fmt.mBitsPerChannel : 16;

    for (UInt32 b = 0; b < ioData->mNumberBuffers; b++) {
        AudioBuffer *buf = &ioData->mBuffers[b];
        if (!buf->mData || buf->mDataByteSize == 0) continue;

        if (isFloat && bitsPerChannel == 32) {
            UInt32 sampleCount = buf->mDataByteSize / sizeof(float);
            float *samples = (float *)buf->mData;
            for (UInt32 i = 0; i < sampleCount; i++) {
                float s = samples[i] * gain;
                if (gHardClip) {
                    if (s > 1.0f) s = 1.0f;
                    else if (s < -1.0f) s = -1.0f;
                } else {
                    s = tanhf(s);
                }
                samples[i] = s;
            }
        } else {
            // Standard Int16 PCM used by WebRTC / tgcalls
            UInt32 sampleCount = buf->mDataByteSize / sizeof(int16_t);
            int16_t *samples = (int16_t *)buf->mData;
            for (UInt32 i = 0; i < sampleCount; i++) {
                float s = (float)samples[i] * gain;
                if (!gHardClip) {
                    // Soft saturation normalized to int16 range
                    s = tanhf(s / 32767.0f) * 32767.0f;
                }
                if (s > 32767.0f) s = 32767.0f;
                else if (s < -32767.0f) s = -32767.0f;
                samples[i] = (int16_t)s;
            }
        }
    }

    return status;
}

// Swizzle AVAudioSession to maximize hardware input gain and allow raw mode
@implementation AVAudioSession (MicBoost)

- (BOOL)mb_setInputGain:(float)gain error:(NSError **)outError {
    float target = gBoostEnabled ? 1.0f : gain;
    return [self mb_setInputGain:target error:outError];
}

- (BOOL)mb_setActive:(BOOL)active withOptions:(AVAudioSessionSetActiveOptions)options error:(NSError **)outError {
    BOOL ok = [self mb_setActive:active withOptions:options error:outError];
    if (ok && active && gBoostEnabled && self.isInputGainSettable) {
        [self mb_setInputGain:1.0f error:nil];
    }
    return ok;
}

@end

// Passthrough overlay UIWindow so touches on MIC & panel always work above Telegram
@interface MBOverlayWindow : UIWindow
@end

@implementation MBOverlayWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self || hit == self.rootViewController.view) {
        return nil;
    }
    return hit;
}
@end

// Floating UI Controller inside Telegram
@interface MBFloatingController : NSObject
@property (nonatomic, strong) MBOverlayWindow *overlayWindow;
@property (nonatomic, strong) UIButton *floatingButton;
@property (nonatomic, strong) UIView *panelView;
@property (nonatomic, strong) UILabel *gainValueLabel;
@property (nonatomic, strong) UISlider *gainSlider;
@property (nonatomic, strong) UISwitch *enableSwitch;
@property (nonatomic, strong) UISwitch *bypassSwitch;
@property (nonatomic, strong) UISwitch *hardClipSwitch;
+ (instancetype)shared;
- (void)installUI;
@end

@implementation MBFloatingController

+ (instancetype)shared {
    static MBFloatingController *inst = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        inst = [[MBFloatingController alloc] init];
    });
    return inst;
}

- (UIWindowScene *)activeWindowScene {
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]] &&
            scene.activationState == UISceneActivationStateForegroundActive) {
            return (UIWindowScene *)scene;
        }
    }
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            return (UIWindowScene *)scene;
        }
    }
    return nil;
}

- (UIWindow *)ensureOverlayWindow {
    UIWindowScene *ws = [self activeWindowScene];
    if (!ws) return nil;

    if (!self.overlayWindow) {
        MBOverlayWindow *ow = [[MBOverlayWindow alloc] initWithWindowScene:ws];
        ow.frame = ws.coordinateSpace.bounds;
        ow.windowLevel = UIWindowLevelAlert + 200;
        ow.backgroundColor = [UIColor clearColor];
        UIViewController *vc = [[UIViewController alloc] init];
        vc.view.backgroundColor = [UIColor clearColor];
        ow.rootViewController = vc;
        ow.hidden = NO;
        self.overlayWindow = ow;
    } else if (self.overlayWindow.windowScene != ws) {
        self.overlayWindow.windowScene = ws;
        self.overlayWindow.frame = ws.coordinateSpace.bounds;
    }
    self.overlayWindow.hidden = NO;
    return self.overlayWindow;
}

- (void)installUI {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self attachButtonIfNeeded];
    });
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(attachButtonIfNeeded)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
}

- (void)attachButtonIfNeeded {
    UIWindow *win = [self ensureOverlayWindow];
    if (!win) return;
    UIView *container = win.rootViewController.view;

    if (!self.floatingButton) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.frame = CGRectMake(container.bounds.size.width - 58, 130, 46, 46);
        btn.layer.cornerRadius = 23;
        btn.layer.borderWidth = 1.5;
        btn.layer.borderColor = [UIColor colorWithRed:1.0 green:0.25 blue:0.25 alpha:0.9].CGColor;
        btn.titleLabel.font = [UIFont boldSystemFontOfSize:11];
        [btn setTitle:@"MIC" forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [btn addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [btn addGestureRecognizer:pan];

        self.floatingButton = btn;
        [self updateButtonAppearance];
    }

    if (self.floatingButton.superview != container) {
        [container addSubview:self.floatingButton];
    }
    [container bringSubviewToFront:self.floatingButton];
}

- (void)updateButtonAppearance {
    if (gBoostEnabled) {
        self.floatingButton.backgroundColor = [UIColor colorWithRed:0.90 green:0.12 blue:0.18 alpha:0.92];
    } else {
        self.floatingButton.backgroundColor = [UIColor colorWithRed:0.15 green:0.15 blue:0.20 alpha:0.85];
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    UIView *superview = self.floatingButton.superview;
    if (!superview) return;
    CGPoint delta = [pan translationInView:superview];
    CGPoint c = self.floatingButton.center;
    c.x = MAX(26, MIN(superview.bounds.size.width - 26, c.x + delta.x));
    c.y = MAX(60, MIN(superview.bounds.size.height - 60, c.y + delta.y));
    self.floatingButton.center = c;
    [pan setTranslation:CGPointZero inView:superview];
}

- (void)togglePanel {
    UIWindow *win = [self ensureOverlayWindow];
    if (!win) return;
    UIView *container = win.rootViewController.view;

    if (self.panelView && self.panelView.superview) {
        [self.panelView removeFromSuperview];
        return;
    }

    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(24, (container.bounds.size.height - 290) / 2.0, container.bounds.size.width - 48, 290)];
    panel.backgroundColor = [UIColor colorWithRed:0.06 green:0.07 blue:0.10 alpha:0.96];
    panel.layer.cornerRadius = 18;
    panel.layer.borderWidth = 1.2;
    panel.layer.borderColor = [UIColor colorWithRed:1.0 green:0.23 blue:0.23 alpha:0.65].CGColor;
    panel.layer.shadowColor = [UIColor blackColor].CGColor;
    panel.layer.shadowOpacity = 0.6;
    panel.layer.shadowRadius = 16;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(18, 14, panel.bounds.size.width - 80, 26)];
    title.text = @"Extra Mic Boost";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont boldSystemFontOfSize:17];
    [panel addSubview:title];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(panel.bounds.size.width - 54, 10, 40, 32);
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor lightGrayColor] forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    [closeBtn addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:closeBtn];

    // Row 1: Enable Boost
    UILabel *l1 = [[UILabel alloc] initWithFrame:CGRectMake(18, 56, 200, 30)];
    l1.text = @"Mic Boost Active";
    l1.textColor = [UIColor whiteColor];
    l1.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    [panel addSubview:l1];

    UISwitch *sw1 = [[UISwitch alloc] initWithFrame:CGRectMake(panel.bounds.size.width - 70, 56, 51, 31)];
    sw1.onTintColor = [UIColor systemRedColor];
    sw1.on = gBoostEnabled;
    [sw1 addTarget:self action:@selector(onToggleEnable:) forControlEvents:UIControlEventValueChanged];
    [panel addSubview:sw1];
    self.enableSwitch = sw1;

    // Row 2: Gain Slider
    UILabel *gLabel = [[UILabel alloc] initWithFrame:CGRectMake(18, 98, panel.bounds.size.width - 36, 24)];
    gLabel.text = [NSString stringWithFormat:@"Boost Gain: %.1fx", gBoostGain];
    gLabel.textColor = [UIColor colorWithRed:1.0 green:0.35 blue:0.38 alpha:1.0];
    gLabel.font = [UIFont boldSystemFontOfSize:14];
    [panel addSubview:gLabel];
    self.gainValueLabel = gLabel;

    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(18, 126, panel.bounds.size.width - 36, 30)];
    slider.minimumValue = 1.0f;
    slider.maximumValue = 20.0f;
    slider.value = gBoostGain;
    slider.minimumTrackTintColor = [UIColor systemRedColor];
    [slider addTarget:self action:@selector(onGainChanged:) forControlEvents:UIControlEventValueChanged];
    [panel addSubview:slider];
    self.gainSlider = slider;

    // Row 3: Bypass iOS Limiter / AGC
    UILabel *l2 = [[UILabel alloc] initWithFrame:CGRectMake(18, 170, 220, 30)];
    l2.text = @"Disable iOS AGC / Limiter";
    l2.textColor = [UIColor whiteColor];
    l2.font = [UIFont systemFontOfSize:14];
    [panel addSubview:l2];

    UISwitch *sw2 = [[UISwitch alloc] initWithFrame:CGRectMake(panel.bounds.size.width - 70, 170, 51, 31)];
    sw2.onTintColor = [UIColor systemRedColor];
    sw2.on = gBypassVPO;
    [sw2 addTarget:self action:@selector(onToggleBypass:) forControlEvents:UIControlEventValueChanged];
    [panel addSubview:sw2];
    self.bypassSwitch = sw2;

    // Row 4: Max Raw Loudness (Hard Clamp vs Soft Clip)
    UILabel *l3 = [[UILabel alloc] initWithFrame:CGRectMake(18, 214, 220, 30)];
    l3.text = @"Max Raw Loudness";
    l3.textColor = [UIColor whiteColor];
    l3.font = [UIFont systemFontOfSize:14];
    [panel addSubview:l3];

    UISwitch *sw3 = [[UISwitch alloc] initWithFrame:CGRectMake(panel.bounds.size.width - 70, 214, 51, 31)];
    sw3.onTintColor = [UIColor systemRedColor];
    sw3.on = gHardClip;
    [sw3 addTarget:self action:@selector(onToggleHardClip:) forControlEvents:UIControlEventValueChanged];
    [panel addSubview:sw3];
    self.hardClipSwitch = sw3;

    self.panelView = panel;
    [container addSubview:panel];
    [container bringSubviewToFront:panel];
    if (self.floatingButton) {
        [container bringSubviewToFront:self.floatingButton];
    }
}

- (void)onToggleEnable:(UISwitch *)sender {
    gBoostEnabled = sender.isOn;
    MBSaveSettings();
    [self updateButtonAppearance];
    AVAudioSession *session = [AVAudioSession sharedInstance];
    if (gBoostEnabled && session.isInputGainSettable) {
        [session setInputGain:1.0f error:nil];
    }
}

- (void)onGainChanged:(UISlider *)sender {
    gBoostGain = sender.value;
    self.gainValueLabel.text = [NSString stringWithFormat:@"Boost Gain: %.1fx", gBoostGain];
    MBSaveSettings();
}

- (void)onToggleBypass:(UISwitch *)sender {
    gBypassVPO = sender.isOn;
    MBSaveSettings();
}

- (void)onToggleHardClip:(UISwitch *)sender {
    gHardClip = sender.isOn;
    MBSaveSettings();
}

@end

__attribute__((constructor))
static void init_mic_boost(void) {
    MBLoadSettings();

    struct rebinding rebindings[] = {
        { "AudioUnitSetProperty", (void *)hooked_AudioUnitSetProperty, (void **)&orig_AudioUnitSetProperty },
        { "AudioUnitRender", (void *)hooked_AudioUnitRender, (void **)&orig_AudioUnitRender }
    };
    rebind_symbols(rebindings, 2);

    // Swizzle AVAudioSession setInputGain:error: and setActive:withOptions:error:
    Class sessionCls = [AVAudioSession class];
    Method m1 = class_getInstanceMethod(sessionCls, @selector(setInputGain:error:));
    Method m2 = class_getInstanceMethod(sessionCls, @selector(mb_setInputGain:error:));
    if (m1 && m2) method_exchangeImplementations(m1, m2);

    Method m3 = class_getInstanceMethod(sessionCls, @selector(setActive:withOptions:error:));
    Method m4 = class_getInstanceMethod(sessionCls, @selector(mb_setActive:withOptions:error:));
    if (m3 && m4) method_exchangeImplementations(m3, m4);

    dispatch_async(dispatch_get_main_queue(), ^{
        [[MBFloatingController shared] installUI];
    });
}
