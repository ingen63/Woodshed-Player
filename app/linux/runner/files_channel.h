// #60: the channel «woodshed/files» of the Linux app (the Mac answers it in MainFlutterWindow.swift):
// file and folder choice, the app's data folder, links, build information and the socket file of the
// command line. Mac-only methods (microphone, recordings, menu bar, title bar) answer with nothing.
#ifndef RUNNER_FILES_CHANNEL_H_
#define RUNNER_FILES_CHANNEL_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <string>

// Socket file of the command line (#140): the same path for the app and its program started from
// a shell. In $XDG_RUNTIME_DIR (private to the user), otherwise in the app's data folder.
std::string command_socket_path();

// Answers «woodshed/files» on [messenger]; [window] is the parent of the file dialogs.
FlMethodChannel* files_channel_new(FlBinaryMessenger* messenger, GtkWindow* window);

#endif  // RUNNER_FILES_CHANNEL_H_
