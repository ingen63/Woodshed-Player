// Command line of the desktop app (#140), see wp_cli.h. Platform-independent: arguments, help,
// request and the conversation with the app over a Connection. The transport (Unix domain socket,
// Ctrl-C) is in cli_posix.cpp; Windows (#60) adds its own file with the same functions.
#pragma once

#include <chrono>
#include <functional>
#include <memory>
#include <ostream>
#include <string>
#include <vector>

namespace wp::cli {

// What the arguments ask for.
struct Parsed {
  enum class Kind { NotACommand, Help, Request, Error };
  Kind kind = Kind::NotACommand;
  // Help: the help text. Error: the message (with a hint to --help).
  std::string text;
  // Request: the JSON line for the app (without the newline).
  std::string request;
};

// Parses `args` (without the program); `program` is the name shown in help and errors.
Parsed parse(const std::vector<std::string> &args, const std::string &program);

// Name of the program for help and errors: the file name of `argv0` ("woodshed" if there is none).
std::string programName(const char *argv0);

// Help of the program and of one command.
std::string help(const std::string &program);
std::string helpPlay(const std::string &program);
std::string helpRecord(const std::string &program);

// `s` as a JSON string with quotes.
std::string jsonString(const std::string &s);

// One connection to the app.
class Connection {
public:
  virtual ~Connection() = default;
  // Sends `line` and a newline; false if the app is gone.
  virtual bool send(const std::string &line) = 0;
  // Waits up to `timeout` for a line (without the newline): 1 = line, 0 = nothing yet, -1 = closed.
  virtual int receive(std::string &line, std::chrono::milliseconds timeout) = 0;

protected:
  Connection() = default;
  Connection(const Connection &) = default;
  Connection &operator=(const Connection &) = default;
};

// Sends `request` and prints the app's answer to `out` and `err` until its exit line, whose code it
// returns. Once `interrupted` turns true it sends "stop" (once). A closed connection without an
// exit line is WP_CLI_EXIT_UNREACHABLE.
int converse(Connection &app, const std::string &request, std::ostream &out, std::ostream &err,
             const std::function<bool()> &interrupted);

// How long the command waits for an app it has started.
constexpr std::chrono::milliseconds kStartTimeout{30000};
constexpr std::chrono::milliseconds kRetryInterval{100};

// Connects to the app at `socketPath`; if no app answers, calls `launch` once and tries again until
// `timeout`. nullptr if no app could be reached; `err` then has the reason.
using Connector = std::function<std::unique_ptr<Connection>(const std::string &)>;
std::unique_ptr<Connection> reach(const std::string &socketPath, const Connector &open,
                                  const std::function<void()> &launch, std::ostream &err,
                                  std::chrono::milliseconds timeout = kStartTimeout,
                                  std::chrono::milliseconds retry = kRetryInterval);

// The whole command, see wp_cli_main. `open` and `interrupted` come from the platform file.
int run(const std::vector<std::string> &args, const std::string &program,
        const std::string &socketPath, const Connector &open, const std::function<void()> &launch,
        const std::function<bool()> &interrupted, std::ostream &out, std::ostream &err);

// ---- Platform (cli_posix.cpp) ----

// Connection to the Unix domain socket `path`; nullptr if no app listens there.
std::unique_ptr<Connection> connectSocket(const std::string &path);
// Catches Ctrl-C from now on: the first one sets interrupted(), a second one ends the program
// with WP_CLI_EXIT_CANCELLED.
void catchInterrupt();
bool interrupted();

} // namespace wp::cli
