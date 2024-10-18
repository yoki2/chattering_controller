//--------------------------------------------------------------------------------
// view関連の定数
// new 24/06/17 yoki
//--------------------------------------------------------------------------------
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:url_launcher/url_launcher.dart';

// サイドナビゲーションメニュー(左)用の定数
class SubDrawerConstants {
  // 前の画面に戻る用アイコンボタン
  static IconButton backButton(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back, color: Colors.black),
      onPressed: () => Navigator.of(context).pop(),
    );
  }
}

// ダイアログ用の定数
class AlertConstants {
  // タイトルテキスト設定
  static const TextStyle titleTextStyle = TextStyle(fontSize: 24.0);

  // 内容テキスト設定
  static const TextStyle contentTextStyle = TextStyle(fontSize: 12.0);

  // OKボタン設定
  static const Text okButton = Text(
    'OK',
    style: TextStyle(fontSize: 16.0),
  );
}

// 読み込み中表現用の定数
class IndicatorConstants {
  // 中央にインジケーターを表示
  static const Center nowLoading = Center(
      child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[CircularProgressIndicator()]));

  // 読み込み失敗時の表示用
  static Text loadingError(Object? error) {
    return Text('Error:$error');
  }
}

// HTML表示関連
class HtmlConstants {
  // URLリンク選択時の処理用
  static void urlLink(String? url) async {
    Uri uri = Uri.parse(url!);
    if (!await launchUrl(uri)) {
      throw Exception('Could not launch $url');
    }
  }

  // Table表示用(flutter_html_tableパッケージが必要)
  static Map<String, Style> tableStyle = {
    "table": Style(
      padding: HtmlPaddings(bottom: HtmlPadding(10)),
    ),
    "tr": Style(
        padding: HtmlPaddings.all(10), border: Border.all(color: Colors.black)),
    "th": Style(
        padding: HtmlPaddings.all(10), border: Border.all(color: Colors.black)),
    "td": Style(
        padding: HtmlPaddings.all(10), border: Border.all(color: Colors.black)),
  };
}
