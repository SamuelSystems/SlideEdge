#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Keyboard backlight through the private CoreBrightness `KeyboardBrightnessClient`.
/// Every selector is checked before use, so an API change disables the feature instead of crashing.
@interface SEKeyboardBacklight : NSObject

/// nil when CoreBrightness is unavailable, its API changed, or there is no backlit keyboard.
+ (nullable instancetype)connect;

- (instancetype)init NS_UNAVAILABLE;

/// 0...1
@property (nonatomic, readonly) float brightness;

- (BOOL)setBrightness:(float)brightness;

@end

NS_ASSUME_NONNULL_END
