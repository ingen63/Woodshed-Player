// Command line of the desktop app (#140, #60): transport on Windows. The command talks to the
// running app through a Unix domain socket (AF_UNIX of Winsock, Windows 10 1803 and later), a file
// in the app's own folder: a local connection between two processes of this computer, never TCP or
// UDP and never the network (#58). Ctrl-C comes from the console control handler.
// network-free: local unix socket (AF_UNIX only), see app/tool/network_free.dart
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
// Winsock first, then AF_UNIX (afunix.h needs its types), then the rest of Windows.
#include <winsock2.h> // network-free: local unix socket, AF_UNIX

#include <afunix.h>

#include <windows.h>

#include <atomic>
#include <cstring>
#include <mutex>

#include "cli.hpp"
#include "wp_cli.h"

namespace wp::cli {

namespace {

bool startWinsock() {
  static std::once_flag once;
  static bool ok = false;
  std::call_once(once, [] {
    WSADATA data{};
    ok = WSAStartup(MAKEWORD(2, 2), &data) == 0;
  });
  return ok;
}

class SocketConnection : public Connection {
public:
  explicit SocketConnection(SOCKET s) : s_(s) {}
  SocketConnection(const SocketConnection &) = delete;
  SocketConnection &operator=(const SocketConnection &) = delete;
  ~SocketConnection() override { ::closesocket(s_); }

  bool send(const std::string &line) override {
    const std::string data = line + "\n";
    size_t done = 0;
    while (done < data.size()) {
      const int n = ::send(s_, data.data() + done, static_cast<int>(data.size() - done), 0);
      if (n <= 0)
        return false;
      done += static_cast<size_t>(n);
    }
    return true;
  }

  int receive(std::string &line, std::chrono::milliseconds timeout) override {
    for (;;) {
      const auto nl = buffer_.find('\n');
      if (nl != std::string::npos) {
        line = buffer_.substr(0, nl);
        buffer_.erase(0, nl + 1);
        if (!line.empty() && line.back() == '\r')
          line.pop_back();
        return 1;
      }
      if (closed_)
        return -1;
      fd_set read{};
      FD_ZERO(&read);
      FD_SET(s_, &read);
      timeval tv{};
      tv.tv_sec = static_cast<long>(timeout.count() / 1000);
      tv.tv_usec = static_cast<long>((timeout.count() % 1000) * 1000);
      const int ready = ::select(0, &read, nullptr, nullptr, &tv);
      if (ready == SOCKET_ERROR)
        return -1;
      if (ready == 0)
        return 0;
      char buf[4096];
      const int n = ::recv(s_, buf, sizeof buf, 0);
      if (n <= 0)
        closed_ = true; // a last line without newline is dropped, the app always ends lines
      else
        buffer_.append(buf, static_cast<size_t>(n));
    }
  }

private:
  SOCKET s_;
  std::string buffer_;
  bool closed_ = false;
};

std::atomic<int> interrupts{0};

BOOL WINAPI onControl(DWORD type) {
  if (type != CTRL_C_EVENT && type != CTRL_BREAK_EVENT)
    return FALSE;
  // The second Ctrl-C ends the command at once (the app then sees the connection close).
  if (interrupts.fetch_add(1) >= 1)
    ::ExitProcess(WP_CLI_EXIT_CANCELLED);
  return TRUE;
}

} // namespace

std::unique_ptr<Connection> connectSocket(const std::string &path) {
  sockaddr_un addr{};
  if (path.empty() || path.size() >= sizeof addr.sun_path || !startWinsock())
    return nullptr;
  addr.sun_family = AF_UNIX;
  std::memcpy(addr.sun_path, path.c_str(), path.size() + 1);
  // network-free: local unix socket (AF_UNIX), a file path
  const SOCKET s = ::socket(AF_UNIX, SOCK_STREAM, 0);
  if (s == INVALID_SOCKET)
    return nullptr;
  // network-free: local unix socket (AF_UNIX), a file path
  if (::connect(s, reinterpret_cast<const sockaddr *>(&addr), sizeof addr) != 0) {
    ::closesocket(s);
    return nullptr;
  }
  return std::make_unique<SocketConnection>(s);
}

void catchInterrupt() { ::SetConsoleCtrlHandler(onControl, TRUE); }

bool interrupted() { return interrupts.load() > 0; }

} // namespace wp::cli
