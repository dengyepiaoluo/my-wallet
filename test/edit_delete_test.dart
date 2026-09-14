import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_wallet/main.dart' as app;

const _storeKey = 'ledger_data_v1';

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 预置一条已有记录，模拟“手机里已经记过账”的启动状态
String _seedJson() {
  final today = _ymd(DateTime.now());
  return jsonEncode(<String, dynamic>{
    'txns': [
      {'id': 't1', 'income': false, 'amount': 12.5, 'date': today, 'note': '午饭', 'category': '餐饮'},
    ],
    'budget': 0,
    'salaryDay': 1,
    'monthlySave': 0,
    'salaryChanges': <dynamic>[],
    'forecastMode': 0,
    'recurs': <dynamic>[],
    'themeIndex': 0,
  });
}

void main() {
  testWidgets('点已有记录可以编辑金额，也可以删除', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{_storeKey: _seedJson()});
    app.main();
    await tester.pumpAndSettle();

    await tester.tap(find.text('明细'));
    await tester.pumpAndSettle();

    // 启动时应读出已有记录
    expect(find.text('午饭'), findsOneWidget);
    expect(find.text('-¥12.50'), findsOneWidget);

    // ---- 编辑：改金额为 99.99 ----
    await tester.tap(find.text('午饭'));
    await tester.pumpAndSettle();
    expect(find.text('保存'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget, reason: '编辑已有记录才有删除按钮');

    await tester.enterText(find.byType(TextField).first, '99.99');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('-¥99.99'), findsOneWidget);
    expect(find.text('-¥12.50'), findsNothing);

    var map = jsonDecode((await SharedPreferences.getInstance()).getString(_storeKey)!) as Map<String, dynamic>;
    expect(((map['txns'] as List).single as Map<String, dynamic>)['amount'], 99.99);

    // ---- 删除 ----
    await tester.tap(find.text('午饭'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(find.text('午饭'), findsNothing);
    expect(find.text('还没有记录'), findsOneWidget, reason: '删完应回到空状态');

    map = jsonDecode((await SharedPreferences.getInstance()).getString(_storeKey)!) as Map<String, dynamic>;
    expect((map['txns'] as List), isEmpty);
  });
}
