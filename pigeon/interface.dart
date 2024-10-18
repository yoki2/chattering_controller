//--------------------------------------------------------------------------------
// pigeon用
// new 24/07/03 yoki
// dart run pigeon --input pigeon/interface.dart
//--------------------------------------------------------------------------------
import 'package:pigeon/pigeon.dart';

// Pigeonの設定項目
@ConfigurePigeon(PigeonOptions(
  dartOut: "lib/messages.g.dart", // Dartファイルの生成先

  // Windows側のファイル生成先
  cppOptions: CppOptions(namespace: 'pigeon_messages'),
  cppHeaderOut: 'windows/runner/messages.g.h',
  cppSourceOut: 'windows/runner/messages.g.cpp',
))

// Flutter -> Native
@HostApi()
abstract class MessageHostApi {
  // 共通
  void startMouseEventListening(); // マウスイベント取得開始
  void cancelMouseEventListening(); // マウスイベント取得停止
  void setLeftClickCheckFlg(bool flg); // マウス左クリック確認フラグ
  void setRightClickCheckFlg(bool flg); // マウス右クリック確認フラグ
  void setLeftDownDisabledTime(int time); // マウス左クリック破棄時間(ms)
  void setLeftUpDisabledTime(int time); // マウス左ボタン離し破棄時間(ms)
  void setRightDownDisabledTime(int time); // マウス右クリック破棄時間(ms)
  void setRightUpDisabledTime(int time); // マウス右ボタン離し破棄時間(ms)
}

// Native -> Flutter
@FlutterApi()
abstract class MessageFlutterApi {
  void outputLog(String? message);
}
