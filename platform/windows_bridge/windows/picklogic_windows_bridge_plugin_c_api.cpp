#include "include/picklogic_windows_bridge/picklogic_windows_bridge_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "picklogic_windows_bridge_plugin.h"

void PicklogicWindowsBridgePluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  picklogic_windows_bridge::PicklogicWindowsBridgePlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
