#import "SEKeyboardBacklight.h"

#import <dlfcn.h>
#import <objc/message.h>

static NSString *const kCoreBrightnessPath = @"/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness";

@implementation SEKeyboardBacklight {
    id _client;
    unsigned long long _keyboardID;
}

+ (nullable instancetype)connect {
    if (!dlopen(kCoreBrightnessPath.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL)) {
        return nil;
    }
    Class clientClass = NSClassFromString(@"KeyboardBrightnessClient");
    SEL required[] = {
        sel_registerName("copyKeyboardBacklightIDs"),
        sel_registerName("brightnessForKeyboard:"),
        sel_registerName("setBrightness:forKeyboard:"),
        sel_registerName("isKeyboardBuiltIn:"),
    };
    if (!clientClass) {
        return nil;
    }
    for (size_t i = 0; i < sizeof(required) / sizeof(required[0]); i++) {
        if (![clientClass instancesRespondToSelector:required[i]]) {
            return nil;
        }
    }

    id client = [[clientClass alloc] init];
    NSArray *ids = ((id (*)(id, SEL))objc_msgSend)(client, sel_registerName("copyKeyboardBacklightIDs"));
    if (![ids isKindOfClass:[NSArray class]] || ids.count == 0) {
        return nil;
    }

    // Prefer the built-in keyboard; fall back to the first backlit one.
    NSNumber *chosen = nil;
    for (NSNumber *candidate in ids) {
        if (![candidate isKindOfClass:[NSNumber class]]) {
            continue;
        }
        BOOL builtIn = ((BOOL (*)(id, SEL, unsigned long long))objc_msgSend)(
            client, sel_registerName("isKeyboardBuiltIn:"), candidate.unsignedLongLongValue);
        if (builtIn) {
            chosen = candidate;
            break;
        }
        if (!chosen) {
            chosen = candidate;
        }
    }
    if (!chosen) {
        return nil;
    }
    return [[self alloc] initWithClient:client keyboardID:chosen.unsignedLongLongValue];
}

- (instancetype)initWithClient:(id)client keyboardID:(unsigned long long)keyboardID {
    if ((self = [super init])) {
        _client = client;
        _keyboardID = keyboardID;
    }
    return self;
}

- (float)brightness {
    return ((float (*)(id, SEL, unsigned long long))objc_msgSend)(
        _client, sel_registerName("brightnessForKeyboard:"), _keyboardID);
}

- (BOOL)setBrightness:(float)brightness {
    return ((BOOL (*)(id, SEL, float, unsigned long long))objc_msgSend)(
        _client, sel_registerName("setBrightness:forKeyboard:"), brightness, _keyboardID);
}

@end
