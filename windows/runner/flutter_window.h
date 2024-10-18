#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>

#include "win32_window.h"


//--------------------------------------------------------------------------------
// ログ出力用 24/07/17 yoki
#include <sstream>
#include <ctime>
#include <iomanip>

#define WM_APP_OUTPUTLOG  WM_APP + 1  // 別スレッドからのログ出力メッセージ用
//--------------------------------------------------------------------------------

//--------------------------------------------------------------------------------
// マウスイベント用 24/07/14 yoki
#include <chrono> // 高精度タイマー用
#include <thread> // 非同期処理用
enum MOUSE_TYPE {
  LEFT = 0,
  RIGHT,
  MIDDLE,
  X,
};
enum MOUSE_BUTTON {
  DOWN = 0,
  UP,
};
//--------------------------------------------------------------------------------

//--------------------------------------------------------------------------------
// (MethodChannel) 24/07/02 yoki
#include "flutter/method_channel.h"
#include "flutter/standard_method_codec.h"
#include "flutter/method_result.h"
#include "flutter/method_result_functions.h"
//--------------------------------------------------------------------------------

//--------------------------------------------------------------------------------
// (pigeon) 24/07/03 yoki
#include "messages.g.h"
using pigeon_messages::ErrorOr;
using pigeon_messages::FlutterError;
using pigeon_messages::MessageHostApi;
using pigeon_messages::MessageFlutterApi;
//--------------------------------------------------------------------------------


// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();


//--------------------------------------------------------------------------------
// ログ出力用 24/07/17 yoki
  std::string getLogTime();
  void outputLog(std::string message);

  // (pigeon)簡単に処理を呼べるようにバインド 24/08/15 yoki
  std::function<void (const std::string*)> funcOutputLog;
//--------------------------------------------------------------------------------

//--------------------------------------------------------------------------------
// マウスイベント取得用 24/07/10 yoki
  static FlutterWindow *m_pThis;
  static LRESULT CALLBACK llMouseProc(int nCode, WPARAM wp, LPARAM lp);
  void mouseHookEnable();
  void mouseHookDisable();
  void setLeftClickCheckFlg(bool flg);
  void setRightClickCheckFlg(bool flg);
  void setLeftDownDisabledTime(int64_t time);
  void setLeftUpDisabledTime(int64_t time);
  void setRightDownDisabledTime(int64_t time);
  void setRightUpDisabledTime(int64_t time);
//--------------------------------------------------------------------------------

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;


//--------------------------------------------------------------------------------
// マウスイベント取得用 24/07/10 yoki
  HHOOK mouseHook;

  bool click_check_flg[4];

  bool pressed_flg[4];
  std::chrono::steady_clock::time_point old_time_point[4][2];
  double disabled_time[4][2];
  bool disabled_flg[4][2];

  bool mouseButtonCheck(MOUSE_TYPE type, MOUSE_BUTTON button);

  void initMouseEvent();
  LRESULT mouseEvent(int nCode, WPARAM wp, LPARAM lp);

// (MethodChannel) 24/07/02 yoki
  std::unique_ptr<flutter::MethodChannel<>> method_channel_;
  void setMethodChannel(flutter::FlutterEngine *engine);

// (pigeon) 24/07/03 yoki
  std::unique_ptr<MessageHostApi> pigeonHostApi_;
  std::unique_ptr<MessageFlutterApi> pigeonFlutterApi_;
//--------------------------------------------------------------------------------
};


//--------------------------------------------------------------------------------
// (pigeon) 24/07/03 yoki
// pigeonで出力された「messages.g.h」を確認してクラスを継承すればOK?
class PigeonHostApi : public MessageHostApi {
  public:
    PigeonHostApi() {}
    virtual ~PigeonHostApi() {}

    std::optional<FlutterError> StartMouseEventListening();
    std::optional<FlutterError> CancelMouseEventListening();
    std::optional<FlutterError> SetLeftClickCheckFlg(bool flg);
    std::optional<FlutterError> SetRightClickCheckFlg(bool flg);
    std::optional<FlutterError> SetLeftDownDisabledTime(int64_t time);
    std::optional<FlutterError> SetLeftUpDisabledTime(int64_t time);
    std::optional<FlutterError> SetRightDownDisabledTime(int64_t time);
    std::optional<FlutterError> SetRightUpDisabledTime(int64_t time);
};
//--------------------------------------------------------------------------------

#endif  // RUNNER_FLUTTER_WINDOW_H_
