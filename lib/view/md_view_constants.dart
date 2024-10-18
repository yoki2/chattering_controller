//--------------------------------------------------------------------------------
// md_view関連の定数
// new 24/09/12 yoki
//--------------------------------------------------------------------------------
import 'package:flutter/material.dart';

// Markdown表示用の定数
class MdViewConstants {
  // 表題
  static const Text title = Text(
    'このアプリケーションについて',
    style: TextStyle(
      fontSize: 20.0,
      fontWeight: FontWeight.bold,
    ),
  );

  // mdファイルのパス
  static const String mdPath = 'README.md';

  // Markdownの枠外余白
  static const EdgeInsets mdPadding = EdgeInsets.fromLTRB(10.0, 5.0, 0.0, 0.0);
}
