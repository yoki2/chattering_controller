#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"


FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {
//--------------------------------------------------------------------------------
  mouseHookDisable(); // 終了時に必ず行う処理 24/07/10 yoki
//--------------------------------------------------------------------------------
}

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
//--------------------------------------------------------------------------------
// 何らかの処理を追加する場合はRegisterPlugins後かつSetChildContent前に行う事


  // マウスイベント取得関連の初期化処理 24/07/10 yoki
  initMouseEvent();


  // (MethodChannel) 24/07/02 yoki
  setMethodChannel(flutter_controller_->engine());


  // (pigeon)初期化 24/07/03 yoki
  pigeonHostApi_ = std::make_unique<PigeonHostApi>();
  MessageHostApi::SetUp(flutter_controller_->engine()->messenger(), pigeonHostApi_.get());


  // (pigeon)ネイティブからFlutter呼び出し用の初期化 24/08/15 yoki
  pigeonFlutterApi_ = std::make_unique<MessageFlutterApi>(flutter_controller_->engine()->messenger());


  // (pigeon)簡単に処理を呼べるようにバインド 24/08/15 yoki
  std::function<void(ErrorOr<int64_t> reply)> result; // エラー用のコールバック?
  funcOutputLog = std::bind(&MessageFlutterApi::OutputLog, *pigeonFlutterApi_,
    std::placeholders::_1,  // ログデータ用
    [](){}, // 戻り値がvoidなので未指定
    [result](const FlutterError& error) { result(error); }
  );


//--------------------------------------------------------------------------------
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
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {

//--------------------------------------------------------------------------------
  // 別スレッドからのログ出力メッセージ処理 24/08/16 yoki

  // ログ出力処理にoutputLogではpigeonでFlutterにログデータを渡す処理を行っているが、
  // メインスレッド以外のスレッド(疑似マウスイベント生成処理等)から呼ぶと
  // Flutterから警告メッセージが出るので、
  // イベントメッセージを送信してメインスレッドで処理するように対応
  if (message == WM_APP_OUTPUTLOG) {
    std::string *log = (std::string *)lparam;
    outputLog(*log);
  }
//--------------------------------------------------------------------------------

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


//--------------------------------------------------------------------------------
// ログ出力用 24/07/17 yoki
std::string FlutterWindow::getLogTime() {
  std::chrono::system_clock::time_point now = std::chrono::system_clock::now();
  time_t t = std::chrono::system_clock::to_time_t(now);
  struct tm lt {};
  errno_t error = localtime_s(&lt, &t);
  if (error == 0) {
    return static_cast<std::ostringstream&&>(
     std::ostringstream()
     << std::put_time(&lt, "%Y-%m-%d %H:%M:%S." )
     << std::setfill('0') << std::setw(3) // ミリ秒を0埋め3桁で表示
     << std::chrono::duration_cast<std::chrono::milliseconds>(now.time_since_epoch()).count() % 1000
    ).str();
  } else {
    return "?";
  }
}

void FlutterWindow::outputLog(std::string message) {
  std::string log_time = getLogTime();
  std::string log = "[" + log_time + "] " + message;
  //std::cout << log << std::endl;
  funcOutputLog(&log);
}
//--------------------------------------------------------------------------------


//--------------------------------------------------------------------------------
// マウスイベント取得関連 24/07/10 yoki

// m_pThisを使う事でメインのクラスを制御
// ※クラスのprotectedやprivateの意味がほぼ無くなってしまうけど、
// 　利便性を考えるとこの方法が簡単
FlutterWindow *FlutterWindow::m_pThis = NULL;

// マウスイベント取得関連の初期化処理
void FlutterWindow::initMouseEvent() {
  m_pThis = this;
  mouseHook = NULL;

  // マウスクリック確認フラグ
  click_check_flg[MOUSE_TYPE::LEFT]
   = click_check_flg[MOUSE_TYPE::RIGHT]
   = click_check_flg[MOUSE_TYPE::MIDDLE]
   = click_check_flg[MOUSE_TYPE::X]
   = false;

  // マウスボタン押下フラグ
  pressed_flg[MOUSE_TYPE::LEFT]
   = pressed_flg[MOUSE_TYPE::RIGHT]
   = pressed_flg[MOUSE_TYPE::MIDDLE]
   = pressed_flg[MOUSE_TYPE::X]
   = false;

  // 前回のイベント発生時間
  old_time_point[MOUSE_TYPE::LEFT][MOUSE_BUTTON::DOWN]
   = old_time_point[MOUSE_TYPE::LEFT][MOUSE_BUTTON::UP]
   = old_time_point[MOUSE_TYPE::RIGHT][MOUSE_BUTTON::DOWN]
   = old_time_point[MOUSE_TYPE::RIGHT][MOUSE_BUTTON::UP]
   = old_time_point[MOUSE_TYPE::MIDDLE][MOUSE_BUTTON::DOWN]
   = old_time_point[MOUSE_TYPE::MIDDLE][MOUSE_BUTTON::UP]
   = old_time_point[MOUSE_TYPE::X][MOUSE_BUTTON::DOWN]
   = old_time_point[MOUSE_TYPE::X][MOUSE_BUTTON::UP]
   = std::chrono::steady_clock::now();

  // イベント破棄判定時間(ms)
  disabled_time[MOUSE_TYPE::LEFT][MOUSE_BUTTON::DOWN]
   = disabled_time[MOUSE_TYPE::RIGHT][MOUSE_BUTTON::DOWN]
   = disabled_time[MOUSE_TYPE::MIDDLE][MOUSE_BUTTON::DOWN]
   = disabled_time[MOUSE_TYPE::X][MOUSE_BUTTON::DOWN]
   = 40;

  disabled_time[MOUSE_TYPE::LEFT][MOUSE_BUTTON::UP]
   = disabled_time[MOUSE_TYPE::RIGHT][MOUSE_BUTTON::UP]
   = disabled_time[MOUSE_TYPE::MIDDLE][MOUSE_BUTTON::UP]
   = disabled_time[MOUSE_TYPE::X][MOUSE_BUTTON::UP]
   = 40;

  // イベント破棄済みフラグ
  disabled_flg[MOUSE_TYPE::LEFT][MOUSE_BUTTON::DOWN]
   = disabled_flg[MOUSE_TYPE::LEFT][MOUSE_BUTTON::UP]
   = disabled_flg[MOUSE_TYPE::RIGHT][MOUSE_BUTTON::DOWN]
   = disabled_flg[MOUSE_TYPE::RIGHT][MOUSE_BUTTON::UP]
   = disabled_flg[MOUSE_TYPE::MIDDLE][MOUSE_BUTTON::DOWN]
   = disabled_flg[MOUSE_TYPE::MIDDLE][MOUSE_BUTTON::UP]
   = disabled_flg[MOUSE_TYPE::X][MOUSE_BUTTON::DOWN]
   = disabled_flg[MOUSE_TYPE::X][MOUSE_BUTTON::UP]
   = false;
}

// マウスボタンイベント共通処理
// マウスボタンを押す処理と離す処理とで内容が一部異なるのでちゃんと分けておく
bool FlutterWindow::mouseButtonCheck(MOUSE_TYPE type, MOUSE_BUTTON button) {

  // ログ出力用マウスボタン種類文字の設定
  std::string type_str = "";
  switch (type) {
    case MOUSE_TYPE::LEFT:
      type_str = "L";
      break;
    case MOUSE_TYPE::RIGHT:
      type_str = "R";
      break;
    case MOUSE_TYPE::MIDDLE:
      type_str = "M";
      break;
    case MOUSE_TYPE::X:
      type_str = "X";
      break;
  }

  // 現在時刻と前回イベントからの経過時間取得
  std::chrono::steady_clock::time_point now_time_point
   = std::chrono::steady_clock::now();
  std::chrono::duration<double, std::milli> d_elapsed_time
   = now_time_point - old_time_point[type][MOUSE_BUTTON::DOWN];
  std::chrono::duration<double, std::milli> u_elapsed_time
   = now_time_point - old_time_point[type][MOUSE_BUTTON::UP];


  // マウスボタンを押した時用の判定
  if (button == MOUSE_BUTTON::DOWN) {
    // 条件に該当したらtrueを返してイベントを破棄する
    if (pressed_flg[type]
     || (!disabled_flg[type][MOUSE_BUTTON::DOWN]
      && disabled_flg[type][MOUSE_BUTTON::UP])
     || (d_elapsed_time.count() < disabled_time[type][MOUSE_BUTTON::DOWN])
     || (u_elapsed_time.count() < disabled_time[type][MOUSE_BUTTON::UP])
    ) {
      // ログ出力
      outputLog("WM_" + type_str + "BUTTONDOWN_DISABLE:"
        + std::to_string(d_elapsed_time.count())
        + " "
        + std::to_string(u_elapsed_time.count())
        );

      // 次回の判定の為にフラグを設定
      pressed_flg[type] = true;
      disabled_flg[type][MOUSE_BUTTON::DOWN] = true;

      return true;
    }

    // ログ出力
    outputLog("----------------------------------------");
    outputLog("WM_" + type_str + "BUTTONDOWN");

    // 次回の判定の為にフラグを設定
    pressed_flg[type] = true;
    old_time_point[type][MOUSE_BUTTON::DOWN] = now_time_point;
    disabled_flg[type][MOUSE_BUTTON::DOWN] = false;

    return false;

  // マウスボタン離した時用の判定
  } else if (button == MOUSE_BUTTON::UP) {
    // 条件に該当したらtrueを返してイベントを破棄する
    if (!pressed_flg[type]
     || (disabled_flg[type][MOUSE_BUTTON::DOWN]
      && !disabled_flg[type][MOUSE_BUTTON::UP])
     || (d_elapsed_time.count() < disabled_time[type][MOUSE_BUTTON::UP])
    ) {
      // ログ出力
      outputLog("WM_" + type_str + "BUTTONUP_DISABLE:" + std::to_string(d_elapsed_time.count()));

      // ドラッグ状態固定化防止処理
      // フック処理中の同期処理はPC再起動コースなので非同期で行う
      auto funcMouse = [](FlutterWindow *pThis, MOUSE_TYPE type, double sleep_time) {
        // 一旦チャタリング判定範囲時間分待機させる
        if (sleep_time < 1) {
          sleep_time = 0;
        }
        sleep_time ++;  // 最低でも1ms待つ
        std::this_thread::sleep_for(std::chrono::milliseconds((long)sleep_time));

        // チャタリング誤判定の確認
        if (!pThis->disabled_flg[type][MOUSE_BUTTON::DOWN]) {
          // 疑似的にクリックイベントを発生させて、チャタリング誤判定によるドラッグ状態を解除
          INPUT simInput[2] = {};
          ZeroMemory(simInput, sizeof(simInput));
          simInput[0].type = INPUT_MOUSE;
          simInput[1].type = INPUT_MOUSE;

          // ログ出力メッセージ準備
          HWND  hwnd = pThis->GetHandle();
          std::string log;

          switch (type) {
            case MOUSE_TYPE::LEFT:
              log = "SendInput:LEFT";
              simInput[0].mi.dwFlags = MOUSEEVENTF_LEFTDOWN;
              simInput[1].mi.dwFlags = MOUSEEVENTF_LEFTUP;
              break;
            case MOUSE_TYPE::RIGHT:
              log = "SendInput:RIGHT";
              simInput[0].mi.dwFlags = MOUSEEVENTF_RIGHTDOWN;
              simInput[1].mi.dwFlags = MOUSEEVENTF_RIGHTUP;
              break;
            case MOUSE_TYPE::MIDDLE:
              log = "SendInput:MIDDLE";
              simInput[0].mi.dwFlags = MOUSEEVENTF_MIDDLEDOWN;
              simInput[1].mi.dwFlags = MOUSEEVENTF_MIDDLEUP;
              break;
            case MOUSE_TYPE::X:
              log = "SendInput:X";
              simInput[0].mi.dwFlags = MOUSEEVENTF_XDOWN;
              simInput[1].mi.dwFlags = MOUSEEVENTF_XUP;
              break;
          }

           // スレッドでマウスイベント生成した事をログ出力
          SendMessage(hwnd, WM_APP_OUTPUTLOG, NULL, (LPARAM)&log);

          // マウスイベント生成
          SendInput(ARRAYSIZE(simInput), simInput, sizeof(INPUT));
        }
      };

      // スレッドの準備
      std::thread thMouse(funcMouse,
        this, type, disabled_time[type][MOUSE_BUTTON::DOWN] - d_elapsed_time.count());

      // スレッド生成した事をログ出力
      outputLog((std::stringstream() << type_str + " thread_id:" << thMouse.get_id()).str());

      // 非同期でスレッド開始
      thMouse.detach();

      // 次回の判定の為にフラグを設定
      pressed_flg[type] = false;
      disabled_flg[type][MOUSE_BUTTON::UP] = true;

      return true;
    }

    // ログ出力
    outputLog("WM_" + type_str + "BUTTONUP");

    // 次回の判定の為にフラグを設定
    pressed_flg[type] = false;
    old_time_point[type][MOUSE_BUTTON::UP] = now_time_point;
    disabled_flg[type][MOUSE_BUTTON::UP] = false;

    return false;

  // 未定義
  } else {
  }

  return false;
}

// マウスイベント取得用
LRESULT CALLBACK FlutterWindow::llMouseProc(int nCode, WPARAM wp, LPARAM lp) {
  assert(m_pThis != NULL);  // ここでNULLにならない筈だけど一応確認、もしNULLだったらアプリを異常終了させる
  return m_pThis->mouseEvent(nCode, wp, lp);
}

LRESULT FlutterWindow::mouseEvent(int nCode, WPARAM wp, LPARAM lp) {
  if (nCode == HC_ACTION) {
    switch (wp) {
      //----------------------------------------
      // マウス移動
      case WM_MOUSEMOVE:
        //outputLog("WM_MOUSEMOVE");
        break;
      //----------------------------------------

      //----------------------------------------
      // マウス左クリック
      case WM_LBUTTONDOWN:
/*
      { // switch文内で変数生成している為、他のcaseに影響しないように囲む
        std::chrono::steady_clock::time_point now_time_point
         = std::chrono::steady_clock::now();
        std::chrono::duration<double, std::milli> d_elapsed_time
         = now_time_point - old_time_point[MOUSE_TYPE::LEFT][MOUSE_BUTTON::DOWN];
        std::chrono::duration<double, std::milli> u_elapsed_time
         = now_time_point - old_time_point[MOUSE_TYPE::LEFT][MOUSE_BUTTON::UP];

        if (pressed_flg[MOUSE_TYPE::LEFT]
         || (!disabled_flg[MOUSE_TYPE::LEFT][MOUSE_BUTTON::DOWN]
          && disabled_flg[MOUSE_TYPE::LEFT][MOUSE_BUTTON::UP])
         || (d_elapsed_time.count() < disabled_time[MOUSE_TYPE::LEFT][MOUSE_BUTTON::DOWN])
         || (u_elapsed_time.count() < disabled_time[MOUSE_TYPE::LEFT][MOUSE_BUTTON::UP])
         ) {
          CallNextHookEx(NULL, nCode, wp, lp); // 別アプリのフック処理用?
          outputLog("WM_LBUTTONDOWN_DISABLE:"
           + std::to_string(d_elapsed_time.count())
           + " "
           + std::to_string(u_elapsed_time.count())
           );
          pressed_flg[MOUSE_TYPE::LEFT] = true;
          disabled_flg[MOUSE_TYPE::LEFT][MOUSE_BUTTON::DOWN] = true;
          return TRUE; // 0以外を返すとこのマウスイベントを無視する
        }

        outputLog("----------------------------------------");
        outputLog("WM_LBUTTONDOWN");
        pressed_flg[MOUSE_TYPE::LEFT] = true;
        old_time_point[MOUSE_TYPE::LEFT][MOUSE_BUTTON::DOWN] = now_time_point;
        disabled_flg[MOUSE_TYPE::LEFT][MOUSE_BUTTON::DOWN] = false;
        break;
      }
*/
        if (click_check_flg[MOUSE_TYPE::LEFT]) {
          // 全てのイベントに上記のような処理を付けるのは管理が面倒なので、共通の関数で処理
          if (mouseButtonCheck(MOUSE_TYPE::LEFT, MOUSE_BUTTON::DOWN)) {
            CallNextHookEx(NULL, nCode, wp, lp); // 別アプリのフック処理用?
            return TRUE; // 0以外を返すとこのマウスイベントを無視する
          }
        }
        break;

      // マウス左ボタン離し
      case WM_LBUTTONUP:
/*
      { // switch文内で変数生成している為、他のcaseに影響しないように囲む
        std::chrono::steady_clock::time_point now_time_point
         = std::chrono::steady_clock::now();
        std::chrono::duration<double, std::milli> d_elapsed_time
         = now_time_point - old_time_point[MOUSE_TYPE::LEFT][MOUSE_BUTTON::DOWN];
        //std::chrono::duration<double, std::milli> u_elapsed_time
        // = now_time_point - old_time_point[MOUSE_TYPE::LEFT][MOUSE_BUTTON::UP];

        if (!pressed_flg[MOUSE_TYPE::LEFT]
         || (disabled_flg[MOUSE_TYPE::LEFT][MOUSE_BUTTON::DOWN]
          && !disabled_flg[MOUSE_TYPE::LEFT][MOUSE_BUTTON::UP])
         || (d_elapsed_time.count() < disabled_time[MOUSE_TYPE::LEFT][MOUSE_BUTTON::UP])
        ) {
 
          outputLog("WM_LBUTTONUP_DISABLE:" + std::to_string(d_elapsed_time.count()));

          CallNextHookEx(NULL, nCode, wp, lp); // 別アプリのフック処理用?

          // ドラッグ状態固定化防止処理
          // フック処理中の同期処理はPC再起動コースなので非同期で行う
          auto funcMouse = [](double sleep_time){
            // 一旦チャタリング判定範囲時間分待機させる
            if (sleep_time < 1) {
              sleep_time = 0;
            }
            sleep_time ++;  // 最低でも1ms待つ
            std::this_thread::sleep_for(std::chrono::milliseconds((long)sleep_time));

            // チャタリング誤判定の確認
            if (!m_pThis->disabled_flg[MOUSE_TYPE::LEFT][MOUSE_BUTTON::DOWN]) {
              m_pThis->outputLog("SendInput");
              // 疑似的にクリックイベントを発生させて、チャタリング誤判定によるドラッグ状態を解除
              INPUT simInput[2] = {};
              ZeroMemory(simInput, sizeof(simInput));
              simInput[0].type = INPUT_MOUSE;
              simInput[0].mi.dwFlags = MOUSEEVENTF_LEFTDOWN;
              simInput[1].type = INPUT_MOUSE;
              simInput[1].mi.dwFlags = MOUSEEVENTF_LEFTUP;
              SendInput(ARRAYSIZE(simInput), simInput, sizeof(INPUT));
            }
          };
          std::thread thMouse(funcMouse, disabled_time[MOUSE_TYPE::LEFT][MOUSE_BUTTON::DOWN] - d_elapsed_time.count());
          outputLog((std::stringstream() << "thread_id:" << thMouse.get_id()).str());
          thMouse.detach();

          pressed_flg[MOUSE_TYPE::LEFT] = false;
          disabled_flg[MOUSE_TYPE::LEFT][MOUSE_BUTTON::UP] = true;
          return TRUE; // 0以外を返すとこのマウスイベントを無視する
        }

        outputLog("WM_LBUTTONUP");
        pressed_flg[MOUSE_TYPE::LEFT] = false;
        old_time_point[MOUSE_TYPE::LEFT][MOUSE_BUTTON::UP] = now_time_point;
        disabled_flg[MOUSE_TYPE::LEFT][MOUSE_BUTTON::UP] = false;
        break;
      }
*/
        if (click_check_flg[MOUSE_TYPE::LEFT]) {
          // 全てのイベントに上記のような処理を付けるのは管理が面倒なので、共通の関数で処理
          if (mouseButtonCheck(MOUSE_TYPE::LEFT, MOUSE_BUTTON::UP)) {
            CallNextHookEx(NULL, nCode, wp, lp); // 別アプリのフック処理用?
            return TRUE; // 0以外を返すとこのマウスイベントを無視する
          }
        }
        break;

      // マウス左ダブルクリック(WNDCLASS の style で CS_DBLCLKS を設定しないとイベントが来ない)
      case WM_LBUTTONDBLCLK:
        //outputLog("WM_LBUTTONDBLCLK");
        break;
      //----------------------------------------

      //----------------------------------------
      // マウス右クリック
      case WM_RBUTTONDOWN:
        if (click_check_flg[MOUSE_TYPE::RIGHT]) {
          if (mouseButtonCheck(MOUSE_TYPE::RIGHT, MOUSE_BUTTON::DOWN)) {
            CallNextHookEx(NULL, nCode, wp, lp); // 別アプリのフック処理用?
            return TRUE; // 0以外を返すとこのマウスイベントを無視する
          }
        }
        break;

      // マウス右ボタン離し
      case WM_RBUTTONUP:
        if (click_check_flg[MOUSE_TYPE::RIGHT]) {
          if (mouseButtonCheck(MOUSE_TYPE::RIGHT, MOUSE_BUTTON::UP)) {
            CallNextHookEx(NULL, nCode, wp, lp); // 別アプリのフック処理用?
            return TRUE; // 0以外を返すとこのマウスイベントを無視する
          }
        }
        break;

      // マウス右ダブルクリック(WNDCLASS の style で CS_DBLCLKS を設定しないとイベントが来ない)
      case WM_RBUTTONDBLCLK:
        //outputLog("WM_RBUTTONDBLCLK");
        break;
      //----------------------------------------

      //----------------------------------------
      // マウス中央クリック
      case WM_MBUTTONDOWN:
        if (click_check_flg[MOUSE_TYPE::MIDDLE]) {
          if (mouseButtonCheck(MOUSE_TYPE::MIDDLE, MOUSE_BUTTON::DOWN)) {
            CallNextHookEx(NULL, nCode, wp, lp); // 別アプリのフック処理用?
            return TRUE; // 0以外を返すとこのマウスイベントを無視する
          }
        }
        break;

      // マウス中央ボタン離し
      case WM_MBUTTONUP:
        if (click_check_flg[MOUSE_TYPE::MIDDLE]) {
          if (mouseButtonCheck(MOUSE_TYPE::MIDDLE, MOUSE_BUTTON::UP)) {
            CallNextHookEx(NULL, nCode, wp, lp); // 別アプリのフック処理用?
            return TRUE; // 0以外を返すとこのマウスイベントを無視する
          }
        }
        break;

      // マウス中央ダブルクリック(WNDCLASS の style で CS_DBLCLKS を設定しないとイベントが来ない)
      case WM_MBUTTONDBLCLK:
        //outputLog("WM_MBUTTONDBLCLK");
        break;
      //----------------------------------------

      //----------------------------------------
      // マウスホイール回転
      case WM_MOUSEWHEEL:
        //outputLog("WM_MOUSEWHEEL");
        break;
      //----------------------------------------

      //----------------------------------------
      // マウスXボタンクリック
      case WM_XBUTTONDOWN:
        if (click_check_flg[MOUSE_TYPE::X]) {
          if (mouseButtonCheck(MOUSE_TYPE::X, MOUSE_BUTTON::DOWN)) {
            CallNextHookEx(NULL, nCode, wp, lp); // 別アプリのフック処理用?
            return TRUE; // 0以外を返すとこのマウスイベントを無視する
          }
        }
        break;

      // マウスXボタン離し
      case WM_XBUTTONUP:
        if (click_check_flg[MOUSE_TYPE::X]) {
          if (mouseButtonCheck(MOUSE_TYPE::X, MOUSE_BUTTON::UP)) {
            CallNextHookEx(NULL, nCode, wp, lp); // 別アプリのフック処理用?
            return TRUE; // 0以外を返すとこのマウスイベントを無視する
          }
        }
        break;

      // マウスXボタンダブルクリック
      case WM_XBUTTONDBLCLK:
        //outputLog("WM_XBUTTONDBLCLK");
        break;
      //----------------------------------------

      //----------------------------------------
      // その他
      default:
        break;
      //----------------------------------------
    }
  }
  return CallNextHookEx(mouseHook, nCode, wp, lp);
};

// マウスイベント取得開始
void FlutterWindow::mouseHookEnable() {
  if (!mouseHook) {
    HMODULE hInstance = GetModuleHandle(nullptr);
    mouseHook = SetWindowsHookEx(WH_MOUSE_LL, llMouseProc, hInstance, 0);
    //mouseHook = SetWindowsHookEx(WH_MOUSE, llMouseProc, hInstance, 0); // マウス以外のイベントも取得(管理者権限必須?)

    if (mouseHook) {
      outputLog("Hook Start");

      // マウス入力状態監視スレッド
      // ...のつもりだったが、どうやら WM_～BUTTONUP が処理されないと、
      // 常にマウスボタンが押された状態になっていたので、
      // GetKeyState 及び GetAsyncKeyState は WM_～ より下位の処理だと理解できた
      /*
      auto funcMouseState = [](){
        do {
          if (GetAsyncKeyState(VK_LBUTTON) & 0x8000) {
            //m_pThis->outputLog("-----VK_LBUTTON_DOWN");
          } else {
            //m_pThis->outputLog("-----VK_LBUTTON_UP");
          }
          if (GetAsyncKeyState(VK_RBUTTON) & 0x8000) {
            //m_pThis->outputLog("-----VK_RBUTTON_DOWN");
          } else {
            //m_pThis->outputLog("-----VK_RBUTTON_UP");
          }

          std::this_thread::sleep_for(std::chrono::milliseconds(1000));
        } while(m_pThis->mouseHook);  // フックが停止したら監視終了
      };
      std::thread thMouseState(funcMouseState);
      thMouseState.detach();
      */
    } else {
      outputLog("Hook Error");
    }
  }
}

// マウスイベント取得停止
void FlutterWindow::mouseHookDisable() {
  if (mouseHook) {
    UnhookWindowsHookEx(mouseHook);
    mouseHook = NULL;
    outputLog("Hook End");
  }
}

// マウス左クリック確認フラグの設定
void FlutterWindow::setLeftClickCheckFlg(bool flg) {
  click_check_flg[MOUSE_TYPE::LEFT] = flg;
}

// マウス右クリック確認フラグの設定
void FlutterWindow::setRightClickCheckFlg(bool flg) {
  click_check_flg[MOUSE_TYPE::RIGHT] = flg;
}

// マウス左クリック破棄時間の設定
void FlutterWindow::setLeftDownDisabledTime(int64_t time) {
  disabled_time[MOUSE_TYPE::LEFT][MOUSE_BUTTON::DOWN] = static_cast<double>(time);
}

// マウス左ボタン離し破棄時間の設定
void FlutterWindow::setLeftUpDisabledTime(int64_t time) {
  disabled_time[MOUSE_TYPE::LEFT][MOUSE_BUTTON::UP] = static_cast<double>(time);
}

// マウス右クリック破棄時間の設定
void FlutterWindow::setRightDownDisabledTime(int64_t time) {
  disabled_time[MOUSE_TYPE::RIGHT][MOUSE_BUTTON::DOWN] = static_cast<double>(time);
}

// マウス右ボタン離し破棄時間の設定
void FlutterWindow::setRightUpDisabledTime(int64_t time) {
  disabled_time[MOUSE_TYPE::RIGHT][MOUSE_BUTTON::UP] = static_cast<double>(time);
}
//--------------------------------------------------------------------------------


//--------------------------------------------------------------------------------
// (MethodChannel) 24/07/02 yoki
void FlutterWindow::setMethodChannel(flutter::FlutterEngine *engine) {
  const std::string test_channel("yoki/chattering_controller"); // チャンネル名は共通にする事
  const flutter::StandardMethodCodec& codec = flutter::StandardMethodCodec::GetInstance();
  method_channel_ = std::make_unique<flutter::MethodChannel<>>(engine->messenger(), test_channel, &codec);

  // Flutterからの呼び出し
  method_channel_->SetMethodCallHandler([&](const auto& call, auto result) {
    std::string name = call.method_name();
    // メソッドが見つかったら処理する
    if (name.compare("test") == 0) {
      flutter::EncodableMap res = {
        {"value", "1"},
      };
      result->Success(res);

      //result->Success();  // メソッド処理の成否だけを返す
/*
    } else if (name.compare("") == 0) {
      // 引数の確認(例)
      if ( call.arguments() ) {
        const auto *arguments = std::get_if<flutter::EncodableMap>(call.arguments());
        if ( arguments ) {
          auto text_it = arguments->find(flutter::EncodableValue("text"));
          auto num_it = arguments->find(flutter::EncodableValue("num"));
          if ( (text_it != arguments->end()) && (num_it != arguments->end()) ) {
            std::string text = std::get<std::string>(text_it->second);
            int num = std::get<int>(num_it->second);
            message = MakeMessage(text,num);
          }
        }
      }

      // 戻り値の設定
      flutter::EncodableMap res = {
        {"device", "Windows"},
        {"level", "1" },
        {"message", "message" },
      };

      result->Success(res);
*/
    } else {
      // 指定したメソッドが見つからなかった場合
      result->Error("UNAVAILABLE","ERROR");
    }
  });

  // Flutter処理の呼び出し例
/*
  auto result_handler = std::make_unique<flutter::MethodResultFunctions<>>(
    // Flutterからの戻り値の確認
    // 数値
    [](const flutter::EncodableValue* success_value) {
      outputLog("on_success");
      outputLog(std::get<std::string>(*success_value));
    },
    // エラーメッセージ
    [](std::string error_code, std::string error_message, const flutter::EncodableValue* error_details) {
      outputLog("on_error");
    },
    // 戻り値無し
    []() {
      outputLog("on_not_implemented");
    }
  );
  method_channel_->InvokeMethod("test", nullptr, std::move(result_handler));
*/
}
//--------------------------------------------------------------------------------


//--------------------------------------------------------------------------------
// (pigeon) 24/07/03 yoki
// メインのクラスにデータを渡すイメージ
std::optional<FlutterError> PigeonHostApi::StartMouseEventListening() {
  assert(FlutterWindow::m_pThis != NULL); // ここでNULLにならない筈だけど一応確認、もしNULLだったらアプリを異常終了させる
  FlutterWindow::m_pThis->mouseHookEnable();  // 対応した処理を呼ぶ
  return std::nullopt;  // エラー無しの場合の戻り値
}

std::optional<FlutterError> PigeonHostApi::CancelMouseEventListening() {
  assert(FlutterWindow::m_pThis != NULL);
  FlutterWindow::m_pThis->mouseHookDisable();
  return std::nullopt;
}

std::optional<FlutterError> PigeonHostApi::SetLeftClickCheckFlg(bool flg) {
  assert(FlutterWindow::m_pThis != NULL);
  FlutterWindow::m_pThis->setLeftClickCheckFlg(flg);
  return std::nullopt;
}

std::optional<FlutterError> PigeonHostApi::SetRightClickCheckFlg(bool flg) {
  assert(FlutterWindow::m_pThis != NULL);
  FlutterWindow::m_pThis->setRightClickCheckFlg(flg);
  return std::nullopt;
}

std::optional<FlutterError> PigeonHostApi::SetLeftDownDisabledTime(int64_t time) {
  assert(FlutterWindow::m_pThis != NULL);
  FlutterWindow::m_pThis->setLeftDownDisabledTime(time);
  return std::nullopt;
}

std::optional<FlutterError> PigeonHostApi::SetLeftUpDisabledTime(int64_t time) {
  assert(FlutterWindow::m_pThis != NULL);
  FlutterWindow::m_pThis->setLeftUpDisabledTime(time);
  return std::nullopt;
}

std::optional<FlutterError> PigeonHostApi::SetRightDownDisabledTime(int64_t time) {
  assert(FlutterWindow::m_pThis != NULL);
  FlutterWindow::m_pThis->setRightDownDisabledTime(time);
  return std::nullopt;
}

std::optional<FlutterError> PigeonHostApi::SetRightUpDisabledTime(int64_t time) {
  assert(FlutterWindow::m_pThis != NULL);
  FlutterWindow::m_pThis->setRightUpDisabledTime(time);
  return std::nullopt;
}
//--------------------------------------------------------------------------------
