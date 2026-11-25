#include "karta_valhalla_ffi.h"

#include <cstring>
#include <memory>
#include <string>

#ifdef KARTA_HAS_LIBVALHALLA
#include <boost/property_tree/json_parser.hpp>
#include <boost/property_tree/ptree.hpp>
#include <sstream>
#include <valhalla/tyr/actor.h>
#endif

namespace {

struct KartaActorContext {
#ifdef KARTA_HAS_LIBVALHALLA
    std::unique_ptr<valhalla::tyr::actor_t> actor;
#endif
    std::string config_json;
};

char* duplicate_cstr(const std::string& input) {
    char* out = new char[input.size() + 1];
    std::memcpy(out, input.c_str(), input.size() + 1);
    return out;
}

} // namespace

extern "C" {

karta_valhalla_handle_t karta_valhalla_create(const char* config_json) {
    if (!config_json) return nullptr;
    auto* ctx = new KartaActorContext();
    ctx->config_json = config_json;
#ifdef KARTA_HAS_LIBVALHALLA
    try {
        boost::property_tree::ptree pt;
        std::istringstream ss(ctx->config_json);
        boost::property_tree::read_json(ss, pt);
        ctx->actor = std::make_unique<valhalla::tyr::actor_t>(pt, true);
    } catch (...) {
        delete ctx;
        return nullptr;
    }
#endif
    return static_cast<karta_valhalla_handle_t>(ctx);
}

char* karta_valhalla_route(karta_valhalla_handle_t handle, const char* request_json) {
    if (!handle || !request_json) return duplicate_cstr("{\"error\":\"invalid_handle\"}");
    auto* ctx = static_cast<KartaActorContext*>(handle);
#ifdef KARTA_HAS_LIBVALHALLA
    try {
        return duplicate_cstr(ctx->actor->route(request_json));
    } catch (const std::exception& ex) {
        return duplicate_cstr(std::string("{\"error\":\"") + ex.what() + "\"}");
    }
#else
    (void)ctx;
    return duplicate_cstr("{\"error\":\"libvalhalla_not_linked\"}");
#endif
}

char* karta_valhalla_trace_attributes(karta_valhalla_handle_t handle, const char* request_json) {
    if (!handle || !request_json) return duplicate_cstr("{\"error\":\"invalid_handle\"}");
    auto* ctx = static_cast<KartaActorContext*>(handle);
#ifdef KARTA_HAS_LIBVALHALLA
    try {
        return duplicate_cstr(ctx->actor->trace_attributes(request_json));
    } catch (const std::exception& ex) {
        return duplicate_cstr(std::string("{\"error\":\"") + ex.what() + "\"}");
    }
#else
    (void)ctx;
    return duplicate_cstr("{\"error\":\"libvalhalla_not_linked\"}");
#endif
}

void karta_valhalla_free_string(char* str) {
    delete[] str;
}

void karta_valhalla_destroy(karta_valhalla_handle_t handle) {
    auto* ctx = static_cast<KartaActorContext*>(handle);
    delete ctx;
}

} // extern "C"
