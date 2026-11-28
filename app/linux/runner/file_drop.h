// #163: audio files dragged from the file manager into the window. The Flutter view takes the GTK
// drag with a text/uri-list and reports it on «woodshed/files» like the Mac
// (MainFlutterWindow.swift): «dragFiles» {x, y} while files are over the window, «dragExit» when
// they leave, «dropFiles» {paths, x, y} on the drop. The position is in logical pixels of the view;
// the URIs become local paths (percent escapes decoded), other files and URIs that are no local
// file are skipped (#22/AK2). GTK hands the URIs over only on the drop, so the window lights its
// targets for any dragged files. With WP_SMOKE=drop the channel «woodshed/dropSmoke» takes a drop
// put together like one from the file manager, for the smoke test (app/lib/app/drop_smoke.dart).
#ifndef RUNNER_FILE_DROP_H_
#define RUNNER_FILE_DROP_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <string>
#include <vector>

// Whether [path] names a file type the app imports, as in the open dialog.
bool file_drop_is_audio(const gchar* path);

// The local paths (UTF-8) of the audio files in a text/uri-list.
std::vector<std::string> file_drop_audio_paths(const gchar* uri_list);

// Makes [view] a drop target that reports on [files] (borrowed, it must outlive the view).
void file_drop_attach(GtkWidget* view, FlMethodChannel* files, FlBinaryMessenger* messenger);

#endif  // RUNNER_FILE_DROP_H_
