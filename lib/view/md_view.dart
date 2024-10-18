//--------------------------------------------------------------------------------
// Markdown表示用画面
// new 24/09/12 yoki
//--------------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

// 外部パッケージ
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_html_table/flutter_html_table.dart';
import 'package:markdown/markdown.dart';

// view関連の定数
import 'view_constants.dart';
import 'md_view_constants.dart';

class MdView extends StatefulWidget {
  const MdView({super.key});

  @override
  State<MdView> createState() => _MdViewState();
}

class _MdViewState extends State<MdView> {
  @override
  void initState() {
    super.initState();
  }

  // Markdownファイルから文字列データを取得
  Future<String> loadMd() async {
    return await rootBundle.loadString(MdViewConstants.mdPath);
  }

  // Markdownデータ表示
  Widget viewMdData() {
    return FutureBuilder<String>(
        future: loadMd(),
        builder: (context, AsyncSnapshot<String> snapshot) {
          // 読み込み中の表示
          if (snapshot.connectionState == ConnectionState.waiting) {
            // 中央にインジケーターを表示
            return IndicatorConstants.nowLoading;
          }
          // 読み込み失敗時の表示
          if (snapshot.hasError) {
            return IndicatorConstants.loadingError(snapshot.error);
          }
          // 読み込み完了時の表示
          return SingleChildScrollView(
            // Markdownを表示するパッケージは複数見つけたが、
            // どれもHTMLタグをそのまま出力していたので、
            // 別案としてHTML形式に変換するパッケージと、
            // HTML表示するパッケージを使用
            child: Html(
              data: markdownToHtml(snapshot.data!),
              onLinkTap: (url, _, __) => HtmlConstants.urlLink(url!),
              extensions: [
                TableHtmlExtension(),
              ],
              style: HtmlConstants.tableStyle,
            ),
          );
        });
  }

  @override
  Scaffold build(BuildContext context) {
    return Scaffold(
      // アプリのタイトルバー
      appBar: AppBar(
        // 前の画面に戻るボタン
        leading: SubDrawerConstants.backButton(context),
        // 背景色
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // タイトル
        title: MdViewConstants.title,
      ),

      body: Container(
        padding: MdViewConstants.mdPadding,
        child: viewMdData(),
      ),
    );
  }
}
