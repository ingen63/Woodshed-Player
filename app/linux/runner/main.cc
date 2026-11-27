#include <dlfcn.h>
#include <limits.h>
#include <unistd.h>

#include <cstdio>
#include <cstring>
#include <string>

#include "files_channel.h"
#include "my_application.h"

namespace {

// #140, #60: wp_cli_main of the core (libwp_core.so in lib/ next to the program, see wp_cli.h).
using CliMain = int (*)(int, const char* const*, const char*, void (*)());

std::string executable_dir() {
  char path[PATH_MAX];
  const ssize_t n = readlink("/proc/self/exe", path, sizeof path - 1);
  if (n <= 0) return ".";
  path[n] = '\0';
  std::string p(path);
  return p.substr(0, p.rfind('/'));
}

// Starts a new instance of the app in the background; the command waits for its socket.
void launch_app() {
  const pid_t pid = fork();
  if (pid != 0) return;
  setsid();
  // A second fork, so the app is no child of the command (no zombie when the command ends).
  if (fork() != 0) _exit(0);
  FILE* null_in = freopen("/dev/null", "r", stdin);
  FILE* null_out = freopen("/dev/null", "w", stdout);
  FILE* null_err = freopen("/dev/null", "w", stderr);
  (void)null_in;
  (void)null_out;
  (void)null_err;
  const std::string self = executable_dir() + "/" + BINARY_NAME;
  execl(self.c_str(), self.c_str(), static_cast<char*>(nullptr));
  _exit(127);
}

bool is_command(const char* arg) {
  for (const char* c : {"play", "record", "help", "--help", "-h"}) {
    if (std::strcmp(arg, c) == 0) return true;
  }
  return false;
}

// The exit code of the command in argv, or -1 if argv holds none (start the app).
int run_command_line(int argc, char** argv) {
  // Only look further if the first argument may be a command; the app starts fast otherwise.
  if (argc < 2 || !is_command(argv[1])) return -1;
  const std::string lib = executable_dir() + "/lib/libwp_core.so";
  void* handle = dlopen(lib.c_str(), RTLD_NOW);
  auto cli = handle ? reinterpret_cast<CliMain>(dlsym(handle, "wp_cli_main")) : nullptr;
  if (cli == nullptr) {
    std::fputs("The command line is not available in this build.\n", stderr);
    return 1;
  }
  const std::string socket = command_socket_path();
  return cli(argc, argv, socket.c_str(), launch_app);
}

}  // namespace

int main(int argc, char** argv) {
  const int code = run_command_line(argc, argv);
  if (code != -1) return code;
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
