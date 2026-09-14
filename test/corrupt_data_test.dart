import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_wallet/main.dart' as app;

const _storeKey = 'ledger_data_v1';

void main() {
  testWidgets('存储里是坏数据时，App 应正常打开成空账本，而不是崩或卡在加载中', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{_storeKey: '{这不是合法 JSON'});
    app.main();
    await tester.pumpAndSettle();

    expect(find.byType(app.AppRoot), findsOneWidget);

    await tester.tap(find.text('明细'));
    await tester.pumpAndSettle();
    expect(find.text('还没有记录'), findsOneWidget);

    // 坏数据不应影响后续正常记账
    await tester.tap(find.text('记第一笔'));
    await tester.pumpAndSettle();
    expect(find.text('保存'), findsOneWidget);
  });
}
