#ifndef CallbackManager_h
#define CallbackManager_h

#include <stdio.h>
#include <stdbool.h>

// dart_api.h
typedef int64_t Dart_Port;

typedef enum {
    Dart_TypedData_kByteData = 0,
    Dart_TypedData_kInt8,
    Dart_TypedData_kUint8,
    Dart_TypedData_kUint8Clamped,
    Dart_TypedData_kInt16,
    Dart_TypedData_kUint16,
    Dart_TypedData_kInt32,
    Dart_TypedData_kUint32,
    Dart_TypedData_kInt64,
    Dart_TypedData_kUint64,
    Dart_TypedData_kFloat32,
    Dart_TypedData_kFloat64,
    Dart_TypedData_kFloat32x4,
    Dart_TypedData_kInvalid
} Dart_TypedData_Type;

typedef struct _Dart_WeakPersistentHandle* Dart_WeakPersistentHandle;

typedef void (*Dart_WeakPersistentHandleFinalizer)(
    void* isolate_callback_data,
    Dart_WeakPersistentHandle handle,
    void* peer);

// dart_native_api.h
typedef enum {
    Dart_CObject_kNull = 0,
    Dart_CObject_kBool,
    Dart_CObject_kInt32,
    Dart_CObject_kInt64,
    Dart_CObject_kDouble,
    Dart_CObject_kString,
    Dart_CObject_kArray,
    Dart_CObject_kTypedData,
    Dart_CObject_kExternalTypedData,
    Dart_CObject_kSendPort,
    Dart_CObject_kCapability,
    Dart_CObject_kUnsupported,
    Dart_CObject_kNumberOfTypes
} Dart_CObject_Type;

typedef struct _Dart_CObject {
    Dart_CObject_Type type;
    union {
        bool as_bool;
        int32_t as_int32;
        int64_t as_int64;
        double as_double;
        char* as_string;
        struct {
            Dart_Port id;
            Dart_Port origin_id;
        } as_send_port;
        struct {
            int64_t id;
        } as_capability;
        struct {
            intptr_t length;
            struct _Dart_CObject** values;
        } as_array;
        struct {
            Dart_TypedData_Type type;
            intptr_t length;
            int8_t* values;
        } as_typed_data;
        struct {
            Dart_TypedData_Type type;
            intptr_t length;
            int8_t* data;
            void* peer;
            Dart_WeakPersistentHandleFinalizer callback;
        } as_external_typed_data;
    } value;
} Dart_CObject;

typedef bool (*Dart_PostCObjectType)(Dart_Port port_id, Dart_CObject* message);

#ifdef __cplusplus
extern "C" {
#endif
    __attribute__((visibility("default"))) __attribute__((used)) void RegisterDart_PostCObject(Dart_PostCObjectType _dartPostCObject);

    void callbackToDartBool(Dart_Port callbackPort, bool value);
    void callbackToDartInt32(Dart_Port callbackPort, int32_t value);
    void callbackToDartInt32Array(Dart_Port callbackPort, int length, int32_t* value);
    void callbackToDartStrArray(Dart_Port callbackPort, int length, char** values);
#ifdef __cplusplus
}
#endif

#endif /* CallbackManager_h */
