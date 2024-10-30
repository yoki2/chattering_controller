//--------------------------------------------------------------------------------
// main関連の定数
// new 24/06/17 yoki
//--------------------------------------------------------------------------------
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

// マウスドラッグによるスクロール有効化対応
class CustomScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch, // 通常のタッチ入力デバイス
        PointerDeviceKind.mouse, // マウス操作対応
      };
}

// メイン用の定数
class MainConstants {
  // アプリのタイトル
  static const String title = 'Chattering Controller';
  static const TextStyle titleStyle = TextStyle(
    fontSize: 20.0,
    fontWeight: FontWeight.bold,
  );

  // アプリのアイコン画像
  static const String iconPath = 'assets/app_icon.ico';
  static const String iconPathPng = 'assets/app_icon.png';

  // システムトレイのメニュー
  static const String systrayShow = '表示';
  static const String systrayHide = '非表示';
  static const String systrayStartup = 'スタートアップ起動設定';
  static const String systrayDestroy = '終了';

  // schtasks用
  static const String schtasksName = 'StartUp_Chattering_Controller';
  static const String releaseAssetsPath = 'data/flutter_assets/assets/';
  static const String debugAssetsPath = 'assets/';
  static const String schtasksXMLPath = 'StartUp_Chattering_Controller.xml';

  // アプリ終了確認
  static const Text closeTitle = Text(
    '終了しますか?',
    style: TextStyle(
      fontSize: 20.0,
      fontWeight: FontWeight.bold,
    ),
  );

  // アプリの設定データ
  static const int minDisabledTime = 1;
  static const int maxDisabledTime = 2000;
  static const int initLeftDownDisabledTime = 40;
  static const int initLeftUpDisabledTime = 40;
  static const int initRightDownDisabledTime = 40;
  static const int initRightUpDisabledTime = 40;

  // 了承ボタン設定
  static ElevatedButton yesButton(void Function()? onPressed) {
    return ElevatedButton(
      onPressed: onPressed,
      style:
          ElevatedButton.styleFrom(fixedSize: const Size(100, double.infinity)),
      child: const Text(
        'はい',
        style: TextStyle(fontSize: 16.0),
      ),
    );
  }

  // 拒否ボタン設定
  static ElevatedButton noButton(void Function()? onPressed) {
    return ElevatedButton(
      onPressed: onPressed,
      style:
          ElevatedButton.styleFrom(fixedSize: const Size(100, double.infinity)),
      child: const Text(
        'いいえ',
        style: TextStyle(fontSize: 16.0),
      ),
    );
  }

  //----------------------------------------
  // 破棄判定時間設定領域の色
  static const Color disabledTimeTileColor = Colors.lightBlue;

  // 破棄判定時間設定領域の余白
  static const EdgeInsets disabledTimeContainerPadding =
      EdgeInsets.symmetric(vertical: 5.0);

  // 破棄判定時間設定領域の枠線の色
  static const Color disabledTimeContainerBorderColor = Colors.blue;

  // 破棄判定時間説明テキスト横サイズ
  static const double disabledTimeTitleWidth = 170.0;

  // 破棄判定時間入力フィールドテキストサイズ
  static const TextStyle disabledTimeFieldFontStyle = TextStyle(
    fontSize: 12.0,
  );

  // 破棄判定時間入力フィールド横サイズ
  static const double disabledTimeFieldWidth = 50.0;

  // 左クリック関連
  static const Text leftClickCheckTitle = Text('左クリック制御',
      style: TextStyle(
        fontSize: 16.0,
        fontWeight: FontWeight.bold,
      ));

  // 右クリック関連
  static const Text rightClickCheckTitle = Text('右クリック制御',
      style: TextStyle(
        fontSize: 16.0,
        fontWeight: FontWeight.bold,
      ));

  // Downイベント破棄判定時間のタイトル
  static const Text downDisabledTimeTitle = Text('押下(Down)イベント\n破棄判定時間',
      style: TextStyle(
        fontSize: 16.0,
        fontWeight: FontWeight.bold,
      ));

  // Upイベント破棄判定時間のタイトル
  static const Text upDisabledTimeTitle = Text('離上(Up)イベント\n破棄判定時間',
      style: TextStyle(
        fontSize: 16.0,
        fontWeight: FontWeight.bold,
      ));

  // 破棄判定時間単位
  static const Text disabledTimeUnit = Text(
    'ms',
    style: TextStyle(fontSize: 16.0, fontWeight: FontWeight.bold),
  );
  //----------------------------------------

  //----------------------------------------
  // 設定適用ボタン
  static Container settingsAppliedButton(void Function()? onPressed) {
    // ボタンの状態で透明度を変化させるのでここでベースの色を定義しておく
    MaterialColor buttonColor = Colors.deepPurple;
    return Container(
      padding: const EdgeInsets.all(5.0),
      child: ElevatedButton(
        onPressed: onPressed,
        // styleFromだとボタンの色がbackgroundColorで固定されて、
        // 押した時のスプラッシュ表現等が消えてしまった。
        // この原因は解明できなかったが、
        // 下記のようにボタンの状態毎に色設定をする事で
        // 想定通りに色が変化するようになった。
        // これが正しい方法なのかは調べても見当たらなかったので不明 24/09/05
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith<Color>(
            (Set<WidgetState> states) {
              // Tabキーによるフォーカス時、又はマウスカーソルが上に来た時は色を薄くする
              if (states.contains(WidgetState.focused) ||
                  states.contains(WidgetState.hovered)) {
                return buttonColor.withOpacity(0.8);
              }
              return buttonColor;
            },
          ),
          overlayColor: WidgetStateProperty.resolveWith<Color>(
            (Set<WidgetState> states) {
              // ボタンが押されたらベースの色でスプラッシュ表現
              if (states.contains(WidgetState.pressed)) {
                return buttonColor;
              }
              // 通常時は透明状態
              return Colors.transparent;
            },
          ),
        ),
        child: const Text(
          '設定適用',
          style: TextStyle(fontSize: 16.0, color: Colors.white),
        ),
      ),
    );
  }
  //----------------------------------------

  //----------------------------------------
  // イベントログタイトル
  static const eventLogTitle = Text(
    'クリックイベントログ',
    style: TextStyle(fontSize: 16.0, fontWeight: FontWeight.bold),
  );

  // イベントログタイトルの色
  static const Color eventLogTitleTileColor = Colors.lightBlue;

  // イベントログの枠外余白
  static const EdgeInsets eventLogContainerPadding =
      EdgeInsets.fromLTRB(5.0, 10.0, 5.0, 0.0);

  // イベントログ本体
  static Container eventLogView(
      ScrollController controller, TextSpan Function()? textFunc) {
    return Container(
      width: 400,
      height: 200,
      //margin: const EdgeInsets.all(5.0),
      color: const Color.fromARGB(255, 226, 226, 226),
      child: SingleChildScrollView(
        controller: controller,
        child: SelectableText.rich(textFunc!()),
      ),
    );
  }

  // イベントログ文字サイズ
  static const double eventLogFontSize = 12.0;
  static const TextStyle eventLogFontStyle =
      TextStyle(fontSize: eventLogFontSize);

  // イベントログ表示件数
  static const int eventLogLength = 1000;
  //----------------------------------------
}

// サイドナビゲーションメニュー(左)用の定数
class MainDrawerConstants {
  // 表題
  static DrawerHeader title = const DrawerHeader(
    decoration: BoxDecoration(color: Colors.blue),
    child: Text(
      'Help',
      style: TextStyle(fontSize: 20.0, fontWeight: FontWeight.bold),
    ),
  );

  // メニュー
  static const Text startup = Text(
    'スタートアップ起動設定',
    style: TextStyle(fontSize: 16.0, fontWeight: FontWeight.bold),
  );
  static const Text info = Text(
    'このアプリケーションについて',
    style: TextStyle(fontSize: 16.0, fontWeight: FontWeight.bold),
  );
  static const Text about = Text(
    '権利表記',
    style: TextStyle(fontSize: 16.0, fontWeight: FontWeight.bold),
  );
}
