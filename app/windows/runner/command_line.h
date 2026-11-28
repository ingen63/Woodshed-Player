// #140, #60: the command line of the Windows app. WoodshedPlayer.com (a console program next to
// WoodshedPlayer.exe, found first by cmd and PowerShell for «WoodshedPlayer play ...») runs
// wp_cli_main of the core (core/src/cli.cpp, transport core/src/cli_win.cpp); the app itself listens
// through command_bridge.cpp.
#ifndef RUNNER_COMMAND_LINE_H_
#define RUNNER_COMMAND_LINE_H_

#include <string>

// Socket file of the command line: the same path for the app and its program, in the app's data
// folder (%LOCALAPPDATA%\WoodshedPlayer). As a short path (8.3), since a socket path holds at most
// 107 bytes and Winsock reads it in the ANSI code page.
std::string CommandSocketPath();

// The app's data folder (%LOCALAPPDATA%) in UTF-8; Dart adds «WoodshedPlayer».
std::string SupportDir();

// #162: the folder for recordings, %LOCALAPPDATA%\WoodshedPlayer\Recordings in UTF-8, created if
// missing.
std::string RecordingsDir();

// The exit code of the command in the arguments of this process, or -1 if they hold none (start
// the app).
int RunCommandLine();

#endif  // RUNNER_COMMAND_LINE_H_
