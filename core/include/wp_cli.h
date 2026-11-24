/* Command line of the desktop app (#140). The program of the app runs wp_cli_main before it starts
 * as an app: with a command (play, record, help) it parses the arguments, prints help and errors,
 * sends the request to the running app over a local Unix domain socket and prints the app's answer;
 * without a command it returns WP_CLI_NOT_A_COMMAND and the program starts as an app. The macOS
 * runner calls it from AppDelegate.main; the Windows and Linux runners (#60) call the same function
 * with their own socket path and launcher. Messages are English only. Protocol (one UTF-8 line
 * each): request = JSON object {"version":1,"command":...}, then optionally "stop" (Ctrl-C); reply
 * = "out <text>", "err <text>", finally "exit <code>" (app/lib/app/command_line.dart). */
#ifndef WP_CLI_H
#define WP_CLI_H

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#define WP_CLI_API __declspec(dllexport)
#else
#define WP_CLI_API __attribute__((visibility("default"))) __attribute__((used))
#endif

/* Exit codes, the same as CliExit in app/lib/app/command_line.dart. */
#define WP_CLI_EXIT_OK 0
#define WP_CLI_EXIT_FAILED 1      /* no or several matching titles, refused, no permission */
#define WP_CLI_EXIT_USAGE 2       /* wrong arguments */
#define WP_CLI_EXIT_UNREACHABLE 3 /* the app did not start or did not answer */
#define WP_CLI_EXIT_CANCELLED 130 /* Ctrl-C while armed: nothing was recorded */
/* argv holds no command: start the app. */
#define WP_CLI_NOT_A_COMMAND -1

/* Starts the app when it is not running; returns at once (the command waits for the socket). */
typedef void (*wp_cli_launch)(void);

/* Runs the command in argv (argv[0] is the program, its file name appears in the help) and returns
 * its exit code, or WP_CLI_NOT_A_COMMAND if argv[1] is no command. socket_path is the socket file
 * of the running app; launch_app (may be NULL) is called once if no app answers there. */
WP_CLI_API int wp_cli_main(int argc, const char *const *argv, const char *socket_path,
                           wp_cli_launch launch_app);

#ifdef __cplusplus
}
#endif
#endif
