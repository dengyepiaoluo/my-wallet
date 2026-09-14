import 'package:flutter_test/flutter_test.dart';

import 'package:my_wallet/main.dart';

/// 纯解析逻辑的边界测试（不涉及界面）
void main() {
  group('AppData.fromJson 容错', () {
    test('老格式（无 category、无新字段）能读出，新字段取默认值', () {
      final d = AppData.fromJson(<String, dynamic>{
        'txns': [
          {'id': 'a', 'income': false, 'amount': 35.5, 'date': '2026-08-10', 'note': '买菜'},
        ],
        'budget': 2500,
        'salaryDay': 15,
      })!;

      expect(d.txns.length, 1);
      expect(d.txns.single.category, '', reason: '老数据没有分类，应为空而不是 null');
      expect(d.budget, 2500);
      expect(d.salaryDay, 15);
      expect(d.monthlySave, 0);
      expect(d.forecastMode, 0);
      expect(d.themeIndex, 0);
      expect(d.salaryChanges, isEmpty);
      expect(d.recurs, isEmpty);
      // 空分类必须能安全映射到「其他」，否则记账列表渲染会崩
      expect(catOf('').name, '其他');
    });

    test('txns 不是数组 → 返回 null（调用方保持空数据，不崩）', () {
      expect(AppData.fromJson(<String, dynamic>{'txns': 'oops'}), isNull);
      expect(AppData.fromJson(<String, dynamic>{}), isNull);
    });

    test('单条记录金额或日期非法 → 只跳过坏的那条', () {
      final d = AppData.fromJson(<String, dynamic>{
        'txns': [
          {'id': 'ok', 'income': false, 'amount': 10, 'date': '2026-08-10', 'note': '好数据'},
          {'id': 'noAmount', 'income': false, 'date': '2026-08-10', 'note': '缺金额'},
          {'id': 'badAmount', 'income': false, 'amount': 'abc', 'date': '2026-08-10', 'note': '金额是文本'},
          {'id': 'badDate', 'income': false, 'amount': 20, 'date': '不是日期', 'note': '日期坏'},
          'not a map',
        ],
      })!;

      expect(d.txns.length, 1);
      expect(d.txns.single.note, '好数据');
    });

    test('数字以字符串存时也能解析；非法数值回落默认值', () {
      final d = AppData.fromJson(<String, dynamic>{
        'txns': <dynamic>[],
        'budget': '3000',
        'salaryDay': '5',
        'monthlySave': '1500.5',
        'forecastMode': '2',
      })!;
      expect(d.budget, 3000);
      expect(d.salaryDay, 5);
      expect(d.monthlySave, 1500.5);
      expect(d.forecastMode, 2);

      final bad = AppData.fromJson(<String, dynamic>{
        'txns': <dynamic>[],
        'budget': 'abc',
        'salaryDay': 'x',
        'forecastMode': '99',
        'themeIndex': '999',
      })!;
      expect(bad.budget, 0);
      expect(bad.salaryDay, 1);
      expect(bad.forecastMode, 2, reason: '越界口径应被夹到 2');
      expect(bad.themeIndex, lessThanOrEqualTo(99));
    });

    test('income 字段的多种写法都认', () {
      Map<String, dynamic> txn(Object? v) => {'id': 'x', 'income': v, 'amount': 1, 'date': '2026-08-10'};
      for (final v in <Object>[true, 1, 'true']) {
        expect(Txn.fromMap(txn(v))!.income, isTrue, reason: '$v 应视为收入');
      }
      for (final v in <Object?>[false, 0, 'false', null]) {
        expect(Txn.fromMap(txn(v))!.income, isFalse, reason: '$v 应视为支出');
      }
    });

    test('调薪记录按日期排序，金额非正的丢弃', () {
      final d = AppData.fromJson(<String, dynamic>{
        'txns': <dynamic>[],
        'salaryChanges': [
          {'id': 'c2', 'date': '2025-06-01', 'amount': 7000},
          {'id': 'c1', 'date': '2024-01-01', 'amount': 5000},
          {'id': 'bad', 'date': '2024-01-01', 'amount': 0},
          {'id': 'bad2', 'date': '2024-01-01', 'amount': -100},
        ],
      })!;
      expect(d.salaryChanges.map((c) => c.id), ['c1', 'c2']);
    });

    test('定期账单：号数越界或金额非正的丢弃', () {
      final d = AppData.fromJson(<String, dynamic>{
        'txns': <dynamic>[],
        'recurs': [
          {'id': 'ok', 'income': false, 'amount': 2000, 'day': 10, 'note': '房租'},
          {'id': 'day0', 'income': false, 'amount': 2000, 'day': 0, 'note': '坏'},
          {'id': 'day32', 'income': false, 'amount': 2000, 'day': 32, 'note': '坏'},
          {'id': 'zero', 'income': false, 'amount': 0, 'day': 5, 'note': '坏'},
        ],
      })!;
      expect(d.recurs.map((r) => r.id), ['ok']);
    });
  });

  group('金额与日期工具', () {
    test('fmtMoney 千分位与负数', () {
      expect(fmtMoney(0), '0.00');
      expect(fmtMoney(12.5), '12.50');
      expect(fmtMoney(1234.5), '1,234.50');
      expect(fmtMoney(1234567.891), '1,234,567.89');
      expect(fmtMoney(-200), '-200.00');
    });

    test('fmtYuan 的负号必须在 ¥ 前面（不能出现 ¥-200.00）', () {
      expect(fmtYuan(200), '¥200.00');
      expect(fmtYuan(0), '¥0.00');
      expect(fmtYuan(-200), '-¥200.00');
      expect(fmtYuan(-1234.5), '-¥1,234.50');
      expect(fmtYuan(-0.001), '¥0.00', reason: '四舍五入到分后为 0，不该显示负号');
    });

    test('ymd 补零', () {
      expect(ymd(DateTime(2026, 1, 5)), '2026-01-05');
    });

    test('daysInMonth 处理闰年与月末', () {
      expect(daysInMonth(DateTime(2024, 2, 1)), 29);
      expect(daysInMonth(DateTime(2025, 2, 1)), 28);
      expect(daysInMonth(DateTime(2026, 4, 1)), 30);
      expect(daysInMonth(DateTime(2026, 12, 1)), 31);
    });

    test('春节日期表抽查（农历换算不能错，否则倒计时全错）', () {
      expect(ymd(cnyOf(2024)), '2024-02-10');
      expect(ymd(cnyOf(2025)), '2025-01-29');
      expect(ymd(cnyOf(2026)), '2026-02-17');
      expect(ymd(cnyOf(2027)), '2027-02-06');
    });
  });

  group('统计与预测口径', () {
    test('salaryAt：按调薪生效日期取工资', () {
      final d = AppData(
        txns: [],
        budget: 0,
        salaryDay: 1,
        salaryChanges: [
          SalaryChange(id: 'c1', date: DateTime(2024, 1, 1), amount: 5000),
          SalaryChange(id: 'c2', date: DateTime(2025, 6, 1), amount: 7000),
        ],
      );
      expect(d.salaryAt(DateTime(2023, 12, 31)), 0, reason: '还没有工资记录');
      expect(d.salaryAt(DateTime(2024, 6, 1)), 5000);
      expect(d.salaryAt(DateTime(2025, 5, 31)), 5000, reason: '调薪前一天还是旧工资');
      expect(d.salaryAt(DateTime(2025, 6, 1)), 7000, reason: '生效当天按新工资');
    });

    test('balanceUpTo 只算当天及以前；plannedNetBetween 只算未来计划账', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final d = AppData(
        txns: [
          Txn(id: '1', income: true, amount: 100, date: today.subtract(const Duration(days: 3)), note: ''),
          Txn(id: '2', income: false, amount: 50, date: today, note: ''),
          Txn(id: '3', income: false, amount: 30, date: today.add(const Duration(days: 10)), note: '计划'),
        ],
        budget: 0,
        salaryDay: 1,
      );
      expect(d.balanceUpTo(today), 50, reason: '未来的计划账不能算进当前结余');
      expect(d.plannedNetBetween(today, today.add(const Duration(days: 60))), -30);
    });

    test('computeForecast：模式0 按每月计划存折算天数', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final d = AppData(txns: [], budget: 0, salaryDay: 1, monthlySave: 3000);
      final f = computeForecast(d, today.add(const Duration(days: 30)), 0);
      expect(f.base, 0);
      expect(f.planned, 0);
      expect(f.regular, closeTo(3000 * 30 / 30.4375, 0.01));
      expect(f.total, closeTo(f.regular, 0.01));
    });

    test('computeForecast：模式2 工资增加预测、定期支出减少预测', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final horizon = today.add(const Duration(days: 120));

      final withSalary = computeForecast(
        AppData(
          txns: [],
          budget: 0,
          salaryDay: 1,
          salaryChanges: [SalaryChange(id: 'c', date: today.subtract(const Duration(days: 400)), amount: 8000)],
        ),
        horizon,
        2,
      );
      expect(withSalary.regular, greaterThan(0), reason: '有工资应该能攒下钱');

      final withRent = computeForecast(
        AppData(
          txns: [],
          budget: 0,
          salaryDay: 1,
          salaryChanges: [SalaryChange(id: 'c', date: today.subtract(const Duration(days: 400)), amount: 8000)],
          recurs: [Recur(id: 'r', income: false, amount: 99999, day: 1, note: '天价房租')],
        ),
        horizon,
        2,
      );
      expect(withRent.regular, lessThan(0), reason: '固定支出远大于工资时预测应为负');
    });
  });
}
