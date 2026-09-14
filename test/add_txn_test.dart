import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_wallet/main.dart' as app;

const _storeKey = 'ledger_data_v1';

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

void main() {
  testWidgets('记一笔：支出(分类+备注)和收入(昨天)都能保存并持久化', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    app.main();
    await tester.pumpAndSettle();

    // 切到明细页
    await tester.tap(find.text('明细'));
    await tester.pumpAndSettle();

    // ---- 记一笔支出：12.5 元，餐饮，备注「午饭」----
    await tester.tap(find.text('记一笔'));
    await tester.pumpAndSettle();
    expect(find.text('保存'), findsOneWidget, reason: '弹窗应打开');

    await tester.enterText(find.byType(TextField).first, '12.5');
    await tester.tap(find.widgetWithText(ChoiceChip, '餐饮'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '午饭');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    // 明细列表应出现这笔
    expect(find.text('午饭'), findsOneWidget);
    expect(find.text('-¥12.50'), findsOneWidget);
    expect(find.text('今天'), findsOneWidget);

    // ---- 记一笔收入：8000 元，日期选「昨天」----
    await tester.tap(find.text('记一笔'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('收入'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '8000');
    await tester.tap(find.widgetWithText(ChoiceChip, '昨天'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('+¥8,000.00'), findsOneWidget);

    // ---- 检查真正写进了本地存储 ----
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storeKey);
    expect(raw, isNotNull, reason: '应该已经写入 SharedPreferences');

    final map = jsonDecode(raw!) as Map<String, dynamic>;
    final txns = (map['txns'] as List).cast<Map<String, dynamic>>();
    expect(txns.length, 2);

    final expense = txns.firstWhere((t) => t['income'] != true);
    expect(expense['amount'], 12.5);
    expect(expense['category'], '餐饮');
    expect(expense['note'], '午饭');

    final income = txns.firstWhere((t) => t['income'] == true);
    expect(income['amount'], 8000);
    final now = DateTime.now();
    expect(income['date'], _ymd(DateTime(now.year, now.month, now.day - 1)), reason: '选「昨天」应存昨天的日期');
  });
}
