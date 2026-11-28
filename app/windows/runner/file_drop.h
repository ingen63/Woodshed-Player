// #163: audio files dragged from Explorer into the window. The drop target of the Flutter view
// reports them on «woodshed/files» like the Mac (MainFlutterWindow.swift): «dragFiles» {x, y} while
// audio files are over the window, «dragExit» when they leave, «dropFiles» {paths, x, y} on the
// drop. The position is in logical pixels of the view, the paths are UTF-8. Other files are skipped
// (#22/AK2). With WP_SMOKE=drop the channel «woodshed/dropSmoke» takes a drop put together like one
// from Explorer, for the smoke test (app/lib/app/drop_smoke.dart).
#ifndef RUNNER_FILE_DROP_H_
#define RUNNER_FILE_DROP_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>
// after windows.h
#include <ole2.h>

#include <memory>
#include <string>
#include <vector>

// Whether [path] (UTF-8) names a file type the app imports, as in the open dialog.
bool IsAudioPath(const std::string& path);

// The audio files of a drop from Explorer (CF_HDROP) as UTF-8 paths; empty if there are none.
std::vector<std::string> AudioPathsOf(IDataObject* data);

class FileDropTarget final : public IDropTarget {
 public:
  // Reports on [files] for the view [view]. Call Attach() to take drops.
  FileDropTarget(HWND view, flutter::MethodChannel<flutter::EncodableValue>* files,
                 flutter::BinaryMessenger* messenger);

  FileDropTarget(const FileDropTarget&) = delete;
  FileDropTarget& operator=(const FileDropTarget&) = delete;

  // Registers the view as drop target (OLE must be initialised); false if Windows refused.
  bool Attach();
  // Ends the registration and the reports; afterwards the channel may go.
  void Detach();

  // IUnknown
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** object) override;
  ULONG STDMETHODCALLTYPE AddRef() override;
  ULONG STDMETHODCALLTYPE Release() override;

  // IDropTarget
  HRESULT STDMETHODCALLTYPE DragEnter(IDataObject* data, DWORD keys, POINTL point,
                                      DWORD* effect) override;
  HRESULT STDMETHODCALLTYPE DragOver(DWORD keys, POINTL point, DWORD* effect) override;
  HRESULT STDMETHODCALLTYPE DragLeave() override;
  HRESULT STDMETHODCALLTYPE Drop(IDataObject* data, DWORD keys, POINTL point,
                                 DWORD* effect) override;

 private:
  ~FileDropTarget();

  // The position {x, y} of a screen point in logical pixels of the view.
  flutter::EncodableMap Position(POINTL point) const;
  void Send(const char* method, flutter::EncodableMap arguments);
  // Smoke test: [paths] dropped at [x], [y] (logical pixels) through the methods above.
  bool Simulate(const std::vector<std::string>& paths, double x, double y);

  LONG refs_ = 1;
  HWND view_;
  flutter::MethodChannel<flutter::EncodableValue>* files_;
  bool attached_ = false;
  // audio files are over the window (the drag that entered had some)
  bool audio_ = false;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> smoke_;
};

#endif  // RUNNER_FILE_DROP_H_
