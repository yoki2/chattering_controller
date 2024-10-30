//--------------------------------------------------------------------------------
// main
// new 24/05/03 yoki
//--------------------------------------------------------------------------------
import 'dart:collection';
import 'dart:io' show Directory, File, Platform, Process, ProcessResult;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// 外部パッケージ
import 'package:package_info_plus/package_info_plus.dart';
import 'package:window_manager/window_manager.dart';
import 'package:system_tray/system_tray.dart';
import 'package:shared_preferences/shared_preferences.dart';
//import 'package:win32_registry/win32_registry.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml.dart';

// このアプリで使用する設定や別画面等
import 'main_constants.dart'; // Widgetの表示内容やサイズ等の定数
import 'messages.g.dart' as messages; // (pigeon)コマンドで出力したファイル
import 'view/md_view.dart'; // Markdown表示用画面
import 'view/license_view.dart'; // ライセンス表示用画面

//--------------------------------------------------------------------------------
void main() async {
  // 非同期処理又は外部サービスの初期化が必要な場合は必須
  WidgetsFlutterBinding.ensureInitialized();

  // (window_manager)初期化
  await windowManager.ensureInitialized();
  windowManager.waitUntilReadyToShow(
    const WindowOptions(),
    () async {
      // OSの閉じる処理を無効にする
      await windowManager.setPreventClose(true);
    },
  );

  runApp(const MyApp());
}

//--------------------------------------------------------------------------------
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: MainConstants.title,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      scrollBehavior: CustomScrollBehavior(), // マウスドラッグによるスクロール有効化対応

      // 表示するWidgetの指定
      //home: const MyHomePage(title: MainConstants.title),

      // 使用するWidgetに予め名前を付ける
      routes: {
        '/': (context) => const TooltipVisibility(
              visible: false, // ツールチップを非表示にする
              child: MyHomePage(title: MainConstants.title),
            ),
        '/info': (context) => const MdView(),
        '/about': (context) => const LicenseView(),
      },

      // DEBUG帯表示設定
      debugShowCheckedModeBanner: false,
    );
  }
}

//--------------------------------------------------------------------------------
class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

//--------------------------------------------------------------------------------
// ログデータ用のクラス
final class EntryItem extends LinkedListEntry<EntryItem> {
  final String text;

  EntryItem(this.text);

  @override
  String toString() {
    return text;
  }
}

//--------------------------------------------------------------------------------
// アプリの表示画面
class _MyHomePageState extends State<MyHomePage>
    with
        WindowListener // (window_manager)リスナー制御用
    implements
        messages.MessageFlutterApi // (pigeon)ネイティブからFlutter呼び出し用
{
  //----------------------------------------
  // 初期化処理
  static const isRelease = bool.fromEnvironment('dart.vm.product'); // ビルド種別の確認
  bool _buildInitFlg = false; // build初期化フラグ
  @override
  void initState() {
    super.initState();

    // build完了後にフラグ設定
    WidgetsBinding.instance.addPostFrameCallback((_) => _buildInitFlg = true);

    windowManager.addListener(this); // (window_manager)リスナーの追加
    _initSystemTray(); // (system_tray)システムトレイ関連の初期化
    _initAppData(); // (shared_preferences)アプリの設定データ関連の初期化
    _initStartup(); // (Process.runSync)スタートアップ関連の確認の初期化

    // (pigeon)ネイティブからFlutter呼び出し用の初期化
    messages.MessageFlutterApi.setUp(this);
    _setAppData(); // (pigeon)マウスイベント破棄時間の設定
    //_startMouseEventListening(); // (pigeon)マウスイベント取得開始

    //callMethod('test'); // (MethodChannel)プラットフォーム処理の呼び出し
    // (MethodChannel)プラットフォームからの連携用
    methodChannel.setMethodCallHandler((handler) {
      // メソッドが見つかったら処理する
      switch (handler.method) {
        case 'test':
          return Future.value("0"); // メソッド処理の成否を返す
        default:
          // 指定したメソッドが見つからなかった場合
          throw MissingPluginException();
      }
    });

    // TextField制御用のController準備
    _leftDownDisabledTimeController.addListener(_textFieldLeftDownDisabledTime);
    _leftUpDisabledTimeController.addListener(_textFieldLeftUpDisabledTime);
    _rightDownDisabledTimeController
        .addListener(_textFieldRightDownDisabledTime);
    _rightUpDisabledTimeController.addListener(_textFieldRightUpDisabledTime);
  }

  // 終了処理
  @override
  void dispose() {
    windowManager.removeListener(this); // (window_manager)リスナーの解除

    _cancelMouseEventListening(); // (pigeon)マウスイベント取得停止

    //callMethod('test'); // (MethodChannel)プラットフォーム処理の呼び出し

    // TextField制御用のController解放
    _leftDownDisabledTimeController.dispose();
    _leftUpDisabledTimeController.dispose();
    _rightDownDisabledTimeController.dispose();
    _rightUpDisabledTimeController.dispose();

    // ログデータ削除(念の為)
    _logData.clear();

    // ログデータのスクロール制御用のController解放
    _logScrollController.dispose();

    super.dispose();
  }

  // ウィンドウを閉じる前の処理
  @override
  void onWindowClose() {
    // 終了確認ダイアログを表示する
    showDialog(
      context: context,
      barrierDismissible: false, // ボタン以外でダイアログを閉じないように末う
      builder: (context) => AlertDialog(
        title: MainConstants.closeTitle,
        actions: [
          MainConstants.noButton(
              () => Navigator.of(context).pop()), // ダイアログを閉じる
          MainConstants.yesButton(() async {
            await windowManager.setPreventClose(false); // OSの閉じる処理を有効にする
            await windowManager.close(); // destroyだとタスクトレイにアイコンが残ってしまう
          }), // (window_manager)手動で画面を閉じる処理を実行
        ],
      ),
    );

    super.onWindowClose();
  }
  //----------------------------------------

  //----------------------------------------
  // shared_preferences関連
  // (shared_preferences)アプリの設定データの保存用
  late SharedPreferences prefs;
  bool leftClickCheckFlg = false;
  bool rightClickCheckFlg = false;
  int leftDownDisabledTime = MainConstants.initLeftDownDisabledTime;
  int leftUpDisabledTime = MainConstants.initLeftUpDisabledTime;
  int rightDownDisabledTime = MainConstants.initRightDownDisabledTime;
  int rightUpDisabledTime = MainConstants.initRightUpDisabledTime;

  // (shared_preferences)初期化処理
  Future _initAppData() async {
    prefs = await SharedPreferences.getInstance();
    _loadAppData();
  }

  // (shared_preferences)アプリの設定データの保存
  Future _saveAppData() async {
    await prefs.setBool('leftClickCheckFlg', leftClickCheckFlg);
    await prefs.setBool('rightClickCheckFlg', rightClickCheckFlg);

    await prefs.setInt('leftDownDisabledTime', leftDownDisabledTime);
    await prefs.setInt('leftUpDisabledTime', leftUpDisabledTime);
    await prefs.setInt('rightDownDisabledTime', rightDownDisabledTime);
    await prefs.setInt('rightUpDisabledTime', rightUpDisabledTime);
  }

  // (shared_preferences)ログ表示フラグの保存
  Future _saveLogFlg() async {
    await prefs.setBool('_logViewFlg', _logViewFlg);
  }

  // (shared_preferences)アプリの設定データの読み込み
  void _loadAppData() {
    // アプリの設定データの読み込み
    leftClickCheckFlg = prefs.getBool('leftClickCheckFlg') ?? false;
    rightClickCheckFlg = prefs.getBool('rightClickCheckFlg') ?? false;

    leftDownDisabledTime = prefs.getInt('leftDownDisabledTime') ??
        MainConstants.initLeftDownDisabledTime;
    leftUpDisabledTime = prefs.getInt('leftUpDisabledTime') ??
        MainConstants.initLeftUpDisabledTime;
    rightDownDisabledTime = prefs.getInt('rightDownDisabledTime') ??
        MainConstants.initRightDownDisabledTime;
    rightUpDisabledTime = prefs.getInt('rightUpDisabledTime') ??
        MainConstants.initRightUpDisabledTime;

    _logViewFlg = prefs.getBool('_logViewFlg') ?? true;

    // アプリ画面に表示されるデータも更新
    _setLeftClickCheckFlg(leftClickCheckFlg);
    _setRightClickCheckFlg(rightClickCheckFlg);

    _leftDownDisabledTimeController.text = leftDownDisabledTime.toString();
    _leftUpDisabledTimeController.text = leftUpDisabledTime.toString();
    _rightDownDisabledTimeController.text = rightDownDisabledTime.toString();
    _rightUpDisabledTimeController.text = rightUpDisabledTime.toString();

    _setLogViewFlg(_logViewFlg);
  }
  //----------------------------------------

  //----------------------------------------
  // MethodChannel関連
  // (MethodChannel)プラットフォームとのデータ連携用(チャンネル名は共通にする事)
  static const methodChannel = MethodChannel('yoki/chattering_controller');

  // (MethodChannel)プラットフォーム処理の呼び出し
  Future callMethod(String method) async {
    try {
      final res = await methodChannel.invokeMethod(method);
      debugPrint(res["value"]);
    } catch (e) {
      throw Exception(e);
    }
  }
  //----------------------------------------

  //----------------------------------------
  // pigeon関連
  // (pigeon)プラットフォームとのデータ連携用
  final messages.MessageHostApi _api = messages.MessageHostApi();

  // (pigeon)マウスイベント取得開始
  Future _startMouseEventListening() async {
    try {
      await _api.startMouseEventListening();
    } catch (e) {
      throw Exception(e);
    }
  }

  // (pigeon)マウスイベント取得停止
  Future _cancelMouseEventListening() async {
    try {
      await _api.cancelMouseEventListening();
    } catch (e) {
      throw Exception(e);
    }
  }

  // (pigeon)アプリの設定データの受け渡し
  Future _setAppData() async {
    try {
      await _cancelMouseEventListening(); // 一旦停止

      // 設定データの受け渡し
      await _api.setLeftClickCheckFlg(leftClickCheckFlg);
      await _api.setRightClickCheckFlg(rightClickCheckFlg);

      await _api.setLeftDownDisabledTime(leftDownDisabledTime);
      await _api.setLeftUpDisabledTime(leftUpDisabledTime);
      await _api.setRightDownDisabledTime(rightDownDisabledTime);
      await _api.setRightUpDisabledTime(rightUpDisabledTime);

      await _startMouseEventListening(); // 再開
    } catch (e) {
      throw Exception(e);
    }
  }

  // (pigeon)ログデータの受信
  @override
  void outputLog(String? message) {
    // build処理実行済みであれば処理する
    if (_buildInitFlg) {
      debugPrint(message);
      _addLogData(message);
    }
  }
  //----------------------------------------

  //----------------------------------------
  // system_tray関連
  // (system_tray)システムトレイ関連処理
  final SystemTray _systemTray = SystemTray();
  final Menu _menuMain = Menu();
  late PackageInfo _packageInfo; // (package_info_plus)アプリ情報取得用

  // スタートアップ有効無効設定
  late final MenuItemCheckbox startupCheckbox = MenuItemCheckbox(
      label: MainConstants.systrayStartup,
      checked: startupFlg,
      onClicked: (menuItem) => _setStartupFlg(!menuItem.checked));

  // (system_tray)初期化処理
  Future<void> _initSystemTray() async {
    _packageInfo =
        await PackageInfo.fromPlatform(); // (package_info_plus)アプリ情報の取得

    // システムトレイのアイコン、表示名設定
    final path = Platform.isWindows // Windowsかどうかで使用するアイコン画像を分ける
        ? MainConstants.iconPath
        : MainConstants.iconPathPng;
    await _systemTray.initSystemTray(
        iconPath: path,
        title: _packageInfo.appName,
        toolTip: _packageInfo.appName);

    // システムトレイアイコンのイベント設定
    _systemTray.registerSystemTrayEventHandler((eventName) {
      // 左クリック時
      if (eventName == kSystemTrayEventClick) {
        Platform.isWindows // Windowsの場合とそれ以外で処理を分ける
            ? windowManager.show()
            : _openSystemTray();
        // 右クリック時
      } else if (eventName == kSystemTrayEventRightClick) {
        Platform.isWindows ? _openSystemTray() : windowManager.show();
      }
    });

    // システムトレイのメニュー設定
    await _menuMain.buildFrom([
      MenuItemLabel(
          label: MainConstants.systrayShow,
          onClicked: (menuItem) => windowManager.show()),
      MenuItemLabel(
          label: MainConstants.systrayHide,
          onClicked: (menuItem) => windowManager.hide()),
      MenuSeparator(),
      startupCheckbox,
      MenuSeparator(),
      MenuItemLabel(
        label: MainConstants.systrayDestroy,
        onClicked: (menuItem) async {
          await windowManager.setPreventClose(false); // OSの閉じる処理を有効にする
          await windowManager.close(); // destroyだとタスクトレイにアイコンが残ってしまう
        },
      ),
    ]);
    _systemTray.setContextMenu(_menuMain);
  }

  // システムトレイ表示処理
  Future<void> _openSystemTray() async {
    startupFlg = _checkStartup();
    startupCheckbox.setCheck(startupFlg);
    _systemTray.popUpContextMenu();
  }
  //----------------------------------------

  //----------------------------------------
  // Process.runSync関連 24/10/29 yoki
  // (Process.runSync)スタートアップ関連処理
  bool startupFlg = false;

  late Directory appCacheDirectory;
  late File schtasksXMLFile;

  static const String schtasksCommand = 'schtasks';

  // スタートアップタスク削除
  static const schtasksDelete = [
    '/delete',
    '/F',
    '/TN',
    MainConstants.schtasksName,
  ];

  // スタートアップタスク有無判定用
  static const schtasksQuery = [
    '/query',
    '/FO',
    'CSV',
    '/NH',
    '/TN',
    MainConstants.schtasksName,
  ];

  // (Process.runSync)初期化処理
  void _initStartup() async {
    try {
      // アプリのキャッシュフォルダパスの取得
      appCacheDirectory = await getApplicationCacheDirectory();

      // スタートアップタスク用XMLファイルの保存先(元ファイルとは別に保存する)
      schtasksXMLFile =
          File('${appCacheDirectory.path}/${MainConstants.schtasksXMLPath}');
    } catch (e) {
      throw Exception(e);
    }

    // スタートアップタスク有無判定
    startupFlg = _checkStartup();
  }

  // XMLファイルからスタートアップタスク作成
  void _createStartupTask() async {
    try {
      // スタートアップタスク用XMLファイルの読み込み
      // アプリ配布の際はassetsフォルダの位置が異なるので分けておく
      final xmlFile = File(isRelease
          ? MainConstants.releaseAssetsPath + MainConstants.schtasksXMLPath
          : MainConstants.debugAssetsPath + MainConstants.schtasksXMLPath);

      // XMLデータの読み込み(ファイル有無判定はassetsからの読み込みなので省略)
      final xmlDoc = XmlDocument.parse(xmlFile.readAsStringSync());

      // アプリの実行パスを設定
      final xmlCommand = xmlDoc.findAllElements('Command');

      // パスに空白が含まれるとパラメーターと認識されてしまうので""で囲む
      xmlCommand.first.innerText = '"${Platform.resolvedExecutable}"';

      // スタートアップタスク用XMLファイルの保存
      if (await schtasksXMLFile.exists()) {
        schtasksXMLFile.create();
      }
      schtasksXMLFile.writeAsString(xmlDoc.toXmlString());

      Process.runSync(schtasksCommand, [
        '/create',
        '/F',
        '/TN',
        MainConstants.schtasksName,
        '/XML',
        schtasksXMLFile.path
      ]);
    } catch (e) {
      throw Exception(e);
    }
  }

  // スタートアップ有効無効確認
  bool _checkStartup() {
    // スタートアップタスク有無判定
    ProcessResult result = Process.runSync(schtasksCommand, schtasksQuery);

    // result.exitCode = OK:0, Error:0以外
    if (result.exitCode == 0) {
      // 念の為、スタートアップタスクを設定しなおす
      _createStartupTask();
      return true;
    } else {
      return false;
    }
  }

  // スタートアップ有効無効設定
  void _setStartupFlg(bool flg) {
    if (flg) {
      // 念の為、スタートアップタスクを設定しなおす
      _createStartupTask();
    } else {
      // スタートアップタスクを削除
      Process.runSync(schtasksCommand, schtasksDelete);
    }

    setState(() {
      startupFlg = flg;
      startupCheckbox.setCheck(startupFlg);
    });
  }
  //----------------------------------------

/*
  //----------------------------------------
  // win32_registry関連
  // (win32_registry)スタートアップ関連処理
  bool startupFlg = false;

  static const valueName = 'Chattering_Controller';
  static const exeKeyPath = r'SOFTWARE\Microsoft\Windows\CurrentVersion\Run';
  static const runKeyPath =
      r'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run';

  static var runEnableValue = RegistryValue(valueName, RegistryValueType.binary,
      [0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]);

  static var runDisableValue = RegistryValue(
      valueName,
      RegistryValueType.binary,
      [0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]);

  // (win32_registry)初期化処理
  Future<void> _initStartup() async {
    // 実行ファイルの場所設定
    final exeKey = Registry.openPath(RegistryHive.localMachine,
        path: exeKeyPath, desiredAccessRights: AccessRights.allAccess);
    final exeParam = exeKey.getValueAsString(valueName);

    final exeValue = RegistryValue(
        valueName, RegistryValueType.string, Platform.resolvedExecutable);

    if (exeParam == null) {
      // レジストリに未設定の場合は追加する
      exeKey.createValue(exeValue);
    } else if (exeParam != Platform.resolvedExecutable) {
      // 実行ファイルの場所が異なっていた場合は作り直す
      exeKey.deleteValue(valueName);
      exeKey.createValue(exeValue);
    }
    exeKey.close();

    // スタートアップ有効無効設定
    final runKey = Registry.openPath(RegistryHive.localMachine,
        path: runKeyPath, desiredAccessRights: AccessRights.allAccess);
    final runParam = runKey.getValue(valueName);

    if (runParam == null) {
      runKey.createValue(runDisableValue);
      startupFlg = false;
    } else {
      if (runParam.type == RegistryValueType.binary) {
        List<int>? listInt = runParam.data as List<int>?;
        if (listInt != null) {
          if (listInt[0] == 2) {
            startupFlg = true;
          } else {
            startupFlg = false;
          }
        } else {
          // データがうまく読み込めなかった場合は作成し直す
          runKey.deleteValue(valueName);
          runKey.createValue(runDisableValue);
          startupFlg = false;
        }
      } else {
        // データがバイナリ以外の場合は作成し直す
        runKey.deleteValue(valueName);
        runKey.createValue(runDisableValue);
        startupFlg = false;
      }
    }
    runKey.close();
  }

  // スタートアップ有効無効確認
  bool _checkStartup() {
    final runKey =
        Registry.openPath(RegistryHive.localMachine, path: runKeyPath);
    final runParam = runKey.getValue(valueName);

    if (runParam != null) {
      if (runParam.type == RegistryValueType.binary) {
        List<int>? listInt = runParam.data as List<int>?;
        if (listInt != null) {
          if (listInt[0] == 2) {
            runKey.close();
            return true;
          }
        }
      }
    }
    runKey.close();
    return false;
  }

  // スタートアップ有効無効設定
  Future<void> _setStartupFlg(bool flg) async {
    final runKey = Registry.openPath(RegistryHive.localMachine,
        path: runKeyPath, desiredAccessRights: AccessRights.allAccess);
    runKey.deleteValue(valueName);
    if (flg) {
      runKey.createValue(runEnableValue);
    } else {
      runKey.createValue(runDisableValue);
    }
    runKey.close();

    setState(() {
      startupFlg = flg;
      startupCheckbox.setCheck(startupFlg);
    });
  }
  //----------------------------------------
*/

  //----------------------------------------
  // サイドナビゲーションメニュー(drawer)の「About」選択時の処理
  // (アプリのMarkdown表示)
  void _pushInfo() {
    _homeWidgetKey.currentState?.closeDrawer(); // 先にdrawerを閉じる
    //Navigator.of(context).pop();  // こちらでも閉じれるが、上記の直接指定なら誤動作の心配が無い
    Navigator.of(context).pushNamed('/info');
  }

  // サイドナビゲーションメニュー(drawer)の「About」選択時の処理
  // (アプリで使用しているライブラリのライセンス表示)
  void _pushAbout() {
    _homeWidgetKey.currentState?.closeDrawer(); // 先にdrawerを閉じる
    //Navigator.of(context).pop();  // こちらでも閉じれるが、上記の直接指定なら誤動作の心配が無い
    Navigator.of(context).pushNamed('/about');
  }
  //----------------------------------------

  //----------------------------------------
  // 表示画面関連
  // Widget制御用のGlobalKey
  final GlobalKey<ScaffoldState> _homeWidgetKey = GlobalKey<ScaffoldState>();

  // ボタンの長押し制御用
  bool _longPressFlag = false;

  // TextField制御用のController
  final TextEditingController _leftDownDisabledTimeController =
      TextEditingController();
  final TextEditingController _leftUpDisabledTimeController =
      TextEditingController();
  final TextEditingController _rightDownDisabledTimeController =
      TextEditingController();
  final TextEditingController _rightUpDisabledTimeController =
      TextEditingController();

  // ログ表示フラグ
  bool _logViewFlg = true;

  // ログデータのスクロール制御用
  final ScrollController _logScrollController = ScrollController();

  // ログデータ(growable: true で可変長)
  //final _logData = List<String>.empty(growable: true);

  // リストへの追加削除を頻繁に行うのでこちらの方が早い
  final _logData = LinkedList<EntryItem>();

  // 表示画面の生成
  @override
  Widget build(BuildContext context) {
    // 画面構築(上から順番に生成)
    return Scaffold(
      // Widget制御用のGlobalKey
      key: _homeWidgetKey,

      // アプリのタイトルバー
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(
          widget.title,
          style: MainConstants.titleStyle,
        ),
      ),

      // 表示するWidget
      // ListViewで縦に複数配置
      body: ListView(
        // 表示内容
        children: <Widget>[
          //----------------------------------------
          // 左クリック監視フラグ
          CheckboxListTile(
            controlAffinity: ListTileControlAffinity.leading,
            title: MainConstants.leftClickCheckTitle,
            tileColor: MainConstants.disabledTimeTileColor,
            value: leftClickCheckFlg,
            onChanged: (bool? flg) {
              _setLeftClickCheckFlg(flg!);
            },
          ),

          Container(
            padding: MainConstants.disabledTimeContainerPadding,
            decoration: BoxDecoration(
                border: Border.all(
                    color: MainConstants.disabledTimeContainerBorderColor)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                SizedBox(
                  width: MainConstants.disabledTimeTitleWidth,
                  // disabled表現の為に疑似的にテキストボタンを使い、
                  // ボタン操作イベントはAbsorbPointerで封印
                  // Tabキーによるフォーカス移動はExcludeFocusで封印
                  child: AbsorbPointer(
                    absorbing: true,
                    child: ExcludeFocus(
                      excluding: true,
                      child: TextButton(
                        onPressed: leftClickCheckFlg ? () {} : null,
                        child: const Align(
                            alignment: Alignment.centerLeft,
                            child: MainConstants.downDisabledTimeTitle),
                      ),
                    ),
                  ),
                ),

                // Down破棄判定時間入力フィールド
                SizedBox(
                  width: MainConstants.disabledTimeFieldWidth,
                  child: TextField(
                    controller: _leftDownDisabledTimeController,
                    enabled: leftClickCheckFlg,
                    style: MainConstants.disabledTimeFieldFontStyle,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),

                AbsorbPointer(
                  absorbing: true,
                  child: ExcludeFocus(
                    excluding: true,
                    child: TextButton(
                        onPressed: leftClickCheckFlg ? () {} : null,
                        child: MainConstants.disabledTimeUnit),
                  ),
                ),

                // Down破棄判定時間増減ボタン
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    GestureDetector(
                      child: OutlinedButton(
                        onPressed: leftClickCheckFlg
                            ? _incrementLeftDownDisabledTime
                            : null,
                        child: const Icon(Icons.add),
                      ),

                      // ボタン長押しで連続で増加処理
                      onLongPress: () async {
                        if (leftClickCheckFlg) {
                          _longPressFlag = true;
                          while (_longPressFlag) {
                            _incrementLeftDownDisabledTime();
                            await Future.delayed(
                                const Duration(milliseconds: 100));
                          }
                        }
                      },

                      // ボタン長押し解除
                      onLongPressEnd: (detail) {
                        _longPressFlag = false;
                      },
                    ),
                    GestureDetector(
                      child: OutlinedButton(
                        onPressed: leftClickCheckFlg
                            ? _decrementLeftDownDisabledTime
                            : null,
                        child: const Icon(Icons.remove),
                      ),

                      // ボタン長押しで連続で減少処理
                      onLongPress: () async {
                        if (leftClickCheckFlg) {
                          _longPressFlag = true;
                          while (_longPressFlag) {
                            _decrementLeftDownDisabledTime();
                            await Future.delayed(
                                const Duration(milliseconds: 100));
                          }
                        }
                      },

                      // ボタン長押し解除
                      onLongPressEnd: (detail) {
                        _longPressFlag = false;
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),

          Container(
            padding: MainConstants.disabledTimeContainerPadding,
            decoration: BoxDecoration(
                border: Border.all(
                    color: MainConstants.disabledTimeContainerBorderColor)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                SizedBox(
                  width: MainConstants.disabledTimeTitleWidth,
                  child: AbsorbPointer(
                    absorbing: true,
                    child: ExcludeFocus(
                      excluding: true,
                      child: TextButton(
                        onPressed: leftClickCheckFlg ? () {} : null,
                        child: const Align(
                          alignment: Alignment.centerLeft,
                          child: MainConstants.upDisabledTimeTitle,
                        ),
                      ),
                    ),
                  ),
                ),

                // Up破棄判定時間入力フィールド
                SizedBox(
                  width: MainConstants.disabledTimeFieldWidth,
                  child: TextField(
                    controller: _leftUpDisabledTimeController,
                    enabled: leftClickCheckFlg,
                    style: MainConstants.disabledTimeFieldFontStyle,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
                AbsorbPointer(
                  absorbing: true,
                  child: ExcludeFocus(
                    excluding: true,
                    child: TextButton(
                        onPressed: leftClickCheckFlg ? () {} : null,
                        child: MainConstants.disabledTimeUnit),
                  ),
                ),

                // Up破棄判定時間増減ボタン
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    GestureDetector(
                      child: OutlinedButton(
                        onPressed: leftClickCheckFlg
                            ? _incrementLeftUpDisabledTime
                            : null,
                        child: const Icon(Icons.add),
                      ),

                      // ボタン長押しで連続で増加処理
                      onLongPress: () async {
                        if (leftClickCheckFlg) {
                          _longPressFlag = true;
                          while (_longPressFlag) {
                            _incrementLeftUpDisabledTime();
                            await Future.delayed(
                                const Duration(milliseconds: 100));
                          }
                        }
                      },

                      // ボタン長押し解除
                      onLongPressEnd: (detail) {
                        _longPressFlag = false;
                      },
                    ),
                    GestureDetector(
                      child: OutlinedButton(
                        onPressed: leftClickCheckFlg
                            ? _decrementLeftUpDisabledTime
                            : null,
                        child: const Icon(Icons.remove),
                      ),

                      // ボタン長押しで連続で減少処理
                      onLongPress: () async {
                        if (leftClickCheckFlg) {
                          _longPressFlag = true;
                          while (_longPressFlag) {
                            _decrementLeftUpDisabledTime();
                            await Future.delayed(
                                const Duration(milliseconds: 100));
                          }
                        }
                      },

                      // ボタン長押し解除
                      onLongPressEnd: (detail) {
                        _longPressFlag = false;
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          //----------------------------------------

          //----------------------------------------
          // 右クリック監視フラグ
          CheckboxListTile(
            controlAffinity: ListTileControlAffinity.leading,
            title: MainConstants.rightClickCheckTitle,
            tileColor: MainConstants.disabledTimeTileColor,
            value: rightClickCheckFlg,
            onChanged: (bool? flg) {
              _setRightClickCheckFlg(flg!);
            },
          ),

          Container(
            padding: MainConstants.disabledTimeContainerPadding,
            decoration: BoxDecoration(
                border: Border.all(
                    color: MainConstants.disabledTimeContainerBorderColor)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                SizedBox(
                  width: MainConstants.disabledTimeTitleWidth,
                  child: AbsorbPointer(
                    absorbing: true,
                    child: ExcludeFocus(
                      excluding: true,
                      child: TextButton(
                        onPressed: rightClickCheckFlg ? () {} : null,
                        child: const Align(
                            alignment: Alignment.centerLeft,
                            child: MainConstants.downDisabledTimeTitle),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: MainConstants.disabledTimeFieldWidth,
                  child: TextField(
                    controller: _rightDownDisabledTimeController,
                    enabled: rightClickCheckFlg,
                    style: MainConstants.disabledTimeFieldFontStyle,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
                AbsorbPointer(
                  absorbing: true,
                  child: ExcludeFocus(
                    excluding: true,
                    child: TextButton(
                        onPressed: rightClickCheckFlg ? () {} : null,
                        child: MainConstants.disabledTimeUnit),
                  ),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    GestureDetector(
                      child: OutlinedButton(
                        onPressed: rightClickCheckFlg
                            ? _incrementRightDownDisabledTime
                            : null,
                        child: const Icon(Icons.add),
                      ),
                      onLongPress: () async {
                        if (rightClickCheckFlg) {
                          _longPressFlag = true;
                          while (_longPressFlag) {
                            _incrementRightDownDisabledTime();
                            await Future.delayed(
                                const Duration(milliseconds: 100));
                          }
                        }
                      },
                      onLongPressEnd: (detail) {
                        _longPressFlag = false;
                      },
                    ),
                    GestureDetector(
                      child: OutlinedButton(
                        onPressed: rightClickCheckFlg
                            ? _decrementRightDownDisabledTime
                            : null,
                        child: const Icon(Icons.remove),
                      ),

                      // ボタン長押しで連続で減少処理
                      onLongPress: () async {
                        if (rightClickCheckFlg) {
                          _longPressFlag = true;
                          while (_longPressFlag) {
                            _decrementRightDownDisabledTime();
                            await Future.delayed(
                                const Duration(milliseconds: 100));
                          }
                        }
                      },
                      onLongPressEnd: (detail) {
                        _longPressFlag = false;
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),

          Container(
            padding: MainConstants.disabledTimeContainerPadding,
            decoration: BoxDecoration(
                border: Border.all(
                    color: MainConstants.disabledTimeContainerBorderColor)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                SizedBox(
                  width: MainConstants.disabledTimeTitleWidth,
                  child: AbsorbPointer(
                    absorbing: true,
                    child: ExcludeFocus(
                      excluding: true,
                      child: TextButton(
                        onPressed: rightClickCheckFlg ? () {} : null,
                        child: const Align(
                          alignment: Alignment.centerLeft,
                          child: MainConstants.upDisabledTimeTitle,
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: MainConstants.disabledTimeFieldWidth,
                  child: TextField(
                    controller: _rightUpDisabledTimeController,
                    enabled: rightClickCheckFlg,
                    style: MainConstants.disabledTimeFieldFontStyle,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
                AbsorbPointer(
                  absorbing: true,
                  child: ExcludeFocus(
                    excluding: true,
                    child: TextButton(
                        onPressed: rightClickCheckFlg ? () {} : null,
                        child: MainConstants.disabledTimeUnit),
                  ),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    GestureDetector(
                      child: OutlinedButton(
                        onPressed: rightClickCheckFlg
                            ? _incrementRightUpDisabledTime
                            : null,
                        child: const Icon(Icons.add),
                      ),
                      onLongPress: () async {
                        if (rightClickCheckFlg) {
                          _longPressFlag = true;
                          while (_longPressFlag) {
                            _incrementRightUpDisabledTime();
                            await Future.delayed(
                                const Duration(milliseconds: 100));
                          }
                        }
                      },
                      onLongPressEnd: (detail) {
                        _longPressFlag = false;
                      },
                    ),
                    GestureDetector(
                      child: OutlinedButton(
                        onPressed: rightClickCheckFlg
                            ? _decrementRightUpDisabledTime
                            : null,
                        child: const Icon(Icons.remove),
                      ),
                      onLongPress: () async {
                        if (rightClickCheckFlg) {
                          _longPressFlag = true;
                          while (_longPressFlag) {
                            _decrementRightUpDisabledTime();
                            await Future.delayed(
                                const Duration(milliseconds: 100));
                          }
                        }
                      },
                      onLongPressEnd: (detail) {
                        _longPressFlag = false;
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          //----------------------------------------

          //----------------------------------------
          // 設定適用ボタン
          MainConstants.settingsAppliedButton(_settingsAppliedButton),
          //----------------------------------------

          //----------------------------------------
          // イベントログ
          Container(
            padding: MainConstants.eventLogContainerPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                CheckboxListTile(
                  controlAffinity: ListTileControlAffinity.leading,
                  title: MainConstants.eventLogTitle,
                  tileColor: MainConstants.eventLogTitleTileColor,
                  value: _logViewFlg,
                  onChanged: (bool? flg) {
                    _setLogViewFlg(flg!);
                  },
                ),
                MainConstants.eventLogView(
                    _logScrollController, _outputLogData),
              ],
            ),
          ),
          //----------------------------------------
        ],
      ),

      // サイドナビゲーションメニューの状態確認
      onDrawerChanged: (bool isDrawerOpen) async {
        // 表示前にスタートアップ設定を確認する
        if (isDrawerOpen) {
          setState(() {
            startupFlg = _checkStartup();
            startupCheckbox.setCheck(startupFlg);
          });
        }
      },

      // サイドナビゲーションメニュー(左)の表示内容
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            // 表題
            MainDrawerConstants.title,
            // メニュー
            CheckboxListTile(
              controlAffinity: ListTileControlAffinity.leading,
              title: MainDrawerConstants.startup,
              value: startupFlg,
              onChanged: (bool? flg) {
                _setStartupFlg(flg!);
              },
            ),
            ListTile(
              title: MainDrawerConstants.info,
              onTap: _pushInfo,
            ),
            ListTile(
              title: MainDrawerConstants.about,
              onTap: _pushAbout,
            ),
          ],
        ),
      ),
    );
  }
  //----------------------------------------

  //----------------------------------------
  // 左クリック監視フラグの設定
  void _setLeftClickCheckFlg(bool flg) {
    setState(() {
      leftClickCheckFlg = flg;
    });
  }

  // 右クリック監視フラグの設定
  void _setRightClickCheckFlg(bool flg) {
    setState(() {
      rightClickCheckFlg = flg;
    });
  }

  // マウスイベント破棄時間のチェック
  int checkInputDisabledTime(String text) {
    int value;
    try {
      value = int.parse(text);
    } catch (e) {
      value = 1;
    }

    if (value < MainConstants.minDisabledTime) {
      value = MainConstants.minDisabledTime;
    }
    if (MainConstants.maxDisabledTime < value) {
      value = MainConstants.maxDisabledTime;
    }
    return value;
  }

  // ログ出力フラグの設定
  void _setLogViewFlg(bool flg) {
    setState(() {
      _logViewFlg = flg;
    });

    _saveLogFlg(); // フラグの状態を保存
  }

  //----------------------------------------
  // 破棄判定時間の増減処理
  // 左Down
  void _textFieldLeftDownDisabledTime() {
    // 入力された数値のチェック
    // 問題なければそのままの数値、小さければ最小値、大きければ最大値を返す
    leftDownDisabledTime =
        checkInputDisabledTime(_leftDownDisabledTimeController.text);

    // 数値と表示内容が一致していなければ表示内容を数値に更新する
    String disabledTimeText = leftDownDisabledTime.toString();
    if (disabledTimeText != _leftDownDisabledTimeController.text) {
      _leftDownDisabledTimeController.text = disabledTimeText;
    }
  }

  void _incrementLeftDownDisabledTime() {
    leftDownDisabledTime++;
    _leftDownDisabledTimeController.text = leftDownDisabledTime.toString();
  }

  void _decrementLeftDownDisabledTime() {
    leftDownDisabledTime--;
    _leftDownDisabledTimeController.text = leftDownDisabledTime.toString();
  }

  //----------------------------------------
  // 左Up
  void _textFieldLeftUpDisabledTime() {
    leftUpDisabledTime =
        checkInputDisabledTime(_leftUpDisabledTimeController.text);

    String disabledTimeText = leftUpDisabledTime.toString();
    if (disabledTimeText != _leftUpDisabledTimeController.text) {
      _leftUpDisabledTimeController.text = disabledTimeText;
    }
  }

  void _incrementLeftUpDisabledTime() {
    leftUpDisabledTime++;
    _leftUpDisabledTimeController.text = leftUpDisabledTime.toString();
  }

  void _decrementLeftUpDisabledTime() {
    leftUpDisabledTime--;
    _leftUpDisabledTimeController.text = leftUpDisabledTime.toString();
  }

  //----------------------------------------
  // 右Down
  void _textFieldRightDownDisabledTime() {
    rightDownDisabledTime =
        checkInputDisabledTime(_rightDownDisabledTimeController.text);

    String disabledTimeText = rightDownDisabledTime.toString();
    if (disabledTimeText != _rightDownDisabledTimeController.text) {
      _rightDownDisabledTimeController.text = disabledTimeText;
    }
  }

  void _incrementRightDownDisabledTime() {
    rightDownDisabledTime++;
    _rightDownDisabledTimeController.text = rightDownDisabledTime.toString();
  }

  void _decrementRightDownDisabledTime() {
    rightDownDisabledTime--;
    _rightDownDisabledTimeController.text = rightDownDisabledTime.toString();
  }

  //----------------------------------------
  // 右Up
  void _textFieldRightUpDisabledTime() {
    rightUpDisabledTime =
        checkInputDisabledTime(_rightUpDisabledTimeController.text);

    String disabledTimeText = rightUpDisabledTime.toString();
    if (disabledTimeText != _rightUpDisabledTimeController.text) {
      _rightUpDisabledTimeController.text = disabledTimeText;
    }
  }

  void _incrementRightUpDisabledTime() {
    rightUpDisabledTime++;
    _rightUpDisabledTimeController.text = rightUpDisabledTime.toString();
  }

  void _decrementRightUpDisabledTime() {
    rightUpDisabledTime--;
    _rightUpDisabledTimeController.text = rightUpDisabledTime.toString();
  }

  //----------------------------------------
  // 設定適用ボタン
  void _settingsAppliedButton() {
    _saveAppData();
    _setAppData();
  }

  //----------------------------------------
  // ログデータの出力
  TextSpan _outputLogData() {
    return TextSpan(children: [
      for (final data in _logData) ...{
        TextSpan(
          //text: data,
          text: data.toString(),
          style: MainConstants.eventLogFontStyle,
        )
      }
    ]);
  }

  // ログデータの追加処理
  void _addLogData(String? message) {
    if (_logViewFlg) {
      // 現在のログ画面のサイズとスクロール位置の確認
      bool scrollFlg = false;
      double scrollMax = _logScrollController.position.maxScrollExtent;
      double scrollPos = _logScrollController.position.pixels +
          MainConstants.eventLogFontSize * 2;

      // 一番下までスクロールさせていた場合
      if (scrollMax <= scrollPos) {
        scrollFlg = true;
      }

      // ログ表示件数を超えた分を削除
      while (MainConstants.eventLogLength <= _logData.length) {
        //_logData.removeAt(0); // 表示遅延の原因、1要素づつ詰めコピー処理が発生
        _logData.remove(_logData.first);
      }

      // ログ表示領域の更新
      setState(() {
        //_logData.add("$message\n"); // ここで改行を付けておく
        _logData.add(EntryItem("$message\n"));

        // 追加された分スクロールさせる
        if (scrollFlg) {
          _logScrollController.jumpTo(scrollPos);
        }
      });
    }
  }
  //----------------------------------------
}
