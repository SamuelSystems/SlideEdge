// Reverse-engineered declarations for the private MultitouchSupport framework.
// Nothing is linked: the app resolves every symbol at runtime with dlopen/dlsym,
// so these are only types and function-pointer signatures.
#pragma once

#include <CoreFoundation/CoreFoundation.h>
#include <stdbool.h>
#include <stdint.h>

typedef struct {
    float x;
    float y;
} MTPoint;

typedef struct {
    MTPoint position;
    MTPoint velocity;
} MTVector;

// Values of MTTouch.state. Kept as plain constants: the field stays int32_t so an
// unexpected value from a future macOS can never become an invalid Swift enum.
enum {
    MTTouchStateNotTracking = 0,
    MTTouchStateStartInRange = 1,
    MTTouchStateHoverInRange = 2,
    MTTouchStateMakeTouch = 3,
    MTTouchStateTouching = 4,
    MTTouchStateBreakTouch = 5,
    MTTouchStateLingerInRange = 6,
    MTTouchStateOutOfRange = 7,
};

typedef struct {
    int32_t frame;
    double timestamp;
    int32_t pathIndex;          // stable per-finger identifier while the finger is down
    int32_t state;              // MTTouchState* constants
    int32_t fingerID;
    int32_t handID;
    MTVector normalizedVector;  // 0...1, origin bottom-left
    float zTotal;               // contact size / pressure proxy
    int32_t field9;
    float angle;
    float majorAxis;
    float minorAxis;
    MTVector absoluteVector;    // millimetres
    int32_t field14;
    int32_t field15;
    float zDensity;
} MTTouch;

_Static_assert(sizeof(MTTouch) == 96, "MTTouch layout changed");

typedef void *MTDeviceRef;

typedef void (*MTContactFrameCallbackRefcon)(MTDeviceRef device, const MTTouch *touches, int32_t count,
                                             double timestamp, int32_t frame, void *refcon);

typedef CFMutableArrayRef (*MTDeviceCreateListFn)(void);
typedef void (*MTRegisterContactFrameCallbackWithRefconFn)(MTDeviceRef device, MTContactFrameCallbackRefcon callback,
                                                            void *refcon);
typedef void (*MTUnregisterContactFrameCallbackFn)(MTDeviceRef device, MTContactFrameCallbackRefcon callback);
typedef int32_t (*MTDeviceStartFn)(MTDeviceRef device, int32_t mode);
typedef int32_t (*MTDeviceStopFn)(MTDeviceRef device);
typedef bool (*MTDeviceIsBuiltInFn)(MTDeviceRef device);
typedef int32_t (*MTDeviceGetFamilyIDFn)(MTDeviceRef device, int32_t *familyID);
typedef int32_t (*MTDeviceGetDeviceIDFn)(MTDeviceRef device, uint64_t *deviceID);
typedef int32_t (*MTDeviceGetSensorSurfaceDimensionsFn)(MTDeviceRef device, int32_t *width, int32_t *height);
