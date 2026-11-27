// #140, #60: the app's end of the command line on Windows. dart:io has no Unix domain sockets on
// Windows, so the runner listens on the socket file (AF_UNIX of Winsock, a local connection between
// two processes, never the network) and hands each line to Dart over the channel
// «woodshed/commands» (app/lib/app/command_channel.dart):
//   Dart -> runner: listen(path) -> bool, write({id, text}), close(id)
//   runner -> Dart: open(id), line({id, text}), closed(id)
#ifndef RUNNER_COMMAND_BRIDGE_H_
#define RUNNER_COMMAND_BRIDGE_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>

class CommandBridge {
 public:
  // Answers «woodshed/commands» on [messenger]; [window] receives kMessage from the socket threads.
  CommandBridge(flutter::BinaryMessenger* messenger, HWND window);
  ~CommandBridge();
  CommandBridge(const CommandBridge&) = delete;
  CommandBridge& operator=(const CommandBridge&) = delete;

  // Message posted to the window when lines or connections wait for Dart.
  static constexpr UINT kMessage = WM_APP + 0x60;

  // On the platform thread (FlutterWindow::MessageHandler): hands what waits to Dart.
  void Deliver();

  struct State;

 private:
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::shared_ptr<State> state_;
};

#endif  // RUNNER_COMMAND_BRIDGE_H_
