// Command line of the desktop app (#140): arguments, help, the request and the conversation with a
// fake app over a real Unix domain socket in the temp folder, starting the app when none answers.
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <unistd.h>

#include <atomic>
#include <chrono>
#include <csignal>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <functional>
#include <sstream>
#include <string>
#include <thread>
#include <utility>
#include <vector>

#include "cli.hpp"
#include "wp_cli.h"

namespace {

int failures = 0;
int checks = 0;

#define CHECK(cond)                                                                                \
  do {                                                                                             \
    ++checks;                                                                                      \
    if (!(cond)) {                                                                                 \
      ++failures;                                                                                  \
      std::printf("  FAILED %s:%d: %s\n", __FILE__, __LINE__, #cond);                              \
    }                                                                                              \
  } while (0)

using wp::cli::Connection;
using wp::cli::parse;
using wp::cli::Parsed;
using Kind = Parsed::Kind;

namespace fs = std::filesystem;

bool contains(const std::string &text, const std::string &part) {
  return text.find(part) != std::string::npos;
}

Parsed p(const std::vector<std::string> &args) { return parse(args, "woodshed"); }

// ---- Arguments ----

void notACommandStartsTheApp() { // #140/AK16: the program without a command is the app
  CHECK(p({}).kind == Kind::NotACommand);
  CHECK(p({"-NSDocumentRevisionsDebugMode", "YES"}).kind == Kind::NotACommand);
  CHECK(p({"-psn_0_12345"}).kind == Kind::NotACommand);
  CHECK(p({"Play"}).kind == Kind::NotACommand);
  const char *argv[] = {"/Applications/Woodshed Player.app/Contents/MacOS/Woodshed Player"};
  CHECK(wp_cli_main(1, argv, "/nonexistent.sock", nullptr) == WP_CLI_NOT_A_COMMAND);
  CHECK(wp_cli_main(0, nullptr, nullptr, nullptr) == WP_CLI_NOT_A_COMMAND);
}

void helpDescribesCommandsAndOptions() { // #140/AK18
  for (const auto &args : std::vector<std::vector<std::string>>{{"--help"}, {"-h"}, {"help"}}) {
    const Parsed r = p(args);
    CHECK(r.kind == Kind::Help);
    CHECK(contains(r.text, "Usage: woodshed <command>"));
    CHECK(contains(r.text, "play"));
    CHECK(contains(r.text, "record"));
  }
  for (const auto &args : std::vector<std::vector<std::string>>{
           {"play", "--help"}, {"play", "-h"}, {"help", "play"}, {"play", "--title", "x", "-h"}}) {
    const Parsed r = p(args);
    CHECK(r.kind == Kind::Help);
    CHECK(contains(r.text, "woodshed play --title <title> [--artist <artist>]"));
    CHECK(contains(r.text, "Upper and lower case do not count"));
  }
  for (const auto &args :
       std::vector<std::vector<std::string>>{{"record", "--help"}, {"help", "record"}}) {
    const Parsed r = p(args);
    CHECK(r.kind == Kind::Help);
    for (const char *option : {"--title", "--artist", "--year <year>", "four digits",
                               "--source system|mic", "--silence <seconds>", "--threshold <dBFS>",
                               "default: 5", "default: -50", "1 s before", "2 s after", "Ctrl-C"})
      CHECK(contains(r.text, option));
  }
  // The program name is the one the shell script runs under.
  CHECK(contains(parse({"--help"}, "ws").text, "Usage: ws <command>"));
  CHECK(p({"help", "stop"}).kind == Kind::Error);
  CHECK(contains(p({"help", "stop"}).text, "Unknown command 'stop'"));
}

void playRequest() { // #140/AK1, AK2
  CHECK(p({"play", "--title", "Blue Bossa", "--artist", "Trio"}).request ==
        R"({"version":1,"command":"play","title":"Blue Bossa","artist":"Trio"})");
  CHECK(p({"play", "--title=Blue Bossa"}).request ==
        R"({"version":1,"command":"play","title":"Blue Bossa"})");
  CHECK(p({"play", "--artist", "Trio", "--title", "x"}).kind == Kind::Request);
  // Quotes, backslashes, control characters and UTF-8 survive.
  CHECK(p({"play", "--title", "Say \"hi\"\\\n\x01 Étude"}).request ==
        "{\"version\":1,\"command\":\"play\",\"title\":\"Say \\\"hi\\\"\\\\\\n\\u0001 Étude\"}");
  CHECK(wp::cli::jsonString("a\tb\rc") == "\"a\\tb\\rc\"");
}

void playUsageErrors() { // #140/AK1
  const auto err = [](const std::vector<std::string> &args, const std::string &message) {
    const Parsed r = p(args);
    CHECK(r.kind == Kind::Error);
    CHECK(contains(r.text, message));
    CHECK(contains(r.text, "--help"));
  };
  err({"play"}, "play needs --title.");
  err({"play", "--title"}, "Option '--title' needs a value.");
  err({"play", "--title", ""}, "play needs --title.");
  err({"play", "--title", "a", "--title", "b"}, "given twice");
  err({"play", "--title", "a", "--source", "mic"}, "Unknown option '--source'");
  err({"play", "--title", "a", "extra"}, "Unexpected argument 'extra'");
  err({"play", "--name", "a"}, "Unknown option '--name'");
  CHECK(contains(p({"play"}).text, "Run 'woodshed play --help'"));
}

void recordRequest() { // #140/AK5, AK6, AK11
  CHECK(p({"record"}).request == R"({"version":1,"command":"record"})");
  CHECK(p({"record", "--title", "Take", "--artist", "Me", "--source", "mic", "--silence", "3",
           "--threshold", "-40.5"})
            .request ==
        R"({"version":1,"command":"record","title":"Take","artist":"Me","source":"mic",)"
        R"("silence":3,"threshold":-40.5})");
  CHECK(contains(p({"record", "--source=system"}).request, R"("source":"system")"));
  CHECK(contains(p({"record", "--silence", "0.1"}).request, R"("silence":0.10000000000000001)"));
  CHECK(contains(p({"record", "--silence", "60"}).request, R"("silence":60)"));
  CHECK(contains(p({"record", "--threshold", "-120"}).request, R"("threshold":-120)"));
  CHECK(contains(p({"record", "--threshold", "0"}).request, R"("threshold":0)"));
}

void recordUsageErrors() { // #140/AK6, AK11
  const auto err = [](const std::vector<std::string> &args, const std::string &message) {
    const Parsed r = p(args);
    CHECK(r.kind == Kind::Error);
    CHECK(contains(r.text, message));
  };
  err({"record", "--source", "line"}, "--source must be 'system' or 'mic'.");
  err({"record", "--silence", "0.09"}, "--silence must be a number of seconds from 0.1 to 60.");
  err({"record", "--silence", "60.5"}, "--silence must be");
  err({"record", "--silence", "5s"}, "--silence must be");
  err({"record", "--silence", ""}, "--silence must be");
  err({"record", "--silence", "nan"}, "--silence must be");
  err({"record", "--threshold", "-120.1"}, "--threshold must be a level in dBFS from -120 to 0.");
  err({"record", "--threshold", "0.1"}, "--threshold must be");
  err({"record", "--threshold", "inf"}, "--threshold must be");
  err({"record", "--title", ""}, "--title must not be empty.");
  err({"record", "--silence"}, "Option '--silence' needs a value.");
}

void recordYear() { // #140/AK12a: --year goes to the app as a number, only for record
  CHECK(p({"record", "--year", "1937"}).request ==
        R"({"version":1,"command":"record","year":1937})");
  CHECK(contains(p({"record", "--year=0001"}).request, R"("year":1)"));
  CHECK(contains(p({"record", "--year", "9999"}).request, R"("year":9999)"));
  CHECK(contains(p({"record", "--title", "T", "--year", "1928", "--artist", "A"}).request,
                 R"("title":"T","artist":"A","year":1928)"));
  for (const char *bad : {"0000", "37", "19370", "19x7", "", " 1937", "-937", "+937", "1e3"}) {
    const Parsed r = p({"record", "--year", bad});
    CHECK(r.kind == Kind::Error);
    CHECK(contains(r.text, "--year must be a year of four digits, e.g. 1937."));
  }
  CHECK(contains(p({"record", "--year"}).text, "Option '--year' needs a value."));
  CHECK(contains(p({"record", "--year", "1937", "--year", "1938"}).text, "given twice"));
  CHECK(contains(p({"play", "--title", "T", "--year", "1937"}).text, "Unknown option '--year'"));
  // wrong value: no request, so the recording is never armed (exit code 2)
  std::ostringstream out, err;
  int launched = 0;
  CHECK(wp::cli::run(
            {"record", "--year", "37"}, "woodshed", "/nonexistent.sock",
            [](const std::string &) { return std::unique_ptr<Connection>(); }, [&] { ++launched; },
            [] { return false; }, out, err) == WP_CLI_EXIT_USAGE);
  CHECK(launched == 0);
}

void usageErrorExitsTwo() { // #140/AK18
  std::ostringstream out, err;
  int launched = 0;
  const int code = wp::cli::run(
      {"play"}, "woodshed", "/nonexistent.sock",
      [](const std::string &) { return std::unique_ptr<Connection>(); }, [&] { ++launched; },
      [] { return false; }, out, err);
  CHECK(code == WP_CLI_EXIT_USAGE);
  CHECK(contains(err.str(), "play needs --title."));
  CHECK(out.str().empty());
  CHECK(launched == 0); // no app needed for an error
  std::ostringstream hout, herr;
  CHECK(wp::cli::run({"--help"}, "woodshed", "", nullptr, nullptr, nullptr, hout, herr) ==
        WP_CLI_EXIT_OK);
  CHECK(contains(hout.str(), "Usage:"));
  CHECK(herr.str().empty());
}

// ---- Conversation with the app ----

// Scripted app: records what the command sends, answers with `replies`.
class FakeApp : public Connection {
public:
  explicit FakeApp(std::vector<std::string> replies) : replies_(std::move(replies)) {}
  bool send(const std::string &line) override {
    sent.push_back(line);
    return alive;
  }
  int receive(std::string &line, std::chrono::milliseconds) override {
    if (waits > 0) {
      --waits;
      return 0;
    }
    if (next_ >= replies_.size())
      return -1;
    line = replies_[next_++];
    return 1;
  }
  std::vector<std::string> sent;
  bool alive = true;
  int waits = 0;

private:
  std::vector<std::string> replies_;
  size_t next_ = 0;
};

void conversePrintsTheAnswer() { // #140/AK3, AK13
  FakeApp app({"out Armed", "err Only silence", "out Saved \"Take\", 00:12.", "exit 0", "out x"});
  std::ostringstream out, err;
  CHECK(wp::cli::converse(app, "{}", out, err, [] { return false; }) == 0);
  CHECK(out.str() == "Armed\nSaved \"Take\", 00:12.\n");
  CHECK(err.str() == "Only silence\n");
  CHECK(app.sent == std::vector<std::string>{"{}"});
  FakeApp failed({"err No title \"x\" in the library.", "unknown line", "exit 1"});
  std::ostringstream out2, err2;
  CHECK(wp::cli::converse(failed, "{}", out2, err2, nullptr) == WP_CLI_EXIT_FAILED);
  CHECK(err2.str() == "No title \"x\" in the library.\n");
  CHECK(out2.str().empty());
  FakeApp cancelled({"exit 130"});
  CHECK(wp::cli::converse(cancelled, "{}", out2, err2, nullptr) == WP_CLI_EXIT_CANCELLED);
  FakeApp garbled({"exit x"});
  CHECK(wp::cli::converse(garbled, "{}", out2, err2, nullptr) == WP_CLI_EXIT_FAILED);
}

void converseSendsStopOnceAfterCtrlC() { // #140/AK14
  FakeApp app({"out Recording.", "out Saved.", "exit 0"});
  app.waits = 3;
  int asked = 0;
  std::ostringstream out, err;
  CHECK(wp::cli::converse(app, "{}", out, err, [&] { return ++asked >= 2; }) == 0);
  CHECK(app.sent == (std::vector<std::string>{"{}", "stop"}));
}

void converseWithoutExitIsUnreachable() { // #140/AK16
  FakeApp gone({"out Armed"});
  std::ostringstream out, err;
  CHECK(wp::cli::converse(gone, "{}", out, err, nullptr) == WP_CLI_EXIT_UNREACHABLE);
  CHECK(contains(err.str(), "closed the connection"));
  FakeApp deaf({});
  deaf.alive = false;
  std::ostringstream out2, err2;
  CHECK(wp::cli::converse(deaf, "{}", out2, err2, nullptr) == WP_CLI_EXIT_UNREACHABLE);
}

void reachStartsTheAppOnce() { // #140/AK16: a closed app is started
  std::ostringstream err;
  int launched = 0, tries = 0;
  auto c = wp::cli::reach(
      "x",
      [&](const std::string &path) -> std::unique_ptr<Connection> {
        CHECK(path == "x");
        return ++tries >= 4 ? std::make_unique<FakeApp>(std::vector<std::string>{}) : nullptr;
      },
      [&] { ++launched; }, err, std::chrono::milliseconds(2000), std::chrono::milliseconds(1));
  CHECK(c != nullptr);
  CHECK(launched == 1);
  CHECK(tries == 4);
  CHECK(contains(err.str(), "Starting Woodshed Player"));
  // A running app: no launch, no message.
  std::ostringstream quiet;
  launched = 0;
  c = wp::cli::reach(
      "x",
      [](const std::string &) { return std::make_unique<FakeApp>(std::vector<std::string>{}); },
      [&] { ++launched; }, quiet);
  CHECK(c != nullptr);
  CHECK(launched == 0);
  CHECK(quiet.str().empty());
}

void reachGivesUp() { // #140/AK16
  std::ostringstream err;
  int launched = 0, tries = 0;
  const auto start = std::chrono::steady_clock::now();
  auto c = wp::cli::reach(
      "x",
      [&](const std::string &) {
        ++tries;
        return std::unique_ptr<Connection>();
      },
      [&] { ++launched; }, err, std::chrono::milliseconds(50), std::chrono::milliseconds(5));
  CHECK(c == nullptr);
  CHECK(launched == 1);
  CHECK(std::chrono::steady_clock::now() - start >= std::chrono::milliseconds(50));
  // one try before the launch, then one every 5 ms, not more often
  CHECK(tries >= 2);
  CHECK(tries <= 12);
  CHECK(contains(err.str(), "did not start within 0 s"));
  std::ostringstream err2;
  CHECK(wp::cli::reach(
            "x", [](const std::string &) { return std::unique_ptr<Connection>(); }, nullptr,
            err2) == nullptr);
  CHECK(contains(err2.str(), "is not running"));
}

// ---- A real Unix domain socket ----

std::string tempSocket() {
  static int counter = 0;
  const auto stamp = std::chrono::steady_clock::now().time_since_epoch().count() % 1000000;
  // short: sun_path holds 104 bytes; the test folder of macOS is long
  return "/tmp/wp_cli_" + std::to_string(stamp) + "_" + std::to_string(++counter) + ".sock";
}

// Listens on `path` and serves one connection with `serve` in a thread.
class SocketApp {
public:
  SocketApp(std::string path, std::function<void(int)> serve) : path_(std::move(path)) {
    fd_ = ::socket(AF_UNIX, SOCK_STREAM, 0);
    sockaddr_un addr{};
    addr.sun_family = AF_UNIX;
    std::strncpy(addr.sun_path, path_.c_str(), sizeof addr.sun_path - 1);
    ::unlink(path_.c_str());
    ok = ::bind(fd_, reinterpret_cast<const sockaddr *>(&addr), sizeof addr) == 0 &&
         ::listen(fd_, 1) == 0;
    if (ok)
      thread_ = std::thread([this, serve = std::move(serve)] {
        const int client = ::accept(fd_, nullptr, nullptr);
        if (client >= 0) {
          serve(client);
          ::close(client);
        }
      });
  }
  SocketApp(const SocketApp &) = delete;
  SocketApp &operator=(const SocketApp &) = delete;
  ~SocketApp() {
    if (thread_.joinable())
      thread_.join();
    ::close(fd_);
    ::unlink(path_.c_str());
  }
  bool ok = false;

private:
  std::string path_;
  int fd_ = -1;
  std::thread thread_;
};

std::string readLine(int fd) {
  std::string line;
  char c = 0;
  while (::read(fd, &c, 1) == 1 && c != '\n')
    line += c;
  return line;
}

void writeAll(int fd, const std::string &text) {
  if (::write(fd, text.data(), text.size()) != static_cast<ssize_t>(text.size()))
    std::printf("  short write\n");
}

void socketConversation() { // #140/AK1, AK19: request and answer over the local socket
  const std::string path = tempSocket();
  std::string request, second;
  {
    SocketApp app(path, [&](int fd) {
      request = readLine(fd);
      // The app takes longer than one wait of the command (100 ms) to answer.
      std::this_thread::sleep_for(std::chrono::milliseconds(250));
      // An answer in pieces, one line split across writes.
      writeAll(fd, "out Playing \"Blue");
      std::this_thread::sleep_for(std::chrono::milliseconds(20));
      writeAll(fd, " Bossa\".\nexit 0\n");
      second = readLine(fd);
    });
    CHECK(app.ok);
    std::ostringstream out, err;
    const int code = wp::cli::run({"play", "--title", "blue bossa"}, "woodshed", path,
                                  wp::cli::connectSocket, nullptr, nullptr, out, err);
    CHECK(code == 0);
    CHECK(out.str() == "Playing \"Blue Bossa\".\n");
    CHECK(err.str().empty());
  }
  CHECK(request == R"({"version":1,"command":"play","title":"blue bossa"})");
  CHECK(second.empty()); // nothing after the request: the command closed the connection
}

void socketStopOnCtrlC() { // #140/AK14: "stop" reaches the app
  const std::string path = tempSocket();
  std::string stop;
  std::atomic<bool> ctrlC{false};
  {
    SocketApp app(path, [&](int fd) {
      readLine(fd);
      writeAll(fd, "out Armed\n");
      ctrlC = true;
      stop = readLine(fd);
      writeAll(fd, "err Cancelled, nothing was recorded.\nexit 130\n");
    });
    std::ostringstream out, err;
    const int code = wp::cli::run(
        {"record"}, "woodshed", path, wp::cli::connectSocket, nullptr, [&] { return ctrlC.load(); },
        out, err);
    CHECK(code == WP_CLI_EXIT_CANCELLED);
    CHECK(out.str() == "Armed\n");
    CHECK(err.str() == "Cancelled, nothing was recorded.\n");
  }
  CHECK(stop == "stop");
}

void socketAppClosedEarly() { // #140/AK16
  const std::string path = tempSocket();
  {
    SocketApp app(path, [&](int fd) { readLine(fd); });
    std::ostringstream out, err;
    CHECK(wp::cli::run({"record"}, "woodshed", path, wp::cli::connectSocket, nullptr, nullptr, out,
                       err) == WP_CLI_EXIT_UNREACHABLE);
    CHECK(contains(err.str(), "closed the connection"));
  }
}

void socketStartsTheClosedApp() { // #140/AK16: no app listens; launching it makes it answer
  const std::string path = tempSocket();
  std::unique_ptr<SocketApp> app;
  int launched = 0;
  std::ostringstream out, err;
  const int code = wp::cli::run(
      {"play", "--title", "x"}, "woodshed", path, wp::cli::connectSocket,
      [&] {
        ++launched;
        app = std::make_unique<SocketApp>(path, [](int fd) {
          readLine(fd);
          writeAll(fd, "out Playing \"x\".\nexit 0\n");
        });
      },
      nullptr, out, err);
  CHECK(code == 0);
  CHECK(launched == 1);
  CHECK(out.str() == "Playing \"x\".\n");
  CHECK(contains(err.str(), "Starting Woodshed Player"));
  app.reset();
}

void socketMissingOrTooLong() { // #140/AK16
  CHECK(wp::cli::connectSocket("/nonexistent/wp.sock") == nullptr);
  CHECK(wp::cli::connectSocket("") == nullptr);
  CHECK(wp::cli::connectSocket("/tmp/" + std::string(200, 'x')) == nullptr);
  std::ostringstream out, err;
  CHECK(wp::cli::run({"play", "--title", "x"}, "woodshed", "/nonexistent/wp.sock",
                     wp::cli::connectSocket, nullptr, nullptr, out,
                     err) == WP_CLI_EXIT_UNREACHABLE);
  CHECK(contains(err.str(), "not running"));
}

void wpCliMainRunsTheCommand() { // #140/AK18: through the C entry point of the program
  const char *argv[] = {"/usr/local/bin/ws", "help", "record"};
  CHECK(wp_cli_main(3, argv, "", nullptr) == WP_CLI_EXIT_OK);
  const char *bad[] = {"ws", "play"};
  CHECK(wp_cli_main(2, bad, "", nullptr) == WP_CLI_EXIT_USAGE);
  const char *play[] = {"ws", "play", "--title", "x"};
  CHECK(wp_cli_main(4, play, "/nonexistent/wp.sock", nullptr) == WP_CLI_EXIT_UNREACHABLE);
  CHECK(!wp::cli::interrupted());
}

void programNameIsTheFileName() { // #140/AK18: the help names the shell script
  CHECK(wp::cli::programName("/usr/local/bin/ws") == "ws");
  CHECK(wp::cli::programName("ws") == "ws");
  CHECK(wp::cli::programName("C:\\bin\\ws.exe") == "ws.exe");
  CHECK(wp::cli::programName("/Applications/Woodshed Player.app/Contents/MacOS/Woodshed Player") ==
        "Woodshed Player");
  CHECK(wp::cli::programName("") == "woodshed");
  CHECK(wp::cli::programName(nullptr) == "woodshed");
}

bool catchesCtrlC() {
  struct sigaction now{};
  sigaction(SIGINT, nullptr, &now);
  return now.sa_handler != SIG_DFL && now.sa_handler != SIG_IGN;
}

void ctrlCIsCaughtOnlyForRequests() { // #140/AK14: help and errors keep the normal Ctrl-C
  const pid_t child = fork();
  if (child == 0) {
    std::signal(SIGINT, SIG_DFL); // an earlier test of this process caught it already
    const char *help[] = {"ws", "--help"};
    const char *bad[] = {"ws", "record", "--silence", "x"};
    const char *play[] = {"ws", "play", "--title", "x"};
    std::FILE *quiet = std::freopen("/dev/null", "w", stdout);
    (void)quiet;
    int code = 0;
    if (wp_cli_main(2, help, "", nullptr) != WP_CLI_EXIT_OK || catchesCtrlC())
      code |= 1;
    if (wp_cli_main(4, bad, "", nullptr) != WP_CLI_EXIT_USAGE || catchesCtrlC())
      code |= 2;
    if (wp_cli_main(4, play, "/nonexistent/wp.sock", nullptr) != WP_CLI_EXIT_UNREACHABLE ||
        !catchesCtrlC())
      code |= 4;
    ::_exit(code);
  }
  int status = 0;
  CHECK(waitpid(child, &status, 0) == child);
  CHECK(WIFEXITED(status));
  CHECK(WEXITSTATUS(status) == 0);
}

void secondCtrlCEndsTheCommand() { // #140/AK14: the first asks the app, the second ends at once
  int alive[2];
  CHECK(pipe(alive) == 0);
  const pid_t child = fork();
  if (child == 0) {
    ::close(alive[0]);
    wp::cli::catchInterrupt();
    const bool before = wp::cli::interrupted();
    std::raise(SIGINT);
    if (before || !wp::cli::interrupted())
      ::_exit(1);
    // still running after the first Ctrl-C
    if (::write(alive[1], "1", 1) != 1)
      ::_exit(3);
    std::raise(SIGINT); // ends the process with WP_CLI_EXIT_CANCELLED
    ::_exit(2);
  }
  ::close(alive[1]);
  char got = 0;
  CHECK(::read(alive[0], &got, 1) == 1);
  CHECK(got == '1');
  ::close(alive[0]);
  int status = 0;
  CHECK(waitpid(child, &status, 0) == child);
  CHECK(WIFEXITED(status));
  CHECK(WEXITSTATUS(status) == WP_CLI_EXIT_CANCELLED);
}

} // namespace

int main() {
  const std::vector<std::pair<std::string, std::function<void()>>> tests = {
      {"notACommandStartsTheApp", notACommandStartsTheApp},
      {"helpDescribesCommandsAndOptions", helpDescribesCommandsAndOptions},
      {"playRequest", playRequest},
      {"playUsageErrors", playUsageErrors},
      {"recordRequest", recordRequest},
      {"recordUsageErrors", recordUsageErrors},
      {"recordYear", recordYear},
      {"usageErrorExitsTwo", usageErrorExitsTwo},
      {"conversePrintsTheAnswer", conversePrintsTheAnswer},
      {"converseSendsStopOnceAfterCtrlC", converseSendsStopOnceAfterCtrlC},
      {"converseWithoutExitIsUnreachable", converseWithoutExitIsUnreachable},
      {"reachStartsTheAppOnce", reachStartsTheAppOnce},
      {"reachGivesUp", reachGivesUp},
      {"socketConversation", socketConversation},
      {"socketStopOnCtrlC", socketStopOnCtrlC},
      {"socketAppClosedEarly", socketAppClosedEarly},
      {"socketStartsTheClosedApp", socketStartsTheClosedApp},
      {"socketMissingOrTooLong", socketMissingOrTooLong},
      {"wpCliMainRunsTheCommand", wpCliMainRunsTheCommand},
      {"programNameIsTheFileName", programNameIsTheFileName},
      {"ctrlCIsCaughtOnlyForRequests", ctrlCIsCaughtOnlyForRequests},
      {"secondCtrlCEndsTheCommand", secondCtrlCEndsTheCommand},
  };
  for (const auto &[name, fn] : tests) {
    const int before = failures;
    fn();
    std::printf("%s %s\n", failures == before ? "ok  " : "FAIL", name.c_str());
  }
  std::printf("%d checks, %d failures\n", checks, failures);
  return failures == 0 ? 0 : 1;
}
