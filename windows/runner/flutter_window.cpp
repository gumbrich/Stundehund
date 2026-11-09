#include "flutter_window.h"

#include <optional>
#include <chrono>
#include <cstring>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"

namespace {
// GUID_LIDSWITCH_STATE_CHANGE, defined by the Windows power API.
constexpr GUID kLidSwitch = {0xba3e0f4d, 0xb817, 0x4094,
                            {0xa2, 0xd1, 0xd5, 0x63, 0x79, 0xe6, 0xa0, 0xf3}};
}

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  power_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "stundehund/power",
          &flutter::StandardMethodCodec::GetInstance());
#ifndef NDEBUG
  // Integration tests send real Win32 messages through the same window procedure
  // as the operating system. This injection endpoint is absent from releases.
  power_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        const auto* event = call.arguments()
            ? std::get_if<std::string>(call.arguments()) : nullptr;
        if (call.method_name() != "simulatePowerEvent" || !event) {
          result->NotImplemented();
          return;
        }
        if (*event == "suspend" || *event == "resume") {
          SendMessage(GetHandle(), WM_POWERBROADCAST,
              *event == "suspend" ? PBT_APMSUSPEND : PBT_APMRESUMEAUTOMATIC, 0);
        } else if (*event == "lidClosed" || *event == "lidOpened" ||
                   *event == "unrelated") {
          struct {
            GUID setting;
            DWORD length;
            DWORD value;
          } setting = {kLidSwitch, sizeof(DWORD), *event == "lidOpened" ? 1UL : 0UL};
          if (*event == "unrelated") setting.setting = GUID{};
          SendMessage(GetHandle(), WM_POWERBROADCAST, PBT_POWERSETTINGCHANGE,
              reinterpret_cast<LPARAM>(&setting));
        } else {
          result->Error("unknown_event", "Unknown simulated power event");
          return;
        }
        result->Success();
      });
#endif
  lid_notification_ = RegisterPowerSettingNotification(
      GetHandle(), &kLidSwitch, DEVICE_NOTIFY_WINDOW_HANDLE);
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (lid_notification_) {
    UnregisterPowerSettingNotification(lid_notification_);
    lid_notification_ = nullptr;
  }
  power_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::NotifySuspend() {
  if (!power_channel_) return;
  const auto timestamp = std::chrono::duration_cast<std::chrono::milliseconds>(
      std::chrono::system_clock::now().time_since_epoch()).count();
  power_channel_->InvokeMethod("suspend",
      std::make_unique<flutter::EncodableValue>(static_cast<int64_t>(timestamp)));
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Handle this before plugins, which may consume the message.
  if (message == WM_POWERBROADCAST) {
    if (wparam == PBT_APMSUSPEND) {
      NotifySuspend();
    } else if (wparam == PBT_POWERSETTINGCHANGE && lparam) {
      const auto* setting = reinterpret_cast<POWERBROADCAST_SETTING*>(lparam);
      if (IsEqualGUID(setting->PowerSetting, kLidSwitch) &&
          setting->DataLength == sizeof(DWORD)) {
        DWORD state;
        std::memcpy(&state, setting->Data, sizeof(state));
        if (state == 0) NotifySuspend();
      }
    }
    return TRUE;
  }
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
