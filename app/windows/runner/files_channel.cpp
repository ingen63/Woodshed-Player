#include "files_channel.h"

#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <shellapi.h>
#include <shobjidl.h>
#include <wrl/client.h>

#include <string>

#include "command_line.h"
#include "utils.h"

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using Microsoft::WRL::ComPtr;

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

std::string PathOf(IShellItem* item) {
  PWSTR path = nullptr;
  std::string out;
  if (SUCCEEDED(item->GetDisplayName(SIGDN_FILESYSPATH, &path))) out = Utf8FromUtf16(path);
  ::CoTaskMemFree(path);
  return out;
}

// The audio files the user chooses (several); empty when cancelled. The file types the app imports
// (#22), as in the Mac's open panel.
EncodableList PickAudioFiles(HWND window) {
  EncodableList files;
  ComPtr<IFileOpenDialog> dialog;
  if (FAILED(::CoCreateInstance(CLSID_FileOpenDialog, nullptr, CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&dialog)))) {
    return files;
  }
  FILEOPENDIALOGOPTIONS options = 0;
  dialog->GetOptions(&options);
  dialog->SetOptions(options | FOS_ALLOWMULTISELECT | FOS_FILEMUSTEXIST | FOS_FORCEFILESYSTEM);
  const COMDLG_FILTERSPEC types[] = {
      {L"Audio", L"*.mp3;*.m4a;*.aac;*.wav;*.aif;*.aiff;*.flac;*.caf"},
      {L"*.*", L"*.*"},
  };
  dialog->SetFileTypes(2, types);
  if (FAILED(dialog->Show(window))) return files;
  ComPtr<IShellItemArray> items;
  if (FAILED(dialog->GetResults(&items))) return files;
  DWORD count = 0;
  items->GetCount(&count);
  for (DWORD i = 0; i < count; ++i) {
    ComPtr<IShellItem> item;
    if (SUCCEEDED(items->GetItemAt(i, &item))) {
      const std::string path = PathOf(item.Get());
      if (!path.empty()) files.push_back(EncodableValue(path));
    }
  }
  return files;
}

// #141: a folder; null when cancelled. [prompt] is the text of the button.
EncodableValue PickFolder(HWND window, const std::string* prompt) {
  ComPtr<IFileOpenDialog> dialog;
  if (FAILED(::CoCreateInstance(CLSID_FileOpenDialog, nullptr, CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&dialog)))) {
    return EncodableValue();
  }
  FILEOPENDIALOGOPTIONS options = 0;
  dialog->GetOptions(&options);
  dialog->SetOptions(options | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM);
  if (prompt != nullptr) dialog->SetOkButtonLabel(Wide(*prompt).c_str());
  ComPtr<IShellItem> item;
  if (FAILED(dialog->Show(window)) || FAILED(dialog->GetResult(&item))) return EncodableValue();
  const std::string path = PathOf(item.Get());
  return path.empty() ? EncodableValue() : EncodableValue(path);
}

// #162/AK3: whether Windows lets desktop apps use the microphone. The privacy settings
// (Settings › Privacy & security › Microphone) keep their switches in the consent store: for the
// device (HKLM), for this user and for desktop apps (NonPackaged). «Deny» in any of them refuses
// the microphone; a missing value counts as allowed (older Windows). The core reports a refusal it
// meets anyway (WP_REC_ERR_ACCESS_DENIED).
bool MicrophoneAllowed() {
  const wchar_t* store =
      L"Software\\Microsoft\\Windows\\CurrentVersion\\CapabilityAccessManager\\ConsentStore\\"
      L"microphone";
  const std::wstring desktop = std::wstring(store) + L"\\NonPackaged";
  const struct {
    HKEY root;
    const wchar_t* key;
  } switches[] = {{HKEY_LOCAL_MACHINE, store}, {HKEY_CURRENT_USER, store},
                  {HKEY_CURRENT_USER, desktop.c_str()}};
  for (const auto& s : switches) {
    wchar_t value[16] = {};
    DWORD size = sizeof value;
    if (::RegGetValueW(s.root, s.key, L"Value", RRF_RT_REG_SZ, nullptr, value, &size) ==
            ERROR_SUCCESS &&
        std::wstring(value) == L"Deny") {
      return false;
    }
  }
  return true;
}

}  // namespace

std::unique_ptr<flutter::MethodChannel<EncodableValue>> CreateFilesChannel(
    flutter::BinaryMessenger* messenger, HWND window) {
  auto channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "woodshed/files", &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([window](const auto& call, auto result) {
    const std::string& method = call.method_name();
    const auto* text = std::get_if<std::string>(call.arguments());
    if (method == "pickAudioFiles") {
      result->Success(EncodableValue(PickAudioFiles(window)));
    } else if (method == "pickFolder") {
      result->Success(PickFolder(window, text));
    } else if (method == "supportDir") {
      result->Success(EncodableValue(SupportDir()));
    } else if (method == "commandSocket") {
      result->Success(EncodableValue(CommandSocketPath()));
    } else if (method == "microphoneAccess") {
      result->Success(EncodableValue(MicrophoneAllowed()));  // #162/AK3
    } else if (method == "recordingsDir") {
      result->Success(EncodableValue(RecordingsDir()));  // #162/AK2
    } else if (method == "openUrl") {
      // #50/AK6: links of the About dialog open in the default browser; only https.
      if (text != nullptr && text->rfind("https://", 0) == 0) {
        ::ShellExecuteW(nullptr, L"open", Wide(*text).c_str(), nullptr, nullptr, SW_SHOWNORMAL);
      }
      result->Success();
    } else if (method == "buildInfo") {
      // #50/AK6: Git tag and build date, set by CMake when the build was configured.
      result->Success(EncodableValue(EncodableMap{
          {EncodableValue("tag"), EncodableValue(std::string(WP_GIT_TAG))},
          {EncodableValue("date"), EncodableValue(std::string(WP_BUILD_DATE))},
      }));
    } else if (method == "keepAwake" || method == "windowAppearance" ||
               method == "localizeMenuBar") {
      result->Success();
    } else {
      result->NotImplemented();
    }
  });
  return channel;
}
