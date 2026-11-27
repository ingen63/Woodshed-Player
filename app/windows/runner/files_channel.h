// #60: the channel «woodshed/files» of the Windows app (the Mac answers it in
// MainFlutterWindow.swift): file and folder choice, the app's data folder, links, build information
// and the socket file of the command line. Mac-only methods (microphone, recordings, menu bar, title
// bar) answer with nothing.
#ifndef RUNNER_FILES_CHANNEL_H_
#define RUNNER_FILES_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> CreateFilesChannel(
    flutter::BinaryMessenger* messenger, HWND window);

#endif  // RUNNER_FILES_CHANNEL_H_
