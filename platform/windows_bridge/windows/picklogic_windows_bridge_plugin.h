#ifndef FLUTTER_PLUGIN_PICKLOGIC_WINDOWS_BRIDGE_PLUGIN_H_
#define FLUTTER_PLUGIN_PICKLOGIC_WINDOWS_BRIDGE_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace picklogic_windows_bridge {

class RecycleUndoStore;

class PicklogicWindowsBridgePlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  explicit PicklogicWindowsBridgePlugin(void* parent_window = nullptr);

  virtual ~PicklogicWindowsBridgePlugin();

  // Disallow copy and assign.
  PicklogicWindowsBridgePlugin(const PicklogicWindowsBridgePlugin&) = delete;
  PicklogicWindowsBridgePlugin& operator=(const PicklogicWindowsBridgePlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

 private:
  void* parent_window_;
  std::unique_ptr<RecycleUndoStore> recycle_undo_store_;
};

}  // namespace picklogic_windows_bridge

#endif  // FLUTTER_PLUGIN_PICKLOGIC_WINDOWS_BRIDGE_PLUGIN_H_
