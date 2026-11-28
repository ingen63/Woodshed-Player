#include "file_drop.h"

#include <cstring>

namespace {

GtkWidget* drop_view = nullptr;
FlMethodChannel* files_channel = nullptr;

void send(const gchar* method, FlValue* args) {
  fl_method_channel_invoke_method(files_channel, method, args, nullptr, nullptr, nullptr);
}

FlValue* position(double x, double y) {
  FlValue* map = fl_value_new_map();
  fl_value_set_string_take(map, "x", fl_value_new_float(x));
  fl_value_set_string_take(map, "y", fl_value_new_float(y));
  return map;
}

void drag_over(double x, double y) {
  g_autoptr(FlValue) at = position(x, y);
  send("dragFiles", at);
}

void drag_exit() { send("dragExit", nullptr); }

// Hands the audio files of [uri_list] dropped at [x], [y] to Dart; false if there are none.
bool drop_uri_list(const gchar* uri_list, double x, double y) {
  const std::vector<std::string> paths = file_drop_audio_paths(uri_list);
  if (paths.empty()) return false;
  g_autoptr(FlValue) args = position(x, y);
  FlValue* list = fl_value_new_list();
  for (const auto& p : paths) fl_value_append_take(list, fl_value_new_string(p.c_str()));
  fl_value_set_string_take(args, "paths", list);
  send("dropFiles", args);
  return true;
}

gboolean on_motion(GtkWidget* widget, GdkDragContext* context, gint x, gint y, guint time,
                   gpointer) {
  if (gtk_drag_dest_find_target(widget, context, nullptr) == GDK_NONE) {
    gdk_drag_status(context, static_cast<GdkDragAction>(0), time);
    return FALSE;
  }
  gdk_drag_status(context, GDK_ACTION_COPY, time);
  drag_over(x, y);
  return TRUE;
}

void on_leave(GtkWidget*, GdkDragContext*, guint, gpointer) { drag_exit(); }

gboolean on_drop(GtkWidget* widget, GdkDragContext* context, gint, gint, guint time, gpointer) {
  const GdkAtom target = gtk_drag_dest_find_target(widget, context, nullptr);
  if (target == GDK_NONE) return FALSE;
  gtk_drag_get_data(widget, context, target, time);
  return TRUE;
}

void on_data(GtkWidget*, GdkDragContext* context, gint x, gint y, GtkSelectionData* data, guint,
             guint time, gpointer) {
  const guchar* bytes = gtk_selection_data_get_data(data);
  const gint length = gtk_selection_data_get_length(data);
  bool taken = false;
  if (bytes != nullptr && length > 0) {
    const std::string text(reinterpret_cast<const char*>(bytes), static_cast<size_t>(length));
    taken = drop_uri_list(text.c_str(), x, y);
  }
  gtk_drag_finish(context, taken, FALSE, time);
}

// Smoke test: [paths] as the text/uri-list of a file manager, dropped at [x], [y].
bool simulate(FlValue* paths, double x, double y) {
  if (drop_view == nullptr || gtk_drag_dest_get_target_list(drop_view) == nullptr) return false;
  g_autoptr(GString) uri_list = g_string_new(nullptr);
  for (size_t i = 0; i < fl_value_get_length(paths); ++i) {
    FlValue* p = fl_value_get_list_value(paths, i);
    if (fl_value_get_type(p) != FL_VALUE_TYPE_STRING) continue;
    g_autofree gchar* uri = g_filename_to_uri(fl_value_get_string(p), nullptr, nullptr);
    if (uri == nullptr) continue;
    g_string_append(uri_list, uri);
    g_string_append(uri_list, "\r\n");
  }
  drag_over(x, y);
  drag_exit();  // GTK reports the leave before the drop
  return drop_uri_list(uri_list->str, x, y);
}

void on_smoke_call(FlMethodChannel*, FlMethodCall* call, gpointer) {
  FlValue* args = fl_method_call_get_args(call);
  g_autoptr(FlMethodResponse) response = nullptr;
  FlValue* paths = args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP
                       ? fl_value_lookup_string(args, "paths")
                       : nullptr;
  FlValue* x = paths != nullptr ? fl_value_lookup_string(args, "x") : nullptr;
  FlValue* y = paths != nullptr ? fl_value_lookup_string(args, "y") : nullptr;
  if (strcmp(fl_method_call_get_name(call), "drop") != 0 || paths == nullptr ||
      fl_value_get_type(paths) != FL_VALUE_TYPE_LIST || x == nullptr ||
      fl_value_get_type(x) != FL_VALUE_TYPE_FLOAT || y == nullptr ||
      fl_value_get_type(y) != FL_VALUE_TYPE_FLOAT) {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  } else {
    g_autoptr(FlValue) taken =
        fl_value_new_bool(simulate(paths, fl_value_get_float(x), fl_value_get_float(y)));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(taken));
  }
  fl_method_call_respond(call, response, nullptr);
}

}  // namespace

bool file_drop_is_audio(const gchar* path) {
  const gchar* dot = strrchr(path, '.');
  const gchar* slash = strrchr(path, '/');
  if (dot == nullptr || (slash != nullptr && dot < slash)) return false;
  // the types of the open dialog (files_channel.cc)
  for (const char* known : {"mp3", "m4a", "aac", "wav", "aif", "aiff", "flac", "caf"}) {
    if (g_ascii_strcasecmp(dot + 1, known) == 0) return true;
  }
  return false;
}

std::vector<std::string> file_drop_audio_paths(const gchar* uri_list) {
  std::vector<std::string> paths;
  g_auto(GStrv) uris = g_uri_list_extract_uris(uri_list);
  for (gchar** uri = uris; uri != nullptr && *uri != nullptr; ++uri) {
    // file:// URIs only; percent escapes decoded (space, «#», «%», umlauts in UTF-8)
    g_autofree gchar* path = g_filename_from_uri(*uri, nullptr, nullptr);
    // Dart takes UTF-8; a name in another encoding is skipped
    if (path != nullptr && g_utf8_validate(path, -1, nullptr) && file_drop_is_audio(path)) {
      paths.emplace_back(path);
    }
  }
  return paths;
}

void file_drop_attach(GtkWidget* view, FlMethodChannel* files, FlBinaryMessenger* messenger) {
  drop_view = view;
  files_channel = files;
  // no default handling: the handlers below answer motion and drop themselves
  gtk_drag_dest_set(view, static_cast<GtkDestDefaults>(0), nullptr, 0, GDK_ACTION_COPY);
  gtk_drag_dest_add_uri_targets(view);
  g_signal_connect(view, "drag-motion", G_CALLBACK(on_motion), nullptr);
  g_signal_connect(view, "drag-leave", G_CALLBACK(on_leave), nullptr);
  g_signal_connect(view, "drag-drop", G_CALLBACK(on_drop), nullptr);
  g_signal_connect(view, "drag-data-received", G_CALLBACK(on_data), nullptr);
  if (g_strcmp0(g_getenv("WP_SMOKE"), "drop") == 0) {
    g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
    FlMethodChannel* smoke =
        fl_method_channel_new(messenger, "woodshed/dropSmoke", FL_METHOD_CODEC(codec));
    fl_method_channel_set_method_call_handler(smoke, on_smoke_call, nullptr, nullptr);
    // the view keeps the channel
    g_object_set_data_full(G_OBJECT(view), "woodshed-drop-smoke", smoke, g_object_unref);
  }
}
