import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_wallet/main.dart' as app;

void main() {
  testWidgets('规划页：换主题、设月预算、设每月计划存、加调薪和定期账单，概览同步生效', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    // 用高一点的窗口，保证规划页所有卡片都渲染出来
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    app.main();
    await tester.pumpAndSettle();

    await tester.tap(find.text('规划'));
    await tester.pumpAndSettle();

    // ---- 主题切换 ----
    expect(app.curTheme.name, '薄荷绿');
    await tester.tap(find.text('夜樱'));
    await tester.pumpAndSettle();
    expect(app.curTheme.name, '夜樱', reason: '换主题应立即生效');
    expect(app.curTheme.dark, isTrue);

    // ---- 每月预算 3000 ----
    await tester.enterText(find.byType(TextField).at(0), '3000');
    await tester.tap(find.text('保存').first);
    await tester.pumpAndSettle();

    // ---- 每月计划存 2000 ----
    await tester.enterText(find.byType(TextField).at(1), '2000');
    await tester.tap(find.text('保存').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('目标 ¥2,000.00'), findsOneWidget, reason: '应显示存钱进度');

    // ---- 每月工资 8000（弹窗里保存）----
    await tester.tap(find.text('设置每月工资'));
    await tester.pumpAndSettle();
    final salaryDlg = find.byType(AlertDialog);
    expect(salaryDlg, findsOneWidget, reason: '设置工资弹窗应打开');
    await tester.enterText(find.descendant(of: salaryDlg, matching: find.byType(TextField)), '8000');
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: salaryDlg, matching: find.text('保存')));
    await tester.pumpAndSettle();
    expect(find.textContaining('当前每月 ¥8,000.00'), findsOneWidget);

    // ---- 定期账单：房租 2000 ----
    await tester.tap(find.text('添加定期账单'));
    await tester.pumpAndSettle();
    final recurDlg = find.byType(AlertDialog);
    expect(recurDlg, findsOneWidget, reason: '定期账单弹窗应打开');
    await tester.enterText(find.descendant(of: recurDlg, matching: find.byType(TextField)).first, '2000');
    await tester.pumpAndSettle();
    await tester.enterText(find.descendant(of: recurDlg, matching: find.byType(TextField)).last, '房租');
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: recurDlg, matching: find.text('保存')));
    await tester.pumpAndSettle();
    expect(find.textContaining('房租 · 每月 1 号'), findsOneWidget);

    // ---- 概览页应同步显示预算和预测 ----
    await tester.tap(find.text('概览'));
    await tester.pumpAndSettle();

    expect(find.text('预算 ¥3,000.00'), findsOneWidget, reason: '概览应显示月预算');
    expect(find.text('存钱预测'), findsOneWidget);
    // “按工资和支出”口径可用（设了工资 + 定期账单）
    await tester.tap(find.text('按工资和支出'));
    await tester.pumpAndSettle();
    expect(find.textContaining('工资 ¥8,000.00'), findsOneWidget);
    expect(find.textContaining('定期支出 ¥2,000.00'), findsOneWidget);
  });
}
