import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_wallet/main.dart' as app;

const _storeKey = 'ledger_data_v1';

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _seedJson() => jsonEncode(<String, dynamic>{
      'txns': [
        {'id': 'p1', 'income': false, 'amount': 200, 'date': _ymd(DateTime.now()), 'note': '计划买书', 'category': '购物'},
      ],
      'budget': 0,
      'salaryDay': 1,
      'monthlySave': 0,
      'salaryChanges': <dynamic>[],
      'forecastMode': 0,
      'recurs': <dynamic>[],
      'themeIndex': 0,
    });

void main() {
  testWidgets('未来的「计划账」：明细标「计划」，不提前计入当月，翻到下月才显示', (tester) async {
    final nextMonth = DateTime(DateTime.now().year, DateTime.now().month + 1, 15);
    final data = jsonDecode(_seedJson()) as Map<String, dynamic>;
    (data['txns'] as List).first['date'] = _ymd(nextMonth);
    SharedPreferences.setMockInitialValues(<String, Object>{_storeKey: jsonEncode(data)});

    app.main();
    await tester.pumpAndSettle();

    // 明细页：应显示为「计划」
    await tester.tap(find.text('明细'));
    await tester.pumpAndSettle();
    expect(find.text('计划买书'), findsOneWidget);
    expect(find.textContaining('· 计划'), findsOneWidget, reason: '未来的账要标成计划');

    // 概览页：当前月不能提前把这笔算进去
    await tester.tap(find.text('概览'));
    await tester.pumpAndSettle();
    expect(find.text('¥0.00'), findsWidgets, reason: '本月收/支/结余都应是 0');
    expect(find.textContaining('已记的未来计划账'), findsOneWidget, reason: '预测里才应把这笔算作计划账');

    // 往后翻一个月：这笔才出现在支出里
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    expect(find.text('¥200.00'), findsOneWidget);
    expect(find.text('-¥200.00'), findsWidgets, reason: '下月结余与预测都应为 -200');
  });
}
