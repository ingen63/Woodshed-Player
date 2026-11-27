#include "files_channel.h"

#include <sys/stat.h>

#include <cstring>

namespace {

GtkWindow* parent_window = nullptr;

// Folder of the app's data: $XDG_DATA_HOME (usually ~/.local/share); Dart adds «WoodshedPlayer».
std::string support_dir() {
  const std::string dir = g_get_user_data_dir();
  g_mkdir_with_parents(dir.c_str(), 0700);
  return dir;
}

// The file types the app imports (#22), as in the Mac's open panel.
void add_audio_filter(GtkFileChooser* chooser) {
  GtkFileFilter* filter = gtk_file_filter_new();
  gtk_file_filter_set_name(filter, "Audio");
  for (const char* ext : {"mp3", "m4a", "aac", "wav", "aif", "aiff", "flac", "caf"}) {
    g_autofree gchar* lower = g_strdup_printf("*.%s", ext);
    g_autofree gchar* upper = g_ascii_strup(lower, -1);
    gtk_file_filter_add_pattern(filter, lower);
    gtk_file_filter_add_pattern(filter, upper);
  }
  gtk_file_chooser_add_filter(chooser, filter);
}

FlValue* pick(bool folder, const gchar* prompt) {
  GtkFileChooserNative* dialog = gtk_file_chooser_native_new(
      nullptr, parent_window,
      folder ? GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER : GTK_FILE_CHOOSER_ACTION_OPEN,
      prompt, nullptr);
  GtkFileChooser* chooser = GTK_FILE_CHOOSER(dialog);
  gtk_file_chooser_set_local_only(chooser, TRUE);
  if (!folder) {
    gtk_file_chooser_set_select_multiple(chooser, TRUE);
    add_audio_filter(chooser);
  }
  const gint response = gtk_native_dialog_run(GTK_NATIVE_DIALOG(dialog));
  FlValue* result;
  if (folder) {
    g_autofree gchar* path =
        response == GTK_RESPONSE_ACCEPT ? gtk_file_chooser_get_filename(chooser) : nullptr;
    result = path ? fl_value_new_string(path) : fl_value_new_null();
  } else {
    result = fl_value_new_list();
    if (response == GTK_RESPONSE_ACCEPT) {
      GSList* files = gtk_file_chooser_get_filenames(chooser);
      for (GSList* f = files; f != nullptr; f = f->next) {
        fl_value_append_take(result, fl_value_new_string(static_cast<const gchar*>(f->data)));
      }
      g_slist_free_full(files, g_free);
    }
  }
  g_object_unref(dialog);
  return result;
}

FlMethodResponse* handle(FlMethodCall* call) {
  const gchar* method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);
  const gchar* text =
      args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_STRING ? fl_value_get_string(args)
                                                                         : nullptr;
  if (strcmp(method, "pickAudioFiles") == 0) {
    return FL_METHOD_RESPONSE(fl_method_success_response_new(pick(false, nullptr)));
  }
  if (strcmp(method, "pickFolder") == 0) {
    return FL_METHOD_RESPONSE(fl_method_success_response_new(pick(true, text)));
  }
  if (strcmp(method, "supportDir") == 0) {
    g_autoptr(FlValue) dir = fl_value_new_string(support_dir().c_str());
    return FL_METHOD_RESPONSE(fl_method_success_response_new(dir));
  }
  if (strcmp(method, "commandSocket") == 0) {
    g_autoptr(FlValue) path = fl_value_new_string(command_socket_path().c_str());
    return FL_METHOD_RESPONSE(fl_method_success_response_new(path));
  }
  if (strcmp(method, "microphoneAccess") == 0) {
    // #162: no recording on Linux yet
    g_autoptr(FlValue) no = fl_value_new_bool(FALSE);
    return FL_METHOD_RESPONSE(fl_method_success_response_new(no));
  }
  if (strcmp(method, "openUrl") == 0) {
    // #50/AK6: links of the About dialog open in the default browser; only https.
    if (text != nullptr && g_str_has_prefix(text, "https://")) {
      g_app_info_launch_default_for_uri(text, nullptr, nullptr);
    }
    return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  }
  if (strcmp(method, "buildInfo") == 0) {
    // #50/AK6: Git tag and build date, set by CMake when the build was configured.
    g_autoptr(FlValue) info = fl_value_new_map();
    fl_value_set_string_take(info, "tag", fl_value_new_string(WP_GIT_TAG));
    fl_value_set_string_take(info, "date", fl_value_new_string(WP_BUILD_DATE));
    return FL_METHOD_RESPONSE(fl_method_success_response_new(info));
  }
  if (strcmp(method, "keepAwake") == 0 || strcmp(method, "recordingsDir") == 0 ||
      strcmp(method, "windowAppearance") == 0 || strcmp(method, "localizeMenuBar") == 0) {
    return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  }
  return FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
}

void on_call(FlMethodChannel* channel, FlMethodCall* call, gpointer) {
  g_autoptr(FlMethodResponse) response = handle(call);
  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(call, response, &error)) {
    g_warning("woodshed/files: %s", error->message);
  }
}

}  // namespace

std::string command_socket_path() {
  // A socket path holds at most 107 bytes; the runtime folder is short and private (0700).
  const gchar* runtime = g_getenv("XDG_RUNTIME_DIR");
  if (runtime != nullptr && *runtime == '/') {
    return std::string(runtime) + "/woodshed-player-cli.sock";
  }
  const std::string dir = support_dir() + "/WoodshedPlayer";
  g_mkdir_with_parents(dir.c_str(), 0700);
  return dir + "/wp-cli.sock";
}

FlMethodChannel* files_channel_new(FlBinaryMessenger* messenger, GtkWindow* window) {
  parent_window = window;
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlMethodChannel* channel =
      fl_method_channel_new(messenger, "woodshed/files", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, on_call, nullptr, nullptr);
  return channel;
}
