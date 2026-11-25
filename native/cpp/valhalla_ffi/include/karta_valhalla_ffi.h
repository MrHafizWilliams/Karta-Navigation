#ifndef KARTA_VALHALLA_FFI_H
#define KARTA_VALHALLA_FFI_H

#include <stdint.h>

#ifdef _WIN32
#define KARTA_API __declspec(dllexport)
#else
#define KARTA_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef void* karta_valhalla_handle_t;

KARTA_API karta_valhalla_handle_t karta_valhalla_create(const char* config_json);
KARTA_API char* karta_valhalla_route(karta_valhalla_handle_t handle, const char* request_json);
KARTA_API char* karta_valhalla_trace_attributes(karta_valhalla_handle_t handle, const char* request_json);
KARTA_API void karta_valhalla_free_string(char* str);
KARTA_API void karta_valhalla_destroy(karta_valhalla_handle_t handle);

#ifdef __cplusplus
}
#endif

#endif // KARTA_VALHALLA_FFI_H
