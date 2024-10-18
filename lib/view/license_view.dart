//--------------------------------------------------------------------------------
// アプリで使用しているパッケージ等のライセンス表示用画面
// new 24/05/06 yoki
//--------------------------------------------------------------------------------
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// 外部パッケージ
import 'package:package_info_plus/package_info_plus.dart';
import 'package:link_text/link_text.dart';

// view関連の定数
import '../main_constants.dart';
import 'view_constants.dart';
import 'license_view_constants.dart';

class LicenseView extends StatefulWidget {
  const LicenseView({super.key});

  @override
  State<LicenseView> createState() => _LicenseViewState();
}

class _LicenseViewState extends State<LicenseView> {
  // アプリのバージョン情報等の取得
  Future<PackageInfo> getPackageInfo() async {
    PackageInfo packageInfo;

    try {
      packageInfo = await PackageInfo.fromPlatform();
    } catch (e) {
      throw Exception(e);
    }

    return packageInfo;
  }

  // アプリで利用しているパッケージのライセンス情報を非同期で取得
  Future<Map<String, List<List<LicenseParagraph>>>> getLicenseInfo() async {
    Map<String, List<List<LicenseParagraph>>> licenseInfo = {};

    try {
      // アプリで利用しているパッケージのライセンス情報の取得
      final licenseEntries = await LicenseRegistry.licenses.toList();

      for (var entry in licenseEntries) {
        for (var element in entry.packages) {
          // 1つのパッケージに複数のライセンス情報が存在する場合があるので
          // とりあえずライセンス情報を連結して表示する
          if (licenseInfo.containsKey(element)) {
            licenseInfo[element]!.add(entry.paragraphs.toList());
          } else {
            licenseInfo[element] = [entry.paragraphs.toList()];
          }
        }
      }
    } catch (e) {
      throw Exception(e);
    }

    return licenseInfo;
  }

  // パッケージのライセンス詳細情報をダイアログで表示
  Widget viewLicenseAlert(String title, List<Widget> content) {
    return AlertDialog(
      title: Text(
        title,
        style: AlertConstants.titleTextStyle,
      ),
      // 表示内容が多い場合、スクロール可能な状態にする
      content: SingleChildScrollView(
        child: ListBody(
          children: content,
        ),
      ),
      actions: <Widget>[
        // OKボタン
        ElevatedButton(
          onPressed: () => Navigator.pop(context), // ダイアログを閉じる
          child: AlertConstants.okButton,
        ),
      ],
    );
  }

  // アプリのバージョン情報等の表示
  Widget viewPackageInfo() {
    return FutureBuilder<PackageInfo>(
      future: getPackageInfo(), // アプリの情報等を取得する処理
      builder: (context, AsyncSnapshot<PackageInfo> snapshot) {
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
        return Column(
          children: [
            LicenseViewConstants.appIcon(MainConstants.iconPathPng),
            LicenseViewConstants.appName(snapshot.data!.appName),
            LicenseViewConstants.appVersion(snapshot.data!.version),
            LicenseViewConstants.appBuildNumber(snapshot.data!.buildNumber),
            LicenseViewConstants.appIconLicense,
          ],
        );
      },
    );
  }

  // ライセンス情報のリスト表示
  Widget viewLicenseInfo() {
    return FutureBuilder<Map<String, List<List<LicenseParagraph>>>>(
        future: getLicenseInfo(), // ライセンス情報を取得する処理
        builder: (context,
            AsyncSnapshot<Map<String, List<List<LicenseParagraph>>>> snapshot) {
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
          return ListView.builder(
              itemCount: snapshot.data!.length,
              itemBuilder: (context, index) {
                final key = snapshot.data!.keys.elementAt(index);
                final value = snapshot.data![key]!;

                // 選択したらダイアログで詳細表示
                return InkWell(
                    child: SizedBox(
                      height: LicenseViewConstants.contentCardHeight,
                      child: LicenseViewConstants.makePackageCard(key, value),
                    ),
                    onTap: () {
                      showDialog<void>(
                          context: context,
                          builder: (_) {
                            return viewLicenseAlert(
                              key,
                              // ライセンスの詳細を見易く成形
                              <Widget>[
                                for (var license in value) ...{
                                  Column(children: [
                                    for (var paragraph in license) ...{
                                      // paragraph.indentがマイナスの場合、
                                      // ネガティブマージンとなって例外エラーが発生する
                                      if (0 <= paragraph.indent) ...{
                                        Padding(
                                          padding: EdgeInsets.only(
                                              left: LicenseViewConstants
                                                      .licenseIndent *
                                                  paragraph.indent),
                                          child: ListTile(
                                            title: LinkText(paragraph.text),
                                          ),
                                        ),
                                      } else ...{
                                        ListTile(
                                          title: LinkText(paragraph.text),
                                        ),
                                      }
                                    }
                                  ]),
                                }
                              ],
                            );
                          });
                    });
              });
        });
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        // アプリのタイトルバー
        appBar: AppBar(
          // 前の画面に戻るボタン
          leading: SubDrawerConstants.backButton(context),
          // 背景色
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          // タイトル
          title: LicenseViewConstants.title,
        ),

        // 表示するウィジェット
        body: Column(
          children: [
            viewPackageInfo(), // アプリのバージョン情報等の表示

            // 可変長に対応させる為にFlexible設定(設定しないとオーバーフローする)
            Flexible(child: viewLicenseInfo()), // ライセンス情報のリスト表示
          ],
        ));
  }
}
