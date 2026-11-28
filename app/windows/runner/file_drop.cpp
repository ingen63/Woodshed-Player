#include "file_drop.h"

#include <flutter/standard_method_codec.h>
#include <flutter_windows.h>
#include <shellapi.h>
#include <shlobj.h>
#include <wrl/client.h>

#include <cmath>
#include <cstring>
#include <utility>

#include "utils.h"

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using Microsoft::WRL::ComPtr;

std::wstring Wide(const std::string& text) {
  if (text.empty()) return std::wstring();
  const int n =
      ::MultiByteToWideChar(CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()), nullptr, 0);
  std::wstring out(n > 0 ? n : 0, L'\0');
  if (n > 0) {
    ::MultiByteToWideChar(CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()), out.data(), n);
  }
  return out;
}

// The smoke test of dropping files runs (WP_SMOKE=drop, tools/smoke_app.sh).
bool DropSmokeRequested() {
  wchar_t value[8] = {};
  const DWORD n = ::GetEnvironmentVariableW(L"WP_SMOKE", value, 8);
  return n > 0 && n < 8 && std::wstring(value) == L"drop";
}

}  // namespace

bool IsAudioPath(const std::string& path) {
  const size_t dot = path.find_last_of('.');
  const size_t sep = path.find_last_of("\\/");
  if (dot == std::string::npos || (sep != std::string::npos && dot < sep)) return false;
  std::string ext = path.substr(dot + 1);
  for (char& ch : ext) {
    if (ch >= 'A' && ch <= 'Z') ch = static_cast<char>(ch - 'A' + 'a');
  }
  // the types of the open dialog (files_channel.cpp)
  for (const char* known : {"mp3", "m4a", "aac", "wav", "aif", "aiff", "flac", "caf"}) {
    if (ext == known) return true;
  }
  return false;
}

std::vector<std::string> AudioPathsOf(IDataObject* data) {
  std::vector<std::string> paths;
  if (data == nullptr) return paths;
  FORMATETC format = {CF_HDROP, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
  STGMEDIUM medium = {};
  if (FAILED(data->GetData(&format, &medium))) return paths;
  const auto drop = static_cast<HDROP>(medium.hGlobal);
  const UINT count = ::DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0);
  for (UINT i = 0; i < count; ++i) {
    const UINT length = ::DragQueryFileW(drop, i, nullptr, 0);
    if (length == 0) continue;
    std::wstring path(length + 1, L'\0');
    if (::DragQueryFileW(drop, i, path.data(), length + 1) != length) continue;
    path.resize(length);
    // UTF-16 to UTF-8; a name that is no valid UTF-16 comes back empty and is skipped
    std::string utf8 = Utf8FromUtf16(path.c_str());
    if (!utf8.empty() && IsAudioPath(utf8)) paths.push_back(std::move(utf8));
  }
  ::ReleaseStgMedium(&medium);
  return paths;
}

FileDropTarget::FileDropTarget(HWND view, flutter::MethodChannel<EncodableValue>* files,
                               flutter::BinaryMessenger* messenger)
    : view_(view), files_(files) {
  if (!DropSmokeRequested()) return;
  smoke_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "woodshed/dropSmoke", &flutter::StandardMethodCodec::GetInstance());
  smoke_->SetMethodCallHandler([this](const auto& call, auto result) {
    const auto* args = std::get_if<EncodableMap>(call.arguments());
    if (call.method_name() != "drop" || args == nullptr) {
      result->NotImplemented();
      return;
    }
    std::vector<std::string> paths;
    double x = 0, y = 0;
    for (const auto& [key, value] : *args) {
      const auto* name = std::get_if<std::string>(&key);
      if (name == nullptr) continue;
      if (*name == "paths") {
        if (const auto* list = std::get_if<EncodableList>(&value)) {
          for (const auto& p : *list) {
            if (const auto* s = std::get_if<std::string>(&p)) paths.push_back(*s);
          }
        }
      } else if (const auto* number = std::get_if<double>(&value)) {
        if (*name == "x") x = *number;
        if (*name == "y") y = *number;
      }
    }
    result->Success(EncodableValue(Simulate(paths, x, y)));
  });
}

FileDropTarget::~FileDropTarget() = default;

bool FileDropTarget::Attach() {
  attached_ = SUCCEEDED(::RegisterDragDrop(view_, this));
  return attached_;
}

void FileDropTarget::Detach() {
  if (attached_) ::RevokeDragDrop(view_);
  attached_ = false;
  smoke_ = nullptr;
  files_ = nullptr;
}

HRESULT STDMETHODCALLTYPE FileDropTarget::QueryInterface(REFIID riid, void** object) {
  if (object == nullptr) return E_POINTER;
  if (riid == IID_IUnknown || riid == IID_IDropTarget) {
    *object = static_cast<IDropTarget*>(this);
    AddRef();
    return S_OK;
  }
  *object = nullptr;
  return E_NOINTERFACE;
}

ULONG STDMETHODCALLTYPE FileDropTarget::AddRef() {
  return static_cast<ULONG>(::InterlockedIncrement(&refs_));
}

ULONG STDMETHODCALLTYPE FileDropTarget::Release() {
  const LONG refs = ::InterlockedDecrement(&refs_);
  if (refs == 0) delete this;
  return static_cast<ULONG>(refs);
}

HRESULT STDMETHODCALLTYPE FileDropTarget::DragEnter(IDataObject* data, DWORD keys, POINTL point,
                                                    DWORD* effect) {
  audio_ = !AudioPathsOf(data).empty();
  return DragOver(keys, point, effect);
}

HRESULT STDMETHODCALLTYPE FileDropTarget::DragOver(DWORD keys, POINTL point, DWORD* effect) {
  if (effect == nullptr) return E_INVALIDARG;
  if (!audio_ || (*effect & DROPEFFECT_COPY) == 0) {
    *effect = DROPEFFECT_NONE;
    return S_OK;
  }
  *effect = DROPEFFECT_COPY;
  Send("dragFiles", Position(point));
  return S_OK;
}

HRESULT STDMETHODCALLTYPE FileDropTarget::DragLeave() {
  if (audio_) Send("dragExit", EncodableMap());
  audio_ = false;
  return S_OK;
}

HRESULT STDMETHODCALLTYPE FileDropTarget::Drop(IDataObject* data, DWORD keys, POINTL point,
                                               DWORD* effect) {
  if (effect == nullptr) return E_INVALIDARG;
  const bool lit = audio_;
  audio_ = false;
  const std::vector<std::string> paths = AudioPathsOf(data);
  if (paths.empty() || (*effect & DROPEFFECT_COPY) == 0) {
    *effect = DROPEFFECT_NONE;
    if (lit) Send("dragExit", EncodableMap());  // OLE sends no DragLeave after a drop
    return S_OK;
  }
  *effect = DROPEFFECT_COPY;
  EncodableList list;
  for (const auto& p : paths) list.push_back(EncodableValue(p));
  EncodableMap arguments = Position(point);
  arguments[EncodableValue("paths")] = EncodableValue(std::move(list));
  Send("dropFiles", std::move(arguments));
  return S_OK;
}

EncodableMap FileDropTarget::Position(POINTL point) const {
  POINT p = {point.x, point.y};
  ::ScreenToClient(view_, &p);
  // logical pixels: Flutter's device pixel ratio on Windows is the window's DPI / 96
  const double scale = FlutterDesktopGetDpiForHWND(view_) / 96.0;
  return EncodableMap{
      {EncodableValue("x"), EncodableValue(p.x / scale)},
      {EncodableValue("y"), EncodableValue(p.y / scale)},
  };
}

void FileDropTarget::Send(const char* method, EncodableMap arguments) {
  if (files_ == nullptr) return;
  files_->InvokeMethod(method, std::make_unique<EncodableValue>(std::move(arguments)));
}

bool FileDropTarget::Simulate(const std::vector<std::string>& paths, double x, double y) {
  if (!attached_) return false;
  // CF_HDROP as Explorer hands it over: DROPFILES, then the UTF-16 paths, each ended by a zero, and
  // a second zero at the end
  std::wstring list;
  for (const auto& p : paths) {
    list += Wide(p);
    list.push_back(L'\0');
  }
  list.push_back(L'\0');
  const size_t bytes = list.size() * sizeof(wchar_t);
  HGLOBAL global = ::GlobalAlloc(GHND, sizeof(DROPFILES) + bytes);
  if (global == nullptr) return false;
  auto* header = static_cast<DROPFILES*>(::GlobalLock(global));
  if (header == nullptr) {
    ::GlobalFree(global);
    return false;
  }
  header->pFiles = sizeof(DROPFILES);
  header->fWide = TRUE;
  std::memcpy(reinterpret_cast<char*>(header) + sizeof(DROPFILES), list.data(), bytes);
  ::GlobalUnlock(global);
  ComPtr<IDataObject> data;
  FORMATETC format = {CF_HDROP, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
  STGMEDIUM medium = {};
  medium.tymed = TYMED_HGLOBAL;
  medium.hGlobal = global;
  if (FAILED(::SHCreateDataObject(nullptr, 0, nullptr, nullptr, IID_PPV_ARGS(&data))) ||
      FAILED(data->SetData(&format, &medium, TRUE))) {
    ::GlobalFree(global);
    return false;
  }
  // the point on the screen, as the mouse would give it
  const double scale = FlutterDesktopGetDpiForHWND(view_) / 96.0;
  POINT p = {static_cast<LONG>(std::lround(x * scale)), static_cast<LONG>(std::lround(y * scale))};
  ::ClientToScreen(view_, &p);
  const POINTL at = {p.x, p.y};
  // Explorer offers copy, move and link
  const DWORD offered = DROPEFFECT_COPY | DROPEFFECT_MOVE | DROPEFFECT_LINK;
  DWORD effect = offered;
  DragEnter(data.Get(), MK_LBUTTON, at, &effect);
  if (effect == DROPEFFECT_NONE) {
    DragLeave();
    return false;
  }
  effect = offered;
  DragOver(MK_LBUTTON, at, &effect);
  effect = offered;
  Drop(data.Get(), MK_LBUTTON, at, &effect);
  return effect == DROPEFFECT_COPY;
}
