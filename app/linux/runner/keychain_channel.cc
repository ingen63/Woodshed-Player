#include "keychain_channel.h"

#include <dlfcn.h>

#include <cstring>
#include <string>

namespace {

// The few functions of libsecret-1 the app needs, the variants with a GHashTable (no varargs), so no
// header of libsecret is needed to build.
struct SecretSchema;
using SchemaNew = SecretSchema* (*)(const gchar*, int, GHashTable*);
using SchemaUnref = void (*)(SecretSchema*);
using Store = gboolean (*)(const SecretSchema*, GHashTable*, const gchar*, const gchar*,
                           const gchar*, GCancellable*, GError**);
using Lookup = gchar* (*)(const SecretSchema*, GHashTable*, GCancellable*, GError**);
using Clear = gboolean (*)(const SecretSchema*, GHashTable*, GCancellable*, GError**);
using PasswordFree = void (*)(gchar*);

struct Secret {
  bool loaded = false;
  SecretSchema* schema = nullptr;
  SchemaUnref schema_unref = nullptr;
  Store store = nullptr;
  Lookup lookup = nullptr;
  Clear clear = nullptr;
  PasswordFree password_free = nullptr;
};

// libsecret, loaded once; schema null if it is missing.
const Secret& secret() {
  static Secret s = [] {
    Secret out;
    out.loaded = true;
    void* lib = dlopen("libsecret-1.so.0", RTLD_NOW | RTLD_LOCAL);
    if (lib == nullptr) return out;
    auto schema_new = reinterpret_cast<SchemaNew>(dlsym(lib, "secret_schema_newv"));
    out.schema_unref = reinterpret_cast<SchemaUnref>(dlsym(lib, "secret_schema_unref"));
    out.store = reinterpret_cast<Store>(dlsym(lib, "secret_password_storev_sync"));
    out.lookup = reinterpret_cast<Lookup>(dlsym(lib, "secret_password_lookupv_sync"));
    out.clear = reinterpret_cast<Clear>(dlsym(lib, "secret_password_clearv_sync"));
    out.password_free = reinterpret_cast<PasswordFree>(dlsym(lib, "secret_password_free"));
    if (schema_new == nullptr || out.store == nullptr || out.lookup == nullptr ||
        out.clear == nullptr || out.password_free == nullptr) {
      return out;
    }
    // one attribute «key» of type string (SECRET_SCHEMA_ATTRIBUTE_STRING = 0), flags none
    g_autoptr(GHashTable) types = g_hash_table_new(g_str_hash, g_str_equal);
    g_hash_table_insert(types, const_cast<gchar*>("key"), GINT_TO_POINTER(0));
    out.schema = schema_new(APPLICATION_ID, 0, types);
    return out;
  }();
  return s;
}

// One call, done on the worker thread: the Secret Service may wait for the user to unlock the keyring.
struct Job {
  FlMethodCall* call;  // owned
  std::string method;
  std::string key;
  std::string value;
  FlMethodResponse* response = nullptr;  // owned, set by the worker
};

FlMethodResponse* error_response(const char* code, const gchar* message) {
  return FL_METHOD_RESPONSE(fl_method_error_response_new(code, message, nullptr));
}

FlMethodResponse* run(const Job& job) {
  const Secret& s = secret();
  if (s.schema == nullptr) return error_response("unavailable", "libsecret missing");
  g_autoptr(GHashTable) attributes = g_hash_table_new(g_str_hash, g_str_equal);
  g_hash_table_insert(attributes, const_cast<gchar*>("key"), const_cast<gchar*>(job.key.c_str()));
  g_autoptr(GError) error = nullptr;
  if (job.method == "read") {
    gchar* found = s.lookup(s.schema, attributes, nullptr, &error);
    if (error != nullptr) return error_response("keychain", error->message);
    g_autoptr(FlValue) value = found == nullptr ? fl_value_new_null() : fl_value_new_string(found);
    if (found != nullptr) s.password_free(found);
    return FL_METHOD_RESPONSE(fl_method_success_response_new(value));
  }
  if (job.method == "write") {
    const std::string label = "Woodshed Player: " + job.key;
    // nullptr: the default collection of the user («login»)
    if (!s.store(s.schema, attributes, nullptr, label.c_str(), job.value.c_str(), nullptr,
                 &error)) {
      return error_response("keychain", error != nullptr ? error->message : "store failed");
    }
    return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  }
  // delete: nothing stored is no error
  s.clear(s.schema, attributes, nullptr, &error);
  if (error != nullptr) return error_response("keychain", error->message);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

gboolean respond(gpointer data) {
  auto* job = static_cast<Job*>(data);
  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(job->call, job->response, &error)) {
    g_warning("woodshed/keychain: %s", error->message);
  }
  g_object_unref(job->response);
  g_object_unref(job->call);
  delete job;
  return G_SOURCE_REMOVE;
}

// One worker thread, so writes and deletes keep their order; the answer goes back on the main thread.
void work(gpointer data, gpointer) {
  auto* job = static_cast<Job*>(data);
  job->response = run(*job);
  g_main_context_invoke(nullptr, respond, job);
}

GThreadPool* pool() {
  static GThreadPool* p = g_thread_pool_new(work, nullptr, 1, FALSE, nullptr);
  return p;
}

const gchar* string_arg(FlValue* args, const char* name) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) return nullptr;
  FlValue* v = fl_value_lookup_string(args, name);
  return v != nullptr && fl_value_get_type(v) == FL_VALUE_TYPE_STRING ? fl_value_get_string(v)
                                                                       : nullptr;
}

void respond_now(FlMethodCall* call, FlMethodResponse* response) {
  g_autoptr(FlMethodResponse) owned = response;
  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(call, owned, &error)) {
    g_warning("woodshed/keychain: %s", error->message);
  }
}

void on_call(FlMethodChannel*, FlMethodCall* call, gpointer) {
  const gchar* method = fl_method_call_get_name(call);
  if (strcmp(method, "available") == 0) {
    g_autoptr(FlValue) yes = fl_value_new_bool(secret().schema != nullptr);
    respond_now(call, FL_METHOD_RESPONSE(fl_method_success_response_new(yes)));
    return;
  }
  if (strcmp(method, "read") != 0 && strcmp(method, "write") != 0 &&
      strcmp(method, "delete") != 0) {
    respond_now(call, FL_METHOD_RESPONSE(fl_method_not_implemented_response_new()));
    return;
  }
  FlValue* args = fl_method_call_get_args(call);
  const gchar* key = string_arg(args, "key");
  const gchar* value = string_arg(args, "value");
  if (key == nullptr || (strcmp(method, "write") == 0 && value == nullptr)) {
    respond_now(call, error_response("args", "key or value missing"));
    return;
  }
  auto* job = new Job{FL_METHOD_CALL(g_object_ref(call)), method, key, value ? value : ""};
  g_thread_pool_push(pool(), job, nullptr);
}

}  // namespace

FlMethodChannel* keychain_channel_new(FlBinaryMessenger* messenger) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlMethodChannel* channel =
      fl_method_channel_new(messenger, "woodshed/keychain", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, on_call, nullptr, nullptr);
  return channel;
}
