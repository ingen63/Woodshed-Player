#include "keychain_channel.h"

#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <wincred.h>

#include <string>
#include <vector>

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;

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

// The name of the credential in the Credential Manager («Windows Credentials», generic).
std::wstring Target(const std::string& key) { return L"Woodshed Player/" + Wide(key); }

const std::string* StringArg(const EncodableMap& args, const char* name) {
  const auto it = args.find(EncodableValue(name));
  return it == args.end() ? nullptr : std::get_if<std::string>(&it->second);
}

std::string LastError() { return "Credential Manager error " + std::to_string(::GetLastError()); }

}  // namespace

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> CreateKeychainChannel(
    flutter::BinaryMessenger* messenger) {
  auto channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "woodshed/keychain", &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([](const auto& call, auto result) {
    const std::string& method = call.method_name();
    if (method == "available") {
      result->Success(EncodableValue(true));  // the Credential Manager is part of every Windows
      return;
    }
    const auto* args = std::get_if<EncodableMap>(call.arguments());
    const std::string* key = args == nullptr ? nullptr : StringArg(*args, "key");
    if (key == nullptr) {
      result->Error("args", "key missing");
      return;
    }
    const std::wstring target = Target(*key);
    if (method == "read") {
      PCREDENTIALW cred = nullptr;
      if (!::CredReadW(target.c_str(), CRED_TYPE_GENERIC, 0, &cred)) {
        if (::GetLastError() == ERROR_NOT_FOUND) {
          result->Success();  // nothing stored: null, as SecItem's errSecItemNotFound on the Mac
        } else {
          result->Error("keychain", LastError());
        }
        return;
      }
      const auto* bytes = reinterpret_cast<const char*>(cred->CredentialBlob);
      std::string value(bytes, bytes + cred->CredentialBlobSize);
      ::CredFree(cred);
      result->Success(EncodableValue(value));
    } else if (method == "write") {
      const std::string* value = StringArg(*args, "value");
      if (value == nullptr) {
        result->Error("args", "value missing");
        return;
      }
      std::vector<BYTE> blob(value->begin(), value->end());
      CREDENTIALW cred = {};
      cred.Type = CRED_TYPE_GENERIC;
      cred.TargetName = const_cast<LPWSTR>(target.c_str());
      cred.CredentialBlobSize = static_cast<DWORD>(blob.size());
      cred.CredentialBlob = blob.data();
      // this user on this computer, never roaming to other computers of a domain
      cred.Persist = CRED_PERSIST_LOCAL_MACHINE;
      wchar_t user[] = L"Woodshed Player";
      cred.UserName = user;
      if (::CredWriteW(&cred, 0)) {
        result->Success();
      } else {
        result->Error("keychain", LastError());
      }
    } else if (method == "delete") {
      if (::CredDeleteW(target.c_str(), CRED_TYPE_GENERIC, 0) ||
          ::GetLastError() == ERROR_NOT_FOUND) {
        result->Success();
      } else {
        result->Error("keychain", LastError());
      }
    } else {
      result->NotImplemented();
    }
  });
  return channel;
}
