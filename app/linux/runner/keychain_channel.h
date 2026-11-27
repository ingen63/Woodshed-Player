// #161: the channel «woodshed/keychain» of the Linux app (the Mac answers it in
// MainFlutterWindow.swift with SecItem): the refresh token of the cloud sign-in in the Secret Service
// of the desktop (GNOME Keyring, KWallet) through libsecret. libsecret (LGPL) is a system library: it is
// loaded at run time (dlopen), never linked or shipped. Without it «available» answers false and the
// app offers no sync (app/linux/SYSTEM-LIBRARIES.txt).
#ifndef RUNNER_KEYCHAIN_CHANNEL_H_
#define RUNNER_KEYCHAIN_CHANNEL_H_

#include <flutter_linux/flutter_linux.h>

// Answers «woodshed/keychain» on [messenger].
FlMethodChannel* keychain_channel_new(FlBinaryMessenger* messenger);

#endif  // RUNNER_KEYCHAIN_CHANNEL_H_
