// network-free: local unix socket (AF_UNIX only), see command_bridge.h
#include <winsock2.h>  // network-free: local unix socket, AF_UNIX

#include <afunix.h>

#include "command_bridge.h"

#include <flutter/standard_method_codec.h>

#include <atomic>
#include <cstring>
#include <deque>
#include <map>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;

enum class Kind { kOpen, kLine, kClosed };

struct Event {
  Kind kind;
  int id;
  std::string text;
};

std::wstring Wide(const std::string& text) {
  if (text.empty()) return std::wstring();
  const int n = ::MultiByteToWideChar(CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()),
                                      nullptr, 0);
  std::wstring out(n > 0 ? n : 0, L'\0');
  if (n > 0) {
    ::MultiByteToWideChar(CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()), out.data(), n);
  }
  return out;
}

}  // namespace

// Shared by the window and the socket threads, which may outlive the bridge.
struct CommandBridge::State {
  std::atomic<HWND> window{nullptr};
  std::mutex mutex;
  std::deque<Event> events;
  std::map<int, SOCKET> connections;
  SOCKET listener = INVALID_SOCKET;
  std::atomic<bool> stopping{false};
  int next_id = 1;

  void Post(Event e) {
    {
      std::lock_guard<std::mutex> lock(mutex);
      events.push_back(std::move(e));
    }
    if (HWND w = window.load()) ::PostMessage(w, CommandBridge::kMessage, 0, 0);
  }
};

namespace {

// Reads lines of one connection until it closes.
void Read(std::shared_ptr<CommandBridge::State> state, int id, SOCKET s) {
  std::string buffer;
  char chunk[4096];
  for (;;) {
    const int n = ::recv(s, chunk, sizeof chunk, 0);
    if (n <= 0) break;
    buffer.append(chunk, static_cast<size_t>(n));
    for (size_t nl; (nl = buffer.find('\n')) != std::string::npos;) {
      std::string line = buffer.substr(0, nl);
      if (!line.empty() && line.back() == '\r') line.pop_back();
      buffer.erase(0, nl + 1);
      state->Post({Kind::kLine, id, std::move(line)});
    }
  }
  {
    std::lock_guard<std::mutex> lock(state->mutex);
    state->connections.erase(id);
  }
  ::closesocket(s);
  state->Post({Kind::kClosed, id, std::string()});
}

void Accept(std::shared_ptr<CommandBridge::State> state, SOCKET listener) {
  while (!state->stopping) {
    const SOCKET s = ::accept(listener, nullptr, nullptr);
    if (s == INVALID_SOCKET) break;
    int id;
    {
      std::lock_guard<std::mutex> lock(state->mutex);
      id = state->next_id++;
      state->connections[id] = s;
    }
    state->Post({Kind::kOpen, id, std::string()});
    std::thread(Read, state, id, s).detach();
  }
}

// Listens on the socket file [path]; a file left by an earlier run is replaced.
bool Listen(const std::shared_ptr<CommandBridge::State>& state, const std::string& path) {
  if (state->listener != INVALID_SOCKET) return true;
  sockaddr_un addr{};
  if (path.empty() || path.size() >= sizeof addr.sun_path) return false;
  WSADATA data{};
  if (::WSAStartup(MAKEWORD(2, 2), &data) != 0) return false;
  ::DeleteFileW(Wide(path).c_str());
  addr.sun_family = AF_UNIX;
  std::memcpy(addr.sun_path, path.c_str(), path.size() + 1);
  // network-free: local unix socket (AF_UNIX), a file path
  const SOCKET s = ::socket(AF_UNIX, SOCK_STREAM, 0);
  if (s == INVALID_SOCKET) return false;
  if (::bind(s, reinterpret_cast<const sockaddr*>(&addr), sizeof addr) != 0 ||
      ::listen(s, 4) != 0) {
    ::closesocket(s);
    return false;
  }
  state->listener = s;
  std::thread(Accept, state, s).detach();
  return true;
}

SOCKET Find(const std::shared_ptr<CommandBridge::State>& state, int id) {
  std::lock_guard<std::mutex> lock(state->mutex);
  const auto it = state->connections.find(id);
  return it == state->connections.end() ? INVALID_SOCKET : it->second;
}

const EncodableValue* Arg(const EncodableValue* args, const char* key) {
  const auto* map = std::get_if<EncodableMap>(args);
  if (map == nullptr) return nullptr;
  const auto it = map->find(EncodableValue(key));
  return it == map->end() ? nullptr : &it->second;
}

}  // namespace

CommandBridge::CommandBridge(flutter::BinaryMessenger* messenger, HWND window)
    : channel_(std::make_unique<flutter::MethodChannel<EncodableValue>>(
          messenger, "woodshed/commands", &flutter::StandardMethodCodec::GetInstance())),
      state_(std::make_shared<State>()) {
  state_->window = window;
  std::shared_ptr<State> state = state_;
  channel_->SetMethodCallHandler([state](const auto& call, auto result) {
    const std::string& method = call.method_name();
    const EncodableValue* args = call.arguments();
    if (method == "listen") {
      const auto* path = std::get_if<std::string>(args);
      result->Success(EncodableValue(path != nullptr && Listen(state, *path)));
    } else if (method == "write") {
      const auto* id = Arg(args, "id") ? std::get_if<int32_t>(Arg(args, "id")) : nullptr;
      const auto* text =
          Arg(args, "text") ? std::get_if<std::string>(Arg(args, "text")) : nullptr;
      const SOCKET s = id ? Find(state, *id) : INVALID_SOCKET;
      if (s != INVALID_SOCKET && text != nullptr) {
        const std::string data = *text + "\n";
        size_t done = 0;
        while (done < data.size()) {
          const int n = ::send(s, data.data() + done, static_cast<int>(data.size() - done), 0);
          if (n <= 0) break;
          done += static_cast<size_t>(n);
        }
      }
      result->Success();
    } else if (method == "close") {
      const auto* id = std::get_if<int32_t>(args);
      const SOCKET s = id ? Find(state, *id) : INVALID_SOCKET;
      // The reading thread sees the end, closes the socket and reports «closed».
      if (s != INVALID_SOCKET) ::shutdown(s, SD_BOTH);
      result->Success();
    } else {
      result->NotImplemented();
    }
  });
}

CommandBridge::~CommandBridge() {
  state_->stopping = true;
  std::lock_guard<std::mutex> lock(state_->mutex);
  if (state_->listener != INVALID_SOCKET) ::closesocket(state_->listener);
  for (const auto& connection : state_->connections) ::shutdown(connection.second, SD_BOTH);
  state_->window = nullptr;
}

void CommandBridge::Deliver() {
  std::deque<Event> events;
  {
    std::lock_guard<std::mutex> lock(state_->mutex);
    events.swap(state_->events);
  }
  for (auto& e : events) {
    switch (e.kind) {
      case Kind::kOpen:
        channel_->InvokeMethod("open", std::make_unique<EncodableValue>(e.id));
        break;
      case Kind::kLine:
        channel_->InvokeMethod(
            "line", std::make_unique<EncodableValue>(EncodableMap{
                        {EncodableValue("id"), EncodableValue(e.id)},
                        {EncodableValue("text"), EncodableValue(std::move(e.text))}}));
        break;
      case Kind::kClosed:
        channel_->InvokeMethod("closed", std::make_unique<EncodableValue>(e.id));
        break;
    }
  }
}
