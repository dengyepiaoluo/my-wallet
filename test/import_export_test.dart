import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_wallet/main.dart' as app;

const _storeKey = 'ledger_data_v1';

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 等 SnackBar 自己消失，避免挡住底部导航栏影响后续点击
Future<void> _waitSnackBar(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('导出能生成备份 JSON，导入能替换数据，坏内容会报错且不破坏现有数据', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final today = _ymd(DateTime.now());
    SharedPreferences.setMockInitialValues(<String, Object>{
      _storeKey: jsonEncode(<String, dynamic>{
        'txns': [
          {'id': 't1', 'income': false, 'amount': 12.5, 'date': today, 'note': '午饭', 'category': '餐饮'},
        ],
        'budget': 1000,
        'salaryDay': 1,
        'monthlySave': 0,
        'salaryChanges': <dynamic>[],
        'forecastMode': 0,
        'recurs': <dynamic>[],
        'themeIndex': 0,
      }),
    });

    // 模拟系统剪贴板
    String? clip;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clip = (call.arguments as Map)['text'] as String?;
        return null;
      }
      if (call.method == 'Clipboard.getData') {
        return <String, dynamic>{'text': clip};
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    app.main();
    await tester.pumpAndSettle();
    await tester.tap(find.text('规划'));
    await tester.pumpAndSettle();

    // ---- 导出：应生成可解析的备份 ----
    await tester.ensureVisible(find.text('导出'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导出'));
    await tester.pumpAndSettle();
    expect(find.text('数据已复制'), findsOneWidget);
    expect(clip, isNotNull, reason: '备份内容应写进剪贴板');

    final exported = jsonDecode(clip!) as Map<String, dynamic>;
    expect((exported['txns'] as List).length, 1);
    expect(exported['budget'], 1000);
    expect(((exported['txns'] as List).single as Map<String, dynamic>)['note'], '午饭');

    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();

    // ---- 导入：应替换掉原有数据 ----
    final incoming = jsonEncode(<String, dynamic>{
      'txns': [
        {'id': 'n1', 'income': false, 'amount': 88, 'date': today, 'note': '导入的记录A', 'category': '购物'},
        {'id': 'n2', 'income': true, 'amount': 5000, 'date': today, 'note': '导入的记录B'},
      ],
      'budget': 2000,
      'salaryDay': 10,
      'monthlySave': 0,
      'salaryChanges': <dynamic>[],
      'forecastMode': 0,
      'recurs': <dynamic>[],
      'themeIndex': 0,
    });

    await tester.tap(find.text('导入'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)),
      incoming,
    );
    await tester.tap(find.text('导入并替换'));
    await tester.pumpAndSettle();
    expect(find.textContaining('导入成功，共 2 笔记录'), findsOneWidget);
    await _waitSnackBar(tester);

    await tester.tap(find.text('明细'));
    await tester.pumpAndSettle();
    expect(find.text('导入的记录A'), findsOneWidget);
    expect(find.text('导入的记录B'), findsOneWidget);
    expect(find.text('午饭'), findsNothing, reason: '导入应替换旧数据');

    // 导入的预算也要生效
    await tester.tap(find.text('概览'));
    await tester.pumpAndSettle();
    expect(find.text('预算 ¥2,000.00'), findsOneWidget);

    // ---- 导入坏内容：应提示失败，且不动已有数据 ----
    await tester.tap(find.text('规划'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导入'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)),
      '这不是 JSON',
    );
    await tester.tap(find.text('导入并替换'));
    await tester.pumpAndSettle();
    expect(find.textContaining('内容格式不对，导入失败'), findsOneWidget);
    await _waitSnackBar(tester);

    await tester.tap(find.text('明细'));
    await tester.pumpAndSettle();
    expect(find.text('导入的记录A'), findsOneWidget, reason: '导入失败不应破坏已有数据');

    // 清空所有数据也应该可用
    await tester.tap(find.text('规划'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('清空所有数据'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清空所有数据'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('明细'));
    await tester.pumpAndSettle();
    expect(find.text('还没有记录'), findsOneWidget);
    expect(find.text('导入的记录A'), findsNothing);
  });
}
