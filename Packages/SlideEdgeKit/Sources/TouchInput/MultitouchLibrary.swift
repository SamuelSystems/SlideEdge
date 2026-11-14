import CMultitouch
import Darwin

/// Function pointers resolved at runtime from the private MultitouchSupport framework.
struct MultitouchLibrary: Sendable {
    static let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"

    let createList: MTDeviceCreateListFn
    let register: MTRegisterContactFrameCallbackWithRefconFn
    let unregister: MTUnregisterContactFrameCallbackFn
    let start: MTDeviceStartFn
    let stop: MTDeviceStopFn
    // Optional: only used to describe devices.
    let isBuiltIn: MTDeviceIsBuiltInFn?
    let getFamilyID: MTDeviceGetFamilyIDFn?
    let getDeviceID: MTDeviceGetDeviceIDFn?
    let getDimensions: MTDeviceGetSensorSurfaceDimensionsFn?

    /// Returns the library, or a human-readable reason why it cannot be used.
    static func load() -> Result<MultitouchLibrary, LoadError> {
        // Never closed: the framework stays mapped for the lifetime of the process.
        guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
            return .failure(LoadError(message: "MultitouchSupport non disponibile"))
        }

        func symbol<T>(_ name: String, as _: T.Type) -> T? {
            dlsym(handle, name).map { unsafeBitCast($0, to: T.self) }
        }

        guard
            let createList = symbol("MTDeviceCreateList", as: MTDeviceCreateListFn.self),
            let register = symbol("MTRegisterContactFrameCallbackWithRefcon", as: MTRegisterContactFrameCallbackWithRefconFn.self),
            let unregister = symbol("MTUnregisterContactFrameCallback", as: MTUnregisterContactFrameCallbackFn.self),
            let start = symbol("MTDeviceStart", as: MTDeviceStartFn.self),
            let stop = symbol("MTDeviceStop", as: MTDeviceStopFn.self)
        else {
            return .failure(LoadError(message: "MultitouchSupport: simboli mancanti in questa versione di macOS"))
        }

        return .success(MultitouchLibrary(
            createList: createList,
            register: register,
            unregister: unregister,
            start: start,
            stop: stop,
            isBuiltIn: symbol("MTDeviceIsBuiltIn", as: MTDeviceIsBuiltInFn.self),
            getFamilyID: symbol("MTDeviceGetFamilyID", as: MTDeviceGetFamilyIDFn.self),
            getDeviceID: symbol("MTDeviceGetDeviceID", as: MTDeviceGetDeviceIDFn.self),
            getDimensions: symbol("MTDeviceGetSensorSurfaceDimensions", as: MTDeviceGetSensorSurfaceDimensionsFn.self)
        ))
    }

    struct LoadError: Error {
        let message: String
    }
}
