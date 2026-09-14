import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_wallet/main.dart' as app;

const _storeKey = 'ledger_data_v1';

/// v1.0.0 老版本真实写进手机的格式：
/// - Txn 没有 category 字段
/// - AppData 只有 txns / budget / salaryDay，没有 themeIndex 等新字段
String _legacyV100Json() => jsonEncode(<String, dynamic>{
      'txns': [
        {'id': 'old1', 'income': false, 'amount': 35.5, 'date': '2026-08-10', 'note': '买菜'},
        {'id': 'old2', 'income': true, 'amount': 9000, 'date': '2026-08-01', 'note': '八月工资'},
        // 老数据里收入也可能没备注
        {'id': 'old3', 'income': false, 'amount': 12.0, 'date': '2026-08-11', 'note': ''},
      ],
      'budget': 2500,
      'salaryDay': 15,
    });

void main() {
  testWidgets('老版本(v1.0.0)数据能正常读出：不丢记录、不崩、预算保留', (tester) async {
    // 概览页很长，用高窗口保证预算卡片也在视口内（真机上是滚动）
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues(<String, Object>{_storeKey: _legacyV100Json()});
    app.main();
    await tester.pumpAndSettle();

    // 启动后不应停在加载中
    expect(find.byType(app.AppRoot), findsOneWidget);

    await tester.tap(find.text('明细'));
    await tester.pumpAndSettle();

    // 老记录一条都不能少
    expect(find.text('买菜'), findsOneWidget);
    expect(find.text('-¥35.50'), findsOneWidget);
    expect(find.text('八月工资'), findsOneWidget);
    expect(find.text('+¥9,000.00'), findsOneWidget);
    // 没有备注的支出，老版本没分类 → 应回落到「其他」而不是崩
    expect(find.text('其他'), findsOneWidget);
    expect(find.text('-¥12.00'), findsOneWidget);

    // 点进老记录编辑不应报错，且金额预填正确
    await tester.tap(find.text('买菜'));
    await tester.pumpAndSettle();
    expect(find.text('删除'), findsOneWidget);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('买菜'), findsOneWidget);

    // 概览：老版本的月预算应保留并显示
    await tester.tap(find.text('概览'));
    await tester.pumpAndSettle();
    expect(find.text('预算 ¥2,500.00'), findsOneWidget);

    // 新字段应取默认值：主题仍是薄荷绿，预测不会因为缺字段而报错
    expect(app.curTheme.name, '薄荷绿');
    expect(find.text('存钱预测'), findsOneWidget);

    // 老记录被编辑保存后，新结构应写回存储
    final raw = (await SharedPreferences.getInstance()).getString(_storeKey)!;
    final map = jsonDecode(raw) as Map<String, dynamic>;
    expect((map['txns'] as List).length, 3, reason: '编辑不应复制或丢失记录');
    expect(map['budget'], 2500);
    expect(map.containsKey('themeIndex'), isTrue, reason: '保存后应是新结构');
  });
}
