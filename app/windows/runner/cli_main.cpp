// #140, #60: WoodshedPlayer.com, the console program of the command line (command_line.h). A
// console program, so the shell waits for it and shows its output; WoodshedPlayer.exe is a window
// program and returns at once.
#include <windows.h>
#include <shellapi.h>

#include <string>

#include "command_line.h"

int wmain() {
  const int code = RunCommandLine();
  if (code != -1) return code;
  // No command: start the app itself.
  wchar_t path[MAX_PATH];
  const DWORD n = ::GetModuleFileNameW(nullptr, path, MAX_PATH);
  if (n == 0 || n >= MAX_PATH) return 1;
  std::wstring exe(path);
  exe = exe.substr(0, exe.find_last_of(L'\\')) + L"\\WoodshedPlayer.exe";
  return reinterpret_cast<INT_PTR>(::ShellExecuteW(nullptr, L"open", exe.c_str(), nullptr,
                                                   nullptr, SW_SHOWNORMAL)) > 32
             ? 0
             : 1;
}
