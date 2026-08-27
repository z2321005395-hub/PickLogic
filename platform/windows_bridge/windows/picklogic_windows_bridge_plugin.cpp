#include "picklogic_windows_bridge_plugin.h"

// Windows headers must precede shell headers.
#include <windows.h>
#include <VersionHelpers.h>
#include <wincrypt.h>
#include <shellapi.h>
#include <shlobj.h>
#include <shobjidl.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <atomic>
#include <cstdint>
#include <cctype>
#include <cwchar>
#include <iterator>
#include <memory>
#include <optional>
#include <sstream>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

namespace picklogic_windows_bridge {

class DeleteCaptureSink final : public IFileOperationProgressSink {
 public:
  DeleteCaptureSink() = default;

  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid,
                                           void** object) override {
    if (object == nullptr) return E_POINTER;
    *object = nullptr;
    if (iid == IID_IUnknown || iid == IID_IFileOperationProgressSink) {
      *object = static_cast<IFileOperationProgressSink*>(this);
      AddRef();
      return S_OK;
    }
    return E_NOINTERFACE;
  }

  ULONG STDMETHODCALLTYPE AddRef() override { return ++reference_count_; }

  ULONG STDMETHODCALLTYPE Release() override {
    const ULONG remaining = --reference_count_;
    if (remaining == 0) delete this;
    return remaining;
  }

  HRESULT STDMETHODCALLTYPE StartOperations() override { return S_OK; }
  HRESULT STDMETHODCALLTYPE FinishOperations(HRESULT) override { return S_OK; }
  HRESULT STDMETHODCALLTYPE PreRenameItem(DWORD, IShellItem*, LPCWSTR) override {
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE PostRenameItem(DWORD, IShellItem*, LPCWSTR,
                                            HRESULT, IShellItem*) override {
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE PreMoveItem(DWORD, IShellItem*, IShellItem*,
                                        LPCWSTR) override {
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE PostMoveItem(DWORD, IShellItem*, IShellItem*,
                                         LPCWSTR, HRESULT,
                                         IShellItem*) override {
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE PreCopyItem(DWORD, IShellItem*, IShellItem*,
                                        LPCWSTR) override {
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE PostCopyItem(DWORD, IShellItem*, IShellItem*,
                                         LPCWSTR, HRESULT,
                                         IShellItem*) override {
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE PreDeleteItem(DWORD, IShellItem*) override {
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE PostDeleteItem(DWORD, IShellItem*, HRESULT status,
                                            IShellItem* newly_created) override {
    if (SUCCEEDED(status) && newly_created != nullptr) {
      if (recycled_item_ != nullptr) recycled_item_->Release();
      recycled_item_ = newly_created;
      recycled_item_->AddRef();
    }
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE PreNewItem(DWORD, IShellItem*, LPCWSTR) override {
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE PostNewItem(DWORD, IShellItem*, LPCWSTR, LPCWSTR,
                                        DWORD, HRESULT, IShellItem*) override {
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE UpdateProgress(UINT, UINT) override { return S_OK; }
  HRESULT STDMETHODCALLTYPE ResetTimer() override { return S_OK; }
  HRESULT STDMETHODCALLTYPE PauseTimer() override { return S_OK; }
  HRESULT STDMETHODCALLTYPE ResumeTimer() override { return S_OK; }

  IShellItem* TakeRecycledItem() {
    IShellItem* item = recycled_item_;
    recycled_item_ = nullptr;
    return item;
  }

 private:
  ~DeleteCaptureSink() {
    if (recycled_item_ != nullptr) recycled_item_->Release();
  }

  std::atomic<ULONG> reference_count_{1};
  IShellItem* recycled_item_ = nullptr;
};

class RecycleUndoStore {
 public:
  ~RecycleUndoStore() {
    for (auto& entry : entries_) entry.second.item->Release();
  }

  void Remember(const std::string& operation_id, IShellItem* item,
                std::wstring original_path) {
    const auto existing = entries_.find(operation_id);
    if (existing != entries_.end()) {
      existing->second.item->Release();
      entries_.erase(existing);
    }
    entries_.emplace(operation_id,
                     Entry{item, std::move(original_path)});
  }

  bool Restore(HWND parent, const std::string& operation_id) {
    const auto found = entries_.find(operation_id);
    if (found == entries_.end()) return false;
    const std::wstring& original = found->second.original_path;
    if (GetFileAttributesW(original.c_str()) != INVALID_FILE_ATTRIBUTES) {
      return false;
    }
    const size_t separator = original.find_last_of(L"\\/");
    if (separator == std::wstring::npos || separator + 1 >= original.size()) {
      return false;
    }
    const std::wstring parent_path = original.substr(0, separator);
    const std::wstring name = original.substr(separator + 1);
    if (GetFileAttributesW(parent_path.c_str()) == INVALID_FILE_ATTRIBUTES) {
      return false;
    }

    IShellItem* destination = nullptr;
    HRESULT status = SHCreateItemFromParsingName(
        parent_path.c_str(), nullptr, IID_PPV_ARGS(&destination));
    IFileOperation* operation = nullptr;
    if (SUCCEEDED(status)) {
      status = CoCreateInstance(CLSID_FileOperation, nullptr,
                                CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&operation));
    }
    if (SUCCEEDED(status)) status = operation->SetOwnerWindow(parent);
    if (SUCCEEDED(status)) {
      status = operation->SetOperationFlags(
          FOF_NOCONFIRMATION | FOF_NOERRORUI | FOF_SILENT |
          FOFX_ADDUNDORECORD);
    }
    if (SUCCEEDED(status)) {
      status = operation->MoveItem(found->second.item, destination,
                                   name.c_str(), nullptr);
    }
    if (SUCCEEDED(status)) status = operation->PerformOperations();
    BOOL aborted = FALSE;
    if (SUCCEEDED(status)) status = operation->GetAnyOperationsAborted(&aborted);
    if (operation != nullptr) operation->Release();
    if (destination != nullptr) destination->Release();
    if (FAILED(status) || aborted) return false;
    found->second.item->Release();
    entries_.erase(found);
    return true;
  }

 private:
  struct Entry {
    IShellItem* item;
    std::wstring original_path;
  };
  std::unordered_map<std::string, Entry> entries_;
};

namespace {

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) return std::wstring();
  const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                         value.data(),
                                         static_cast<int>(value.size()),
                                         nullptr, 0);
  if (length <= 0) return std::wstring();
  std::wstring output(length, L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                      static_cast<int>(value.size()), output.data(), length);
  return output;
}

std::string WideToUtf8(const std::wstring& value) {
  if (value.empty()) return std::string();
  const int length = WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, value.data(),
      static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
  if (length <= 0) return std::string();
  std::string output(length, '\0');
  WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.data(),
                      static_cast<int>(value.size()), output.data(), length,
                      nullptr, nullptr);
  return output;
}

bool SetClipboardBlock(UINT format, const void* data, SIZE_T size) {
  HGLOBAL memory = GlobalAlloc(GMEM_MOVEABLE, size);
  if (memory == nullptr) return false;
  void* target = GlobalLock(memory);
  if (target == nullptr) {
    GlobalFree(memory);
    return false;
  }
  CopyMemory(target, data, size);
  GlobalUnlock(memory);
  if (SetClipboardData(format, memory) == nullptr) {
    GlobalFree(memory);
    return false;
  }
  return true;
}

bool CopyRichTextToClipboard(HWND parent, const std::string& plain_text,
                             const std::string& rtf) {
  if (plain_text.empty() || rtf.empty() || plain_text.size() > 4 * 1024 * 1024 ||
      rtf.size() > 4 * 1024 * 1024) {
    return false;
  }
  const std::wstring plain_wide = Utf8ToWide(plain_text);
  if (plain_wide.empty()) return false;
  const UINT rich_text_format = RegisterClipboardFormatW(L"Rich Text Format");
  if (rich_text_format == 0 || !OpenClipboard(parent)) return false;
  bool success = EmptyClipboard() != FALSE;
  if (success) {
    success = SetClipboardBlock(
        CF_UNICODETEXT, plain_wide.c_str(),
        (plain_wide.size() + 1) * sizeof(wchar_t));
  }
  if (success) {
    success = SetClipboardBlock(rich_text_format, rtf.c_str(), rtf.size() + 1);
  }
  CloseClipboard();
  return success;
}

std::optional<std::string> StringArgument(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    const char* key) {
  const auto* arguments =
      std::get_if<flutter::EncodableMap>(call.arguments());
  if (arguments == nullptr) return std::nullopt;
  const auto found = arguments->find(flutter::EncodableValue(key));
  if (found == arguments->end()) return std::nullopt;
  const auto* value = std::get_if<std::string>(&found->second);
  if (value == nullptr || value->empty()) return std::nullopt;
  return *value;
}

std::optional<int32_t> IntArgument(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    const char* key) {
  const auto* arguments =
      std::get_if<flutter::EncodableMap>(call.arguments());
  if (arguments == nullptr) return std::nullopt;
  const auto found = arguments->find(flutter::EncodableValue(key));
  if (found == arguments->end()) return std::nullopt;
  if (const auto* value = std::get_if<int32_t>(&found->second)) return *value;
  if (const auto* value = std::get_if<int64_t>(&found->second)) {
    if (*value >= INT32_MIN && *value <= INT32_MAX) {
      return static_cast<int32_t>(*value);
    }
  }
  return std::nullopt;
}

bool IsSafeSecretName(const std::string& name) {
  if (name.empty() || name.size() > 64) return false;
  for (const unsigned char value : name) {
    if (!std::isalnum(value) && value != '-' && value != '_') return false;
  }
  return true;
}

std::optional<std::wstring> SecretPath(const std::string& name) {
  if (!IsSafeSecretName(name)) return std::nullopt;
  PWSTR local_app_data = nullptr;
  const HRESULT status = SHGetKnownFolderPath(
      FOLDERID_LocalAppData, KF_FLAG_DEFAULT, nullptr, &local_app_data);
  if (FAILED(status) || local_app_data == nullptr) return std::nullopt;
  std::wstring app_directory(local_app_data);
  CoTaskMemFree(local_app_data);
  app_directory += L"\\PickLogic";
  CreateDirectoryW(app_directory.c_str(), nullptr);
  app_directory += L"\\Secrets";
  CreateDirectoryW(app_directory.c_str(), nullptr);
  return app_directory + L"\\" + Utf8ToWide(name) + L".dpapi";
}

bool WriteBytes(const std::wstring& path, const BYTE* bytes, DWORD size) {
  HANDLE file = CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr,
                            CREATE_ALWAYS, FILE_ATTRIBUTE_HIDDEN, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  DWORD written = 0;
  const bool ok = WriteFile(file, bytes, size, &written, nullptr) != FALSE &&
                  written == size;
  CloseHandle(file);
  if (!ok) DeleteFileW(path.c_str());
  return ok;
}

std::optional<std::vector<BYTE>> ReadBytes(const std::wstring& path) {
  HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ,
                            nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL,
                            nullptr);
  if (file == INVALID_HANDLE_VALUE) return std::nullopt;
  LARGE_INTEGER length = {};
  if (!GetFileSizeEx(file, &length) || length.QuadPart <= 0 ||
      length.QuadPart > 64 * 1024) {
    CloseHandle(file);
    return std::nullopt;
  }
  std::vector<BYTE> bytes(static_cast<size_t>(length.QuadPart));
  DWORD read = 0;
  const bool ok = ReadFile(file, bytes.data(), static_cast<DWORD>(bytes.size()),
                           &read, nullptr) != FALSE && read == bytes.size();
  CloseHandle(file);
  return ok ? std::optional<std::vector<BYTE>>(std::move(bytes))
            : std::nullopt;
}

std::optional<flutter::EncodableMap> LoadShellImage(
    const std::wstring& path, int requested_size) {
  IShellItem* item = nullptr;
  HRESULT status = SHCreateItemFromParsingName(path.c_str(), nullptr,
                                               IID_PPV_ARGS(&item));
  if (FAILED(status) || item == nullptr) return std::nullopt;
  IShellItemImageFactory* factory = nullptr;
  status = item->QueryInterface(IID_PPV_ARGS(&factory));
  item->Release();
  if (FAILED(status) || factory == nullptr) return std::nullopt;

  const SIZE requested = {requested_size, requested_size};
  HBITMAP bitmap = nullptr;
  bool icon_fallback = false;
  status = factory->GetImage(
      requested, static_cast<SIIGBF>(SIIGBF_THUMBNAILONLY |
                                     SIIGBF_BIGGERSIZEOK |
                                     SIIGBF_RESIZETOFIT),
      &bitmap);
  if (FAILED(status) || bitmap == nullptr) {
    icon_fallback = true;
    status = factory->GetImage(
        requested, static_cast<SIIGBF>(SIIGBF_ICONONLY |
                                       SIIGBF_BIGGERSIZEOK |
                                       SIIGBF_RESIZETOFIT),
        &bitmap);
  }
  factory->Release();
  if (FAILED(status) || bitmap == nullptr) return std::nullopt;

  BITMAP description = {};
  if (GetObjectW(bitmap, sizeof(description), &description) == 0) {
    DeleteObject(bitmap);
    return std::nullopt;
  }
  const int width = description.bmWidth;
  const int height = description.bmHeight < 0
                         ? -description.bmHeight
                         : description.bmHeight;
  if (width <= 0 || height <= 0 || width > 512 || height > 512) {
    DeleteObject(bitmap);
    return std::nullopt;
  }
  BITMAPINFO info = {};
  info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = width;
  info.bmiHeader.biHeight = -height;
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;
  std::vector<uint8_t> pixels(static_cast<size_t>(width) * height * 4);
  HDC screen = GetDC(nullptr);
  const int rows = GetDIBits(screen, bitmap, 0, height, pixels.data(), &info,
                             DIB_RGB_COLORS);
  ReleaseDC(nullptr, screen);
  DeleteObject(bitmap);
  if (rows != height) return std::nullopt;

  bool has_alpha = false;
  for (size_t index = 3; index < pixels.size(); index += 4) {
    if (pixels[index] != 0) {
      has_alpha = true;
      break;
    }
  }
  if (!has_alpha) {
    for (size_t index = 3; index < pixels.size(); index += 4) {
      pixels[index] = 255;
    }
  }
  flutter::EncodableMap values;
  values[flutter::EncodableValue("bgraBytes")] =
      flutter::EncodableValue(pixels);
  values[flutter::EncodableValue("width")] =
      flutter::EncodableValue(width);
  values[flutter::EncodableValue("height")] =
      flutter::EncodableValue(height);
  values[flutter::EncodableValue("isIconFallback")] =
      flutter::EncodableValue(icon_fallback);
  return values;
}

bool OpenPath(HWND parent, const std::wstring& path) {
  if (path.empty() || GetFileAttributesW(path.c_str()) == INVALID_FILE_ATTRIBUTES) {
    return false;
  }
  const auto result = reinterpret_cast<INT_PTR>(
      ShellExecuteW(parent, L"open", path.c_str(), nullptr, nullptr, SW_SHOWNORMAL));
  return result > 32;
}

bool RevealPath(const std::wstring& path) {
  if (path.empty() || GetFileAttributesW(path.c_str()) == INVALID_FILE_ATTRIBUTES) {
    return false;
  }
  PIDLIST_ABSOLUTE item = nullptr;
  const HRESULT parsed = SHParseDisplayName(path.c_str(), nullptr, &item, 0, nullptr);
  if (FAILED(parsed) || item == nullptr) return false;
  const HRESULT opened = SHOpenFolderAndSelectItems(item, 0, nullptr, 0);
  CoTaskMemFree(item);
  return SUCCEEDED(opened);
}

bool IsSafeOperationId(const std::string& value) {
  if (value.empty() || value.size() > 128) return false;
  for (const char character : value) {
    if ((character >= 'a' && character <= 'z') ||
        (character >= 'A' && character <= 'Z') ||
        (character >= '0' && character <= '9') || character == '-' ||
        character == '_') {
      continue;
    }
    return false;
  }
  return true;
}

struct RecycleResult {
  bool recycled = false;
  IShellItem* undo_item = nullptr;
};

RecycleResult RecyclePath(HWND parent, const std::wstring& path) {
  RecycleResult output;
  if (path.empty() ||
      GetFileAttributesW(path.c_str()) == INVALID_FILE_ATTRIBUTES) {
    return output;
  }
  IShellItem* source = nullptr;
  HRESULT status = SHCreateItemFromParsingName(
      path.c_str(), nullptr, IID_PPV_ARGS(&source));
  IFileOperation* operation = nullptr;
  if (SUCCEEDED(status)) {
    status = CoCreateInstance(CLSID_FileOperation, nullptr,
                              CLSCTX_INPROC_SERVER,
                              IID_PPV_ARGS(&operation));
  }
  if (SUCCEEDED(status)) status = operation->SetOwnerWindow(parent);
  if (SUCCEEDED(status)) {
    status = operation->SetOperationFlags(
        FOF_NOCONFIRMATION | FOF_NOERRORUI | FOF_SILENT |
        FOFX_RECYCLEONDELETE | FOFX_ADDUNDORECORD);
  }
  auto* sink = new DeleteCaptureSink();
  if (SUCCEEDED(status)) status = operation->DeleteItem(source, sink);
  if (SUCCEEDED(status)) status = operation->PerformOperations();
  BOOL aborted = FALSE;
  if (SUCCEEDED(status)) status = operation->GetAnyOperationsAborted(&aborted);
  output.recycled = SUCCEEDED(status) && !aborted;
  if (output.recycled) output.undo_item = sink->TakeRecycledItem();
  sink->Release();
  if (operation != nullptr) operation->Release();
  if (source != nullptr) source->Release();
  return output;
}

bool HasPdfExtension(const std::wstring& path) {
  constexpr wchar_t extension[] = L".pdf";
  constexpr int extension_length = 4;
  if (path.size() < extension_length) return false;
  return CompareStringOrdinal(path.data() + path.size() - extension_length,
                              extension_length, extension, extension_length,
                              TRUE) == CSTR_EQUAL;
}

void AddBrowseRoot(flutter::EncodableList* roots, const std::string& id,
                   const std::wstring& path, const std::string& kind) {
  if (path.empty() ||
      GetFileAttributesW(path.c_str()) == INVALID_FILE_ATTRIBUTES) {
    return;
  }
  flutter::EncodableMap root;
  root[flutter::EncodableValue("id")] = flutter::EncodableValue(id);
  root[flutter::EncodableValue("path")] =
      flutter::EncodableValue(WideToUtf8(path));
  root[flutter::EncodableValue("kind")] = flutter::EncodableValue(kind);
  roots->push_back(flutter::EncodableValue(root));
}

void AddKnownFolder(flutter::EncodableList* roots, REFKNOWNFOLDERID folder_id,
                    const std::string& id, const std::string& kind) {
  PWSTR raw_path = nullptr;
  const HRESULT status = SHGetKnownFolderPath(
      folder_id, KF_FLAG_DEFAULT, nullptr, &raw_path);
  if (SUCCEEDED(status) && raw_path != nullptr) {
    AddBrowseRoot(roots, id, std::wstring(raw_path), kind);
  }
  if (raw_path != nullptr) CoTaskMemFree(raw_path);
}

}  // namespace

// static
void PicklogicWindowsBridgePlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "picklogic_windows_bridge",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<PicklogicWindowsBridgePlugin>(
      registrar->GetView()->GetNativeWindow());

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

PicklogicWindowsBridgePlugin::PicklogicWindowsBridgePlugin(void* parent_window)
    : parent_window_(parent_window),
      recycle_undo_store_(std::make_unique<RecycleUndoStore>()) {}

PicklogicWindowsBridgePlugin::~PicklogicWindowsBridgePlugin() = default;

void PicklogicWindowsBridgePlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = method_call.method_name();
  const HWND parent = static_cast<HWND>(parent_window_);
  if (method == "getPlatformVersion") {
    std::ostringstream version_stream;
    version_stream << "Windows ";
    if (IsWindows10OrGreater()) {
      version_stream << "10+";
    } else if (IsWindows8OrGreater()) {
      version_stream << "8";
    } else if (IsWindows7OrGreater()) {
      version_stream << "7";
    }
    result->Success(flutter::EncodableValue(version_stream.str()));
    return;
  }

  if (method == "pickDirectory") {
    IFileOpenDialog* dialog = nullptr;
    HRESULT status = CoCreateInstance(CLSID_FileOpenDialog, nullptr,
                                      CLSCTX_INPROC_SERVER,
                                      IID_PPV_ARGS(&dialog));
    if (FAILED(status) || dialog == nullptr) {
      result->Error("dialog_unavailable",
                    "Windows could not open the directory picker.");
      return;
    }
    DWORD options = 0;
    dialog->GetOptions(&options);
    dialog->SetOptions(options | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM |
                       FOS_PATHMUSTEXIST);
    if (const auto title = StringArgument(method_call, "title")) {
      const std::wstring wide_title = Utf8ToWide(*title);
      if (!wide_title.empty()) dialog->SetTitle(wide_title.c_str());
    }
    status = dialog->Show(parent);
    if (status == HRESULT_FROM_WIN32(ERROR_CANCELLED)) {
      dialog->Release();
      result->Success(flutter::EncodableValue());
      return;
    }
    if (FAILED(status)) {
      dialog->Release();
      result->Error("dialog_failed", "Windows directory selection failed.");
      return;
    }
    IShellItem* item = nullptr;
    status = dialog->GetResult(&item);
    dialog->Release();
    if (FAILED(status) || item == nullptr) {
      result->Error("dialog_failed", "Windows returned no selected directory.");
      return;
    }
    PWSTR path = nullptr;
    status = item->GetDisplayName(SIGDN_FILESYSPATH, &path);
    item->Release();
    if (FAILED(status) || path == nullptr) {
      result->Error("dialog_failed", "The selected directory has no filesystem path.");
      return;
    }
    const std::string utf8_path = WideToUtf8(path);
    CoTaskMemFree(path);
    result->Success(flutter::EncodableValue(utf8_path));
    return;
  }

  if (method == "pickPdfFile" || method == "pickPdfFiles" ||
      method == "pickFiles") {
    const bool pdf_only = method != "pickFiles";
    const bool allow_multiple = method != "pickPdfFile";
    IFileOpenDialog* dialog = nullptr;
    HRESULT status = CoCreateInstance(CLSID_FileOpenDialog, nullptr,
                                      CLSCTX_INPROC_SERVER,
                                      IID_PPV_ARGS(&dialog));
    if (FAILED(status) || dialog == nullptr) {
      result->Error("dialog_unavailable",
                    "Windows could not open the PDF picker.");
      return;
    }
    if (pdf_only) {
      const COMDLG_FILTERSPEC filters[] = {
          {L"PDF documents (*.pdf)", L"*.pdf"},
      };
      status = dialog->SetFileTypes(1, filters);
      if (SUCCEEDED(status)) status = dialog->SetFileTypeIndex(1);
      if (SUCCEEDED(status)) status = dialog->SetDefaultExtension(L"pdf");
    }
    DWORD options = 0;
    if (SUCCEEDED(status)) status = dialog->GetOptions(&options);
    if (SUCCEEDED(status)) {
      status = dialog->SetOptions(
          options | FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST |
          FOS_FILEMUSTEXIST | (pdf_only ? FOS_STRICTFILETYPES : 0) |
          FOS_NOCHANGEDIR |
          (allow_multiple ? FOS_ALLOWMULTISELECT : 0));
    }
    if (FAILED(status)) {
      dialog->Release();
      result->Error("dialog_unavailable",
                    "Windows could not configure the PDF picker.");
      return;
    }
    if (const auto title = StringArgument(method_call, "title")) {
      const std::wstring wide_title = Utf8ToWide(*title);
      if (!wide_title.empty()) dialog->SetTitle(wide_title.c_str());
    }
    status = dialog->Show(parent);
    if (status == HRESULT_FROM_WIN32(ERROR_CANCELLED)) {
      dialog->Release();
      result->Success(flutter::EncodableValue());
      return;
    }
    if (FAILED(status)) {
      dialog->Release();
      result->Error("dialog_failed", "Windows PDF selection failed.");
      return;
    }
    if (allow_multiple) {
      IShellItemArray* items = nullptr;
      status = dialog->GetResults(&items);
      dialog->Release();
      if (FAILED(status) || items == nullptr) {
        result->Error("dialog_failed", "Windows returned no selected PDFs.");
        return;
      }
      DWORD count = 0;
      status = items->GetCount(&count);
      flutter::EncodableList selected_paths;
      if (SUCCEEDED(status)) selected_paths.reserve(count);
      for (DWORD index = 0; SUCCEEDED(status) && index < count; ++index) {
        IShellItem* item = nullptr;
        status = items->GetItemAt(index, &item);
        if (FAILED(status) || item == nullptr) break;
        PWSTR path = nullptr;
        status = item->GetDisplayName(SIGDN_FILESYSPATH, &path);
        item->Release();
        if (FAILED(status) || path == nullptr) break;
        const std::wstring selected_path(path);
        const std::string utf8_path = WideToUtf8(selected_path);
        CoTaskMemFree(path);
        const DWORD attributes = GetFileAttributesW(selected_path.c_str());
        if (attributes == INVALID_FILE_ATTRIBUTES ||
            (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0 ||
            (pdf_only && !HasPdfExtension(selected_path))) {
          status = E_INVALIDARG;
          break;
        }
        selected_paths.emplace_back(utf8_path);
      }
      items->Release();
      if (FAILED(status)) {
        result->Error("invalid_pdf",
                      pdf_only ? "A selected item is not a local PDF file."
                               : "A selected item is not a local file.");
        return;
      }
      result->Success(flutter::EncodableValue(selected_paths));
      return;
    }
    IShellItem* item = nullptr;
    status = dialog->GetResult(&item);
    dialog->Release();
    if (FAILED(status) || item == nullptr) {
      result->Error("dialog_failed", "Windows returned no selected PDF.");
      return;
    }
    PWSTR path = nullptr;
    status = item->GetDisplayName(SIGDN_FILESYSPATH, &path);
    item->Release();
    if (FAILED(status) || path == nullptr) {
      result->Error("dialog_failed", "The selected PDF has no filesystem path.");
      return;
    }
    const std::wstring selected_path(path);
    const std::string utf8_path = WideToUtf8(selected_path);
    CoTaskMemFree(path);
    const DWORD attributes = GetFileAttributesW(selected_path.c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES ||
        (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0 ||
        !HasPdfExtension(selected_path)) {
      result->Error("invalid_pdf", "The selected item is not a local PDF file.");
      return;
    }
    result->Success(flutter::EncodableValue(utf8_path));
    return;
  }

  if (method == "pickPdfSavePath") {
    IFileSaveDialog* dialog = nullptr;
    HRESULT status = CoCreateInstance(CLSID_FileSaveDialog, nullptr,
                                      CLSCTX_INPROC_SERVER,
                                      IID_PPV_ARGS(&dialog));
    if (FAILED(status) || dialog == nullptr) {
      result->Error("dialog_unavailable",
                    "Windows could not open the PDF save dialog.");
      return;
    }
    const COMDLG_FILTERSPEC filters[] = {
        {L"PDF documents (*.pdf)", L"*.pdf"},
    };
    status = dialog->SetFileTypes(1, filters);
    if (SUCCEEDED(status)) status = dialog->SetFileTypeIndex(1);
    if (SUCCEEDED(status)) status = dialog->SetDefaultExtension(L"pdf");
    DWORD options = 0;
    if (SUCCEEDED(status)) status = dialog->GetOptions(&options);
    if (SUCCEEDED(status)) {
      status = dialog->SetOptions(options | FOS_FORCEFILESYSTEM |
                                  FOS_PATHMUSTEXIST | FOS_STRICTFILETYPES |
                                  FOS_NOCHANGEDIR | FOS_OVERWRITEPROMPT);
    }
    if (const auto title = StringArgument(method_call, "title")) {
      const std::wstring wide_title = Utf8ToWide(*title);
      if (!wide_title.empty()) dialog->SetTitle(wide_title.c_str());
    }
    if (const auto suggested = StringArgument(method_call, "suggestedName")) {
      const std::wstring wide_name = Utf8ToWide(*suggested);
      if (!wide_name.empty() &&
          wide_name.find_first_of(L"\\/") == std::wstring::npos) {
        dialog->SetFileName(wide_name.c_str());
      }
    }
    if (FAILED(status)) {
      dialog->Release();
      result->Error("dialog_unavailable",
                    "Windows could not configure the PDF save dialog.");
      return;
    }
    status = dialog->Show(parent);
    if (status == HRESULT_FROM_WIN32(ERROR_CANCELLED)) {
      dialog->Release();
      result->Success(flutter::EncodableValue());
      return;
    }
    if (FAILED(status)) {
      dialog->Release();
      result->Error("dialog_failed", "Windows PDF save selection failed.");
      return;
    }
    IShellItem* item = nullptr;
    status = dialog->GetResult(&item);
    dialog->Release();
    if (FAILED(status) || item == nullptr) {
      result->Error("dialog_failed", "Windows returned no PDF save path.");
      return;
    }
    PWSTR path = nullptr;
    status = item->GetDisplayName(SIGDN_FILESYSPATH, &path);
    item->Release();
    if (FAILED(status) || path == nullptr) {
      result->Error("dialog_failed", "The PDF save target has no filesystem path.");
      return;
    }
    const std::string utf8_path = WideToUtf8(path);
    CoTaskMemFree(path);
    result->Success(flutter::EncodableValue(utf8_path));
    return;
  }

  if (method == "getApplicationSupportDirectory") {
    PWSTR local_app_data = nullptr;
    const HRESULT status = SHGetKnownFolderPath(
        FOLDERID_LocalAppData, KF_FLAG_DEFAULT, nullptr, &local_app_data);
    if (FAILED(status) || local_app_data == nullptr) {
      result->Error("app_support_unavailable",
                    "Windows could not locate Local AppData.");
      return;
    }
    std::wstring support_path(local_app_data);
    CoTaskMemFree(local_app_data);
    support_path += L"\\PickLogic";
    result->Success(flutter::EncodableValue(WideToUtf8(support_path)));
    return;
  }

  if (method == "getBrowseRoots") {
    flutter::EncodableList roots;
    const DWORD required = GetLogicalDriveStringsW(0, nullptr);
    if (required > 0) {
      std::vector<wchar_t> drives(required + 1, L'\0');
      if (GetLogicalDriveStringsW(required, drives.data()) > 0) {
        for (const wchar_t* drive = drives.data(); *drive != L'\0';
             drive += wcslen(drive) + 1) {
          const UINT type = GetDriveTypeW(drive);
          if (type == DRIVE_UNKNOWN || type == DRIVE_NO_ROOT_DIR) continue;
          const std::wstring path(drive);
          AddBrowseRoot(&roots, "drive:" + WideToUtf8(path), path, "drive");
        }
      }
    }
    AddKnownFolder(&roots, FOLDERID_Desktop, "desktop", "desktop");
    AddKnownFolder(&roots, FOLDERID_Documents, "documents", "documents");
    AddKnownFolder(&roots, FOLDERID_Downloads, "downloads", "downloads");
    result->Success(flutter::EncodableValue(roots));
    return;
  }

  if (method == "openItem" || method == "revealItem" ||
      method == "getPathAttributes") {
    const auto path_argument = StringArgument(method_call, "path");
    if (!path_argument) {
      result->Error("invalid_path", "A local filesystem path is required.");
      return;
    }
    const std::wstring path = Utf8ToWide(*path_argument);
    if (method == "openItem") {
      result->Success(flutter::EncodableValue(OpenPath(parent, path)));
      return;
    }
    if (method == "revealItem") {
      result->Success(flutter::EncodableValue(RevealPath(path)));
      return;
    }
    const DWORD attributes = GetFileAttributesW(path.c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES) {
      result->Success(flutter::EncodableValue());
      return;
    }
    flutter::EncodableMap values;
    values[flutter::EncodableValue("hidden")] = flutter::EncodableValue(
        (attributes & FILE_ATTRIBUTE_HIDDEN) != 0);
    values[flutter::EncodableValue("system")] = flutter::EncodableValue(
        (attributes & FILE_ATTRIBUTE_SYSTEM) != 0);
    values[flutter::EncodableValue("readOnly")] = flutter::EncodableValue(
        (attributes & FILE_ATTRIBUTE_READONLY) != 0);
    values[flutter::EncodableValue("directory")] = flutter::EncodableValue(
        (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0);
    result->Success(flutter::EncodableValue(values));
    return;
  }

  if (method == "getSystemDriveSummary") {
    wchar_t system_drive[16] = L"C:";
    const DWORD length = GetEnvironmentVariableW(
        L"SystemDrive", system_drive,
        static_cast<DWORD>(std::size(system_drive)));
    if (length == 0 || length >= std::size(system_drive)) {
      wcscpy_s(system_drive, L"C:");
    }
    std::wstring root(system_drive);
    root += L"\\";
    ULARGE_INTEGER available = {};
    ULARGE_INTEGER total = {};
    ULARGE_INTEGER free = {};
    if (!GetDiskFreeSpaceExW(root.c_str(), &available, &total, &free)) {
      result->Error("storage_unavailable",
                    "Windows could not read the system-drive summary.");
      return;
    }
    flutter::EncodableMap values;
    values[flutter::EncodableValue("root")] =
        flutter::EncodableValue(WideToUtf8(root));
    values[flutter::EncodableValue("totalBytes")] =
        flutter::EncodableValue(static_cast<int64_t>(total.QuadPart));
    values[flutter::EncodableValue("availableBytes")] =
        flutter::EncodableValue(static_cast<int64_t>(available.QuadPart));
    result->Success(flutter::EncodableValue(values));
    return;
  }

  if (method == "loadShellThumbnail") {
    const auto path_argument = StringArgument(method_call, "path");
    const auto size_argument = IntArgument(method_call, "size");
    if (!path_argument || !size_argument || *size_argument < 16 ||
        *size_argument > 512) {
      result->Error("invalid_thumbnail_request",
                    "A local path and a 16-512 pixel size are required.");
      return;
    }
    const auto thumbnail =
        LoadShellImage(Utf8ToWide(*path_argument), *size_argument);
    if (!thumbnail) {
      result->Success(flutter::EncodableValue());
      return;
    }
    result->Success(flutter::EncodableValue(*thumbnail));
    return;
  }

  if (method == "recycleItem") {
    const auto path_argument = StringArgument(method_call, "path");
    const auto operation_id = StringArgument(method_call, "operationId");
    if (!path_argument || !operation_id || !IsSafeOperationId(*operation_id)) {
      result->Error("invalid_recycle_request",
                    "A local path and bounded operation id are required.");
      return;
    }
    const std::wstring path = Utf8ToWide(*path_argument);
    RecycleResult recycled = RecyclePath(parent, path);
    const bool undo_available = recycled.undo_item != nullptr;
    if (undo_available) {
      recycle_undo_store_->Remember(*operation_id, recycled.undo_item, path);
    }
    flutter::EncodableMap values;
    values[flutter::EncodableValue("recycled")] =
        flutter::EncodableValue(recycled.recycled);
    values[flutter::EncodableValue("undoAvailable")] =
        flutter::EncodableValue(undo_available);
    result->Success(flutter::EncodableValue(values));
    return;
  }

  if (method == "restoreRecycledItem") {
    const auto operation_id = StringArgument(method_call, "operationId");
    if (!operation_id || !IsSafeOperationId(*operation_id)) {
      result->Error("invalid_restore_request",
                    "A bounded operation id is required.");
      return;
    }
    result->Success(flutter::EncodableValue(
        recycle_undo_store_->Restore(parent, *operation_id)));
    return;
  }

  if (method == "copyRichText") {
    const auto plain_text = StringArgument(method_call, "plainText");
    const auto rtf = StringArgument(method_call, "rtf");
    if (!plain_text || !rtf || rtf->rfind("{\\rtf", 0) != 0) {
      result->Error("invalid_rich_text",
                    "Plain text and a bounded RTF document are required.");
      return;
    }
    result->Success(flutter::EncodableValue(
        CopyRichTextToClipboard(parent, *plain_text, *rtf)));
    return;
  }

  if (method == "writeProtectedSecret") {
    const auto name = StringArgument(method_call, "name");
    const auto value = StringArgument(method_call, "value");
    const auto path = name ? SecretPath(*name) : std::nullopt;
    if (!name || !value || !path) {
      result->Error("invalid_secret", "A valid secret name and value are required.");
      return;
    }
    DATA_BLOB plain = {};
    plain.pbData = reinterpret_cast<BYTE*>(
        const_cast<char*>(value->data()));
    plain.cbData = static_cast<DWORD>(value->size());
    DATA_BLOB protected_data = {};
    if (!CryptProtectData(&plain, L"PickLogic protected setting", nullptr,
                          nullptr, nullptr, CRYPTPROTECT_UI_FORBIDDEN,
                          &protected_data)) {
      result->Error("secret_protection_failed",
                    "Windows could not protect this setting.");
      return;
    }
    const bool written = WriteBytes(*path, protected_data.pbData,
                                    protected_data.cbData);
    LocalFree(protected_data.pbData);
    if (!written) {
      result->Error("secret_write_failed",
                    "Windows could not store the protected setting.");
      return;
    }
    result->Success();
    return;
  }

  if (method == "readProtectedSecret") {
    const auto name = StringArgument(method_call, "name");
    const auto path = name ? SecretPath(*name) : std::nullopt;
    if (!name || !path) {
      result->Error("invalid_secret", "A valid secret name is required.");
      return;
    }
    const auto protected_bytes = ReadBytes(*path);
    if (!protected_bytes) {
      result->Success(flutter::EncodableValue());
      return;
    }
    DATA_BLOB protected_data = {};
    protected_data.pbData = const_cast<BYTE*>(protected_bytes->data());
    protected_data.cbData = static_cast<DWORD>(protected_bytes->size());
    DATA_BLOB plain = {};
    if (!CryptUnprotectData(&protected_data, nullptr, nullptr, nullptr,
                            nullptr, CRYPTPROTECT_UI_FORBIDDEN, &plain)) {
      result->Error("secret_read_failed",
                    "Windows could not unlock the protected setting.");
      return;
    }
    const std::string value(reinterpret_cast<char*>(plain.pbData),
                            plain.cbData);
    LocalFree(plain.pbData);
    result->Success(flutter::EncodableValue(value));
    return;
  }

  if (method == "deleteProtectedSecret") {
    const auto name = StringArgument(method_call, "name");
    const auto path = name ? SecretPath(*name) : std::nullopt;
    if (!name || !path) {
      result->Error("invalid_secret", "A valid secret name is required.");
      return;
    }
    if (!DeleteFileW(path->c_str()) &&
        GetLastError() != ERROR_FILE_NOT_FOUND) {
      result->Error("secret_delete_failed",
                    "Windows could not delete the protected setting.");
      return;
    }
    result->Success();
    return;
  }

  result->NotImplemented();
}

}  // namespace picklogic_windows_bridge
