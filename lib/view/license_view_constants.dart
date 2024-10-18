//--------------------------------------------------------------------------------
// license_view関連の定数
// new 24/06/17 yoki
//--------------------------------------------------------------------------------
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// 外部パッケージ
import 'package:flutter_html/flutter_html.dart';

// view関連の定数
import 'view_constants.dart';

// ライセンス表示画面用の定数
class LicenseViewConstants {
  // 表題
  static const Text title = Text(
    '権利表記',
    style: TextStyle(
      fontSize: 20.0,
      fontWeight: FontWeight.bold,
    ),
  );

  // アプリアイコン
  static Image appIcon(String iconPath) {
    return Image.asset(
      iconPath,
      width: 64.0,
      height: 64.0,
    );
  }

  // アプリ名
  static Text appName(String name) {
    return Text(
      name,
      style: const TextStyle(fontSize: 40.0),
    );
  }

  // アプリのバージョン表示
  static Text appVersion(String version) {
    return Text(
      'バージョン: $version',
      style: const TextStyle(fontSize: 20.0),
    );
  }

  // アプリのビルド番号表示
  static Text appBuildNumber(String buildNumber) {
    return Text(
      'ビルド番号: $buildNumber',
      style: const TextStyle(fontSize: 20.0),
    );
  }

  // アイコン画像の権利表記(icons8)
  static Html appIconLicense = Html(
    data:
        '<p style="font-size:16px; text-align:center">icons by <a target="_blank" href="https://icons8.jp">Icons8</a></p>',
    onLinkTap: (url, _, __) {
      HtmlConstants.urlLink(url!);
    },
  );

  // パッケージ一覧カードの高さ
  static const double contentCardHeight = 80.0;

  // パッケージ一覧カード生成
  static Card makePackageCard(String key, List<List<LicenseParagraph>> value) {
    return Card(
        child: Column(children: [
      ListTile(
        title: Text(' $key', style: const TextStyle(fontSize: 20.0)),
        subtitle: Text(' ${value.length} licenses.',
            style: const TextStyle(fontSize: 14.0)),
      )
    ]));
  }

  // ライセンス詳細表示のインデント用
  static const double licenseIndent = 16.0;
}
