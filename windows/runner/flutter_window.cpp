#include "flutter_window.h"

#include <optional>

#include <flutter/encodable_value.h>

#include "flutter/generated_plugin_registrant.h"

namespace {
// How many times a reminder blinks the taskbar entry before it stops on its
// own. Enough to be noticed, short enough not to look like a fault.
constexpr UINT kFlashCycles = 3;
}  // namespace

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
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // One native call for the interval reminder: blink the taskbar entry. The
  // window is deliberately not brought forward — FlashWindowEx with
  // FLASHW_TIMERNOFG blinks until the user clicks it, which gets attention
  // without stealing it.
  alert_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "com.pomodoro/window_alert",
          &flutter::StandardMethodCodec::GetInstance());
  alert_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() != "flash") {
          result->NotImplemented();
          return;
        }
        FLASHWINFO info{};
        info.cbSize = sizeof(FLASHWINFO);
        info.hwnd = GetHandle();
        info.dwFlags = FLASHW_ALL | FLASHW_TIMERNOFG;
        info.uCount = kFlashCycles;
        info.dwTimeout = 0;
        result->Success(flutter::EncodableValue(FlashWindowEx(&info) != FALSE));
      });

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
  if (alert_channel_) {
    alert_channel_->SetMethodCallHandler(nullptr);
    alert_channel_ = nullptr;
  }

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
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
