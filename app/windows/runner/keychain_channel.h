// #161: the channel «woodshed/keychain» of the Windows app (the Mac answers it in
// MainFlutterWindow.swift with SecItem): the refresh token of the cloud sign-in in the Windows
// Credential Manager (generic credential «Woodshed Player/<key>», only for the signed-in user).
#ifndef RUNNER_KEYCHAIN_CHANNEL_H_
#define RUNNER_KEYCHAIN_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <memory>

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> CreateKeychainChannel(
    flutter::BinaryMessenger* messenger);

#endif  // RUNNER_KEYCHAIN_CHANNEL_H_
