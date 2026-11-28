#include "command_line.h"

#include <windows.h>

#include <knownfolders.h>
#include <shellapi.h>
#include <shlobj.h>

#include <cwchar>
#include <string>
#include <vector>

#include "wp_cli.h"

namespace {

// UTF-8 of [text]; this file is also part of WoodshedPlayer.com, which has no Flutter (utils.cpp).
std::string Utf8(const std::wstring& text) {
  if (text.empty()) return std::string();
  const int n = ::WideCharToMultiByte(CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()),
                                      nullptr, 0, nullptr, nullptr);
  std::string out(n > 0 ? n : 0, '\0');
  if (n > 0) {
    ::WideCharToMultiByte(CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()), out.data(), n,
                          nullptr, nullptr);
  }
  return out;
}

std::wstring LocalAppData() {
  PWSTR path = nullptr;
  std::wstring dir;
  if (SUCCEEDED(::SHGetKnownFolderPath(FOLDERID_LocalAppData, KF_FLAG_CREATE, nullptr, &path))) {
    dir = path;
  }
  ::CoTaskMemFree(path);
  return dir;
}

std::wstring ExecutableDir() {
  std::vector<wchar_t> path(MAX_PATH);
  for (;;) {
    const DWORD n = ::GetModuleFileNameW(nullptr, path.data(), static_cast<DWORD>(path.size()));
    if (n == 0) return L".";
    if (n < path.size()) break;
    path.resize(path.size() * 2);
  }
  std::wstring p(path.data());
  return p.substr(0, p.find_last_of(L'\\'));
}

// Starts the app in the background; the command waits for its socket.
void LaunchApp() {
  std::wstring exe = ExecutableDir() + L"\\WoodshedPlayer.exe";
  std::wstring command = L"\"" + exe + L"\"";
  STARTUPINFOW startup{};
  startup.cb = sizeof startup;
  PROCESS_INFORMATION process{};
  if (::CreateProcessW(exe.c_str(), command.data(), nullptr, nullptr, FALSE, DETACHED_PROCESS,
                       nullptr, nullptr, &startup, &process)) {
    ::CloseHandle(process.hThread);
    ::CloseHandle(process.hProcess);
  }
}

bool IsCommand(const wchar_t* arg) {
  for (const wchar_t* c : {L"play", L"record", L"help", L"--help", L"-h"}) {
    if (std::wcscmp(arg, c) == 0) return true;
  }
  return false;
}

}  // namespace

std::string SupportDir() { return Utf8(LocalAppData()); }

std::string RecordingsDir() {
  const std::wstring app = LocalAppData() + L"\\WoodshedPlayer";
  const std::wstring dir = app + L"\\Recordings";
  ::CreateDirectoryW(app.c_str(), nullptr);
  ::CreateDirectoryW(dir.c_str(), nullptr);
  return Utf8(dir);
}

std::string CommandSocketPath() {
  std::wstring dir = LocalAppData() + L"\\WoodshedPlayer";
  ::CreateDirectoryW(dir.c_str(), nullptr);
  wchar_t short_path[MAX_PATH];
  const DWORD n = ::GetShortPathNameW(dir.c_str(), short_path, MAX_PATH);
  if (n > 0 && n < MAX_PATH) dir = short_path;
  return Utf8(dir + L"\\wp-cli.sock");
}

int RunCommandLine() {
  int argc = 0;
  wchar_t** wargv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (wargv == nullptr) return -1;
  // Only look further if the first argument may be a command; the app starts fast otherwise.
  if (argc < 2 || !IsCommand(wargv[1])) {
    ::LocalFree(wargv);
    return -1;
  }
  std::vector<std::string> args;
  for (int i = 0; i < argc; ++i) args.push_back(Utf8(wargv[i]));
  ::LocalFree(wargv);
  std::vector<const char*> argv;
  for (const auto& a : args) argv.push_back(a.c_str());
  // Titles and messages are UTF-8.
  ::SetConsoleOutputCP(CP_UTF8);
  const std::string socket = CommandSocketPath();
  return wp_cli_main(static_cast<int>(argv.size()), argv.data(), socket.c_str(), LaunchApp);
}
