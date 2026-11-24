// Command line of the desktop app (#140): transport on macOS and Linux. The command talks to the
// running app through a Unix domain socket, a file in the app's own folder: a local connection
// between two processes of this computer, never TCP or UDP and never the network (#58).
// network-free: local unix socket (AF_UNIX only), see app/tool/network_free.dart
#include <poll.h>
#include <sys/socket.h> // network-free: local unix socket, AF_UNIX
#include <sys/un.h>
#include <unistd.h>

#include <atomic>
#include <cerrno>
#include <csignal>
#include <cstring>

#include "cli.hpp"
#include "wp_cli.h"

namespace wp::cli {

namespace {

class SocketConnection : public Connection {
public:
  explicit SocketConnection(int fd) : fd_(fd) {}
  SocketConnection(const SocketConnection &) = delete;
  SocketConnection &operator=(const SocketConnection &) = delete;
  ~SocketConnection() override { ::close(fd_); }

  bool send(const std::string &line) override {
    const std::string data = line + "\n";
    size_t done = 0;
    while (done < data.size()) {
      const ssize_t n = ::write(fd_, data.data() + done, data.size() - done);
      if (n < 0 && errno == EINTR)
        continue;
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
        return 1;
      }
      if (closed_)
        return -1;
      pollfd p{fd_, POLLIN, 0};
      const int ready = ::poll(&p, 1, static_cast<int>(timeout.count()));
      if (ready < 0 && errno == EINTR)
        return 0; // Ctrl-C: the caller sends "stop"
      if (ready < 0)
        return -1;
      if (ready == 0)
        return 0;
      char buf[4096];
      const ssize_t n = ::read(fd_, buf, sizeof buf);
      if (n < 0 && errno == EINTR)
        return 0;
      if (n <= 0)
        closed_ = true; // a last line without newline is dropped, the app always ends lines
      else
        buffer_.append(buf, static_cast<size_t>(n));
    }
  }

private:
  int fd_;
  std::string buffer_;
  bool closed_ = false;
};

std::atomic<int> interrupts{0};

void onInterrupt(int /*signal*/) {
  // The second Ctrl-C ends the command at once (the app then sees the connection close).
  if (interrupts.fetch_add(1) >= 1)
    ::_exit(WP_CLI_EXIT_CANCELLED);
}

} // namespace

std::unique_ptr<Connection> connectSocket(const std::string &path) {
  sockaddr_un addr{};
  if (path.empty() || path.size() >= sizeof addr.sun_path)
    return nullptr;
  addr.sun_family = AF_UNIX;
  std::memcpy(addr.sun_path, path.c_str(), path.size() + 1);
  // network-free: local unix socket (AF_UNIX), a file path
  const int fd = ::socket(AF_UNIX, SOCK_STREAM, 0);
  if (fd < 0)
    return nullptr;
#ifdef SO_NOSIGPIPE
  const int on = 1;
  ::setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, sizeof on);
#endif
  // network-free: local unix socket (AF_UNIX), a file path
  if (::connect(fd, reinterpret_cast<const sockaddr *>(&addr), sizeof addr) != 0) {
    ::close(fd);
    return nullptr;
  }
  return std::make_unique<SocketConnection>(fd);
}

void catchInterrupt() {
  // Writing to an app that went away must end with a message, not with SIGPIPE.
  std::signal(SIGPIPE, SIG_IGN);
  struct sigaction sa{};
  sa.sa_handler = onInterrupt;
  sigemptyset(&sa.sa_mask);
  sa.sa_flags = 0; // no SA_RESTART: poll returns at once
  sigaction(SIGINT, &sa, nullptr);
}

bool interrupted() { return interrupts.load() > 0; }

} // namespace wp::cli
