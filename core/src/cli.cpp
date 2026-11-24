// Command line of the desktop app (#140), see cli.hpp and wp_cli.h.
#include "cli.hpp"

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <iostream>
#include <sstream>
#include <thread>

#include "wp_cli.h"

namespace wp::cli {

namespace {

// Range of the settings, as in sound_gate.hpp (the app checks them again).
constexpr double kMinThreshold = -120.0;
constexpr double kMaxThreshold = 0.0;
constexpr double kMinSilence = 0.1;
constexpr double kMaxSilence = 60.0;

bool isHelp(const std::string &a) { return a == "--help" || a == "-h" || a == "help"; }

std::string usageError(const std::string &program, const std::string &command,
                       const std::string &message) {
  std::string hint = program;
  if (!command.empty())
    hint += " " + command;
  return message + "\nRun '" + hint + " --help' for the options.";
}

// A finite number in all of `text`, nothing else.
bool number(const std::string &text, double &value) {
  if (text.empty())
    return false;
  char *end = nullptr;
  value = std::strtod(text.c_str(), &end);
  return end == text.c_str() + text.size() && std::isfinite(value);
}

std::string jsonNumber(double v) {
  char buf[32];
  std::snprintf(buf, sizeof buf, "%.17g", v);
  return buf;
}

struct Option {
  explicit Option(const char *n) : name(n) {}
  const char *name;
  std::string value;
  bool given = false;
};

} // namespace

std::string jsonString(const std::string &s) {
  std::string out = "\"";
  for (const char ch : s) {
    const auto c = static_cast<unsigned char>(ch);
    switch (c) {
    case '"':
      out += "\\\"";
      break;
    case '\\':
      out += "\\\\";
      break;
    case '\n':
      out += "\\n";
      break;
    case '\r':
      out += "\\r";
      break;
    case '\t':
      out += "\\t";
      break;
    default:
      if (c < 0x20) {
        char buf[8];
        std::snprintf(buf, sizeof buf, "\\u%04x", c);
        out += buf;
      } else {
        out += ch; // UTF-8 passes through unchanged
      }
    }
  }
  return out + "\"";
}

std::string programName(const char *argv0) {
  std::string name = argv0 && *argv0 ? argv0 : "woodshed";
  const auto slash = name.find_last_of("/\\");
  return slash == std::string::npos ? name : name.substr(slash + 1);
}

std::string help(const std::string &program) {
  return "Usage: " + program +
         " <command> [options]\n"
         "\n"
         "Controls Woodshed Player on this computer. Starts the app if it is not running.\n"
         "\n"
         "Commands:\n"
         "  play     Load a title of the library and play it\n"
         "  record   Arm a recording: it starts with the first sound and ends after a pause\n"
         "\n"
         "Options:\n"
         "  -h, --help   Show this help\n"
         "\n"
         "Run '" +
         program + " <command> --help' for the options of a command.\n";
}

std::string helpPlay(const std::string &program) {
  return "Usage: " + program +
         " play --title <title> [--artist <artist>]\n"
         "\n"
         "Loads the title of the library with this title (and artist) and plays it.\n"
         "Upper and lower case do not count. Without --artist the title must be unique.\n"
         "\n"
         "Options:\n"
         "  --title <title>     Title of the track (required)\n"
         "  --artist <artist>   Artist of the track\n"
         "  -h, --help          Show this help\n"
         "\n"
         "Exit code 0 when it plays; 1 when no title or several titles match (they are listed).\n";
}

std::string helpRecord(const std::string &program) {
  return "Usage: " + program +
         " record [--title <title>] [--artist <artist>] [--source system|mic]\n"
         "       [--silence <seconds>] [--threshold <dBFS>]\n"
         "\n"
         "Arms a recording. The app records the source all the time but keeps nothing until the\n"
         "level rises above the threshold. The new title starts 1 s before the first sound and\n"
         "ends 2 s after the last one; a pause as long as --silence ends the recording. Shorter\n"
         "pauses stay in it. The command waits until the recording ends, then prints the title\n"
         "and its length. Ctrl-C while armed cancels without a title; Ctrl-C while recording\n"
         "stops and saves it.\n"
         "\n"
         "Options:\n"
         "  --title <title>       Title of the new track (default: date and time)\n"
         "  --artist <artist>     Artist of the new track\n"
         "  --source system|mic   System audio or microphone (default: the source last chosen\n"
         "                        in the app)\n"
         "  --silence <seconds>   Pause that ends the recording, 0.1 to 60 (default: 5)\n"
         "  --threshold <dBFS>    Level that counts as sound, -120 to 0 (default: -50)\n"
         "  -h, --help            Show this help\n"
         "\n"
         "Exit code 0 when saved, 1 when refused (a recording runs, no permission), 130 when\n"
         "cancelled while armed.\n";
}

Parsed parse(const std::vector<std::string> &args, const std::string &program) {
  Parsed p;
  if (args.empty())
    return p;
  const std::string &command = args[0];
  if (isHelp(command)) {
    p.kind = Parsed::Kind::Help;
    if (command == "help" && args.size() > 1) {
      if (args[1] == "play")
        p.text = helpPlay(program);
      else if (args[1] == "record")
        p.text = helpRecord(program);
      else {
        p.kind = Parsed::Kind::Error;
        p.text = usageError(program, "", "Unknown command '" + args[1] + "'.");
      }
    } else {
      p.text = help(program);
    }
    return p;
  }
  if (command != "play" && command != "record")
    return p;

  const bool record = command == "record";
  Option title("--title"), artist("--artist"), source("--source"), silence("--silence"),
      threshold("--threshold");
  std::vector<Option *> options{&title, &artist};
  if (record) {
    options.push_back(&source);
    options.push_back(&silence);
    options.push_back(&threshold);
  }
  auto fail = [&](const std::string &message) {
    p.kind = Parsed::Kind::Error;
    p.text = usageError(program, command, message);
    return p;
  };
  for (size_t i = 1; i < args.size(); ++i) {
    const std::string &a = args[i];
    if (isHelp(a) && a != "help") {
      p.kind = Parsed::Kind::Help;
      p.text = record ? helpRecord(program) : helpPlay(program);
      return p;
    }
    // --name value or --name=value
    const auto eq = a.find('=');
    const std::string name = a.rfind("--", 0) == 0 && eq != std::string::npos ? a.substr(0, eq) : a;
    Option *found = nullptr;
    for (Option *o : options)
      if (name == o->name)
        found = o;
    if (!found)
      return fail(a.rfind('-', 0) == 0 ? "Unknown option '" + a + "'."
                                       : "Unexpected argument '" + a + "'.");
    if (found->given)
      return fail(std::string("Option '") + found->name + "' is given twice.");
    if (name.size() < a.size()) {
      found->value = a.substr(eq + 1);
    } else if (i + 1 < args.size()) {
      found->value = args[++i];
    } else {
      return fail(std::string("Option '") + found->name + "' needs a value.");
    }
    found->given = true;
  }
  if (!record && (!title.given || title.value.empty()))
    return fail("play needs --title.");
  if (title.given && title.value.empty())
    return fail("--title must not be empty.");
  std::string json = "{\"version\":1,\"command\":" + jsonString(command);
  if (title.given)
    json += ",\"title\":" + jsonString(title.value);
  if (artist.given)
    json += ",\"artist\":" + jsonString(artist.value);
  if (source.given) {
    if (source.value != "system" && source.value != "mic")
      return fail("--source must be 'system' or 'mic'.");
    json += ",\"source\":" + jsonString(source.value);
  }
  if (silence.given) {
    double v = 0;
    if (!number(silence.value, v) || v < kMinSilence || v > kMaxSilence)
      return fail("--silence must be a number of seconds from 0.1 to 60.");
    json += ",\"silence\":" + jsonNumber(v);
  }
  if (threshold.given) {
    double v = 0;
    if (!number(threshold.value, v) || v < kMinThreshold || v > kMaxThreshold)
      return fail("--threshold must be a level in dBFS from -120 to 0.");
    json += ",\"threshold\":" + jsonNumber(v);
  }
  p.kind = Parsed::Kind::Request;
  p.request = json + "}";
  return p;
}

int converse(Connection &app, const std::string &request, std::ostream &out, std::ostream &err,
             const std::function<bool()> &interrupted) {
  if (!app.send(request)) {
    err << "Woodshed Player closed the connection.\n";
    return WP_CLI_EXIT_UNREACHABLE;
  }
  bool stopSent = false;
  std::string line;
  for (;;) {
    if (!stopSent && interrupted && interrupted()) {
      stopSent = true;
      app.send("stop"); // the app answers with the outcome; if it is gone, receive says so
    }
    const int got = app.receive(line, std::chrono::milliseconds(100));
    if (got < 0) {
      err << "Woodshed Player closed the connection.\n";
      return WP_CLI_EXIT_UNREACHABLE;
    }
    if (got == 0)
      continue;
    if (line.rfind("out ", 0) == 0) {
      out << line.substr(4) << '\n' << std::flush;
    } else if (line.rfind("err ", 0) == 0) {
      err << line.substr(4) << '\n' << std::flush;
    } else if (line.rfind("exit ", 0) == 0) {
      double code = 0;
      return number(line.substr(5), code) ? static_cast<int>(code) : WP_CLI_EXIT_FAILED;
    }
    // other lines: from a newer app, ignored
  }
}

std::unique_ptr<Connection> reach(const std::string &socketPath, const Connector &open,
                                  const std::function<void()> &launch, std::ostream &err,
                                  std::chrono::milliseconds timeout,
                                  std::chrono::milliseconds retry) {
  if (auto c = open(socketPath))
    return c;
  if (!launch) {
    err << "Woodshed Player is not running.\n";
    return nullptr;
  }
  err << "Starting Woodshed Player...\n" << std::flush;
  launch();
  const auto until = std::chrono::steady_clock::now() + timeout;
  while (std::chrono::steady_clock::now() < until) {
    std::this_thread::sleep_for(retry);
    if (auto c = open(socketPath))
      return c;
  }
  err << "Woodshed Player did not start within " << timeout.count() / 1000 << " s.\n";
  return nullptr;
}

int run(const std::vector<std::string> &args, const std::string &program,
        const std::string &socketPath, const Connector &open, const std::function<void()> &launch,
        const std::function<bool()> &interrupted, std::ostream &out, std::ostream &err) {
  const Parsed p = parse(args, program);
  switch (p.kind) {
  case Parsed::Kind::NotACommand:
    return WP_CLI_NOT_A_COMMAND;
  case Parsed::Kind::Help:
    out << p.text << std::flush;
    return WP_CLI_EXIT_OK;
  case Parsed::Kind::Error:
    err << p.text << '\n' << std::flush;
    return WP_CLI_EXIT_USAGE;
  case Parsed::Kind::Request:
    break;
  }
  auto app = reach(socketPath, open, launch, err);
  if (!app)
    return WP_CLI_EXIT_UNREACHABLE;
  return converse(*app, p.request, out, err, interrupted);
}

} // namespace wp::cli

extern "C" int wp_cli_main(int argc, const char *const *argv, const char *socket_path,
                           wp_cli_launch launch_app) {
  if (argc < 2 || !argv)
    return WP_CLI_NOT_A_COMMAND;
  std::vector<std::string> args;
  for (int i = 1; i < argc; ++i)
    args.emplace_back(argv[i] ? argv[i] : "");
  const std::string program = wp::cli::programName(argv[0]);
  if (wp::cli::parse(args, program).kind == wp::cli::Parsed::Kind::Request)
    wp::cli::catchInterrupt();
  std::function<void()> launch;
  if (launch_app)
    launch = launch_app;
  return wp::cli::run(args, program, socket_path ? socket_path : "", wp::cli::connectSocket, launch,
                      wp::cli::interrupted, std::cout, std::cerr);
}
