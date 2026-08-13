#include "picklogic_windows_bridge_plugin.h"

// Windows headers must precede shell headers.
#include <windows.h>
#include <VersionHelpers.h>
#include <shellapi.h>
#include <shlobj.h>
#include <shobjidl.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <cstdint>
#include <cwchar>
#include <iterator>
#include <memory>
#include <optional>
#include <sstream>
#include <string>
#include <vector>

namespace picklogic_windows_bridge {
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
    : parent_window_(parent_window) {}

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

  if (method == "pickPdfFile") {
    IFileOpenDialog* dialog = nullptr;
    HRESULT status = CoCreateInstance(CLSID_FileOpenDialog, nullptr,
                                      CLSCTX_INPROC_SERVER,
                                      IID_PPV_ARGS(&dialog));
    if (FAILED(status) || dialog == nullptr) {
      result->Error("dialog_unavailable",
                    "Windows could not open the PDF picker.");
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
                                  FOS_PATHMUSTEXIST | FOS_FILEMUSTEXIST |
                                  FOS_STRICTFILETYPES | FOS_NOCHANGEDIR);
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

  result->NotImplemented();
}

}  // namespace picklogic_windows_bridge
