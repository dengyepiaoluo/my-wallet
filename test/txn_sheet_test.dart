import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_wallet/main.dart' as app;

void main() {
  testWidgets('明细页「记一笔」和空列表「记第一笔」都能弹出记账弹窗', (tester) async {
    // 测试环境里没有插件 handler，mock 掉 SharedPreferences
    SharedPreferences.setMockInitialValues(<String, Object>{});
    app.main();
    await tester.pumpAndSettle();

    // 切到「明细」tab
    await tester.tap(find.text('明细'));
    await tester.pumpAndSettle();

    // 点「记一笔」FAB：弹窗应出现
    //（修复前这里会抛
    //  "Navigator operation requested with a context that does not include a Navigator"）
    await tester.tap(find.text('记一笔'));
    await tester.pumpAndSettle();
    expect(find.text('保存'), findsOneWidget);
    expect(find.text('支出'), findsOneWidget);
    expect(find.text('收入'), findsOneWidget);

    // 点遮罩关掉弹窗
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('保存'), findsNothing);

    // 空列表时点「记第一笔」也应弹出弹窗
    await tester.tap(find.text('记第一笔'));
    await tester.pumpAndSettle();
    expect(find.text('保存'), findsOneWidget);
  });
}
