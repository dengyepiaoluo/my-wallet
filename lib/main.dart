import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _storeKey = 'ledger_data_v1';

void main() {
  runApp(const AppRoot());
}

class Txn {
  String id;
  bool income;
  double amount;
  DateTime date;
  String note;
  String category;

  Txn({
    required this.id,
    required this.income,
    required this.amount,
    required this.date,
    required this.note,
    this.category = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'income': income,
      'amount': amount,
      'date': ymd(date),
      'note': note,
      'category': category,
    };
  }

  static Txn? fromMap(Map<String, dynamic> map) {
    final d = DateTime.tryParse(map['date']?.toString() ?? '');
    final a = double.tryParse(map['amount']?.toString() ?? '');
    if (d == null || a == null) return null;
    return Txn(
      id: map['id']?.toString() ?? DateTime.now().microsecondsSinceEpoch.toString(),
      income: map['income'] == true || map['income'] == 1 || map['income'] == 'true',
      amount: a,
      date: d,
      note: map['note']?.toString() ?? '',
      category: map['category']?.toString() ?? '',
    );
  }
}

/// 一次调薪（涨薪 / 降薪）记录：从 [date] 起每月工资变为 [amount]
class SalaryChange {
  String id;
  DateTime date;
  double amount;

  SalaryChange({required this.id, required this.date, required this.amount});

  Map<String, dynamic> toMap() => {'id': id, 'date': ymd(date), 'amount': amount};

  static SalaryChange? fromMap(Map<String, dynamic> map) {
    final d = DateTime.tryParse(map['date']?.toString() ?? '');
    final a = double.tryParse(map['amount']?.toString() ?? '');
    if (d == null || a == null || a <= 0) return null;
    return SalaryChange(
      id: map['id']?.toString() ?? DateTime.now().microsecondsSinceEpoch.toString(),
      date: d,
      amount: a,
    );
  }
}

/// 每月定期账（房租、订阅等固定收支），只用于预测，不会自动记入流水
class Recur {
  String id;
  bool income;
  double amount;
  int day; // 每月几号（超过当月天数按月底算）
  String note;

  Recur({required this.id, required this.income, required this.amount, required this.day, required this.note});

  Map<String, dynamic> toMap() => {'id': id, 'income': income, 'amount': amount, 'day': day, 'note': note};

  static Recur? fromMap(Map<String, dynamic> map) {
    final a = double.tryParse(map['amount']?.toString() ?? '');
    final d = int.tryParse(map['day']?.toString() ?? '');
    if (a == null || a <= 0 || d == null || d < 1 || d > 31) return null;
    return Recur(
      id: map['id']?.toString() ?? DateTime.now().microsecondsSinceEpoch.toString(),
      income: map['income'] == true || map['income'] == 1 || map['income'] == 'true',
      amount: a,
      day: d,
      note: map['note']?.toString() ?? '',
    );
  }
}

/// 最近几个月的平均收支
class MonthAvg {
  final double income;
  final double expense;

  const MonthAvg(this.income, this.expense);

  double get net => income - expense;
}

class AppData {
  List<Txn> txns;
  double budget;
  int salaryDay;
  double monthlySave;
  List<SalaryChange> salaryChanges;
  int forecastMode;
  List<Recur> recurs;
  int themeIndex;

  AppData({
    required this.txns,
    required this.budget,
    required this.salaryDay,
    this.monthlySave = 0,
    List<SalaryChange>? salaryChanges,
    this.forecastMode = 0,
    List<Recur>? recurs,
    this.themeIndex = 0,
  })  : salaryChanges = salaryChanges ?? [],
        recurs = recurs ?? [];

  factory AppData.empty() =>
      AppData(txns: [], budget: 0, salaryDay: 1, monthlySave: 0, salaryChanges: [], forecastMode: 0, recurs: [], themeIndex: 0);

  Map<String, dynamic> toJson() => {
        'txns': txns.map((t) => t.toMap()).toList(),
        'budget': budget,
        'salaryDay': salaryDay,
        'monthlySave': monthlySave,
        'salaryChanges': salaryChanges.map((c) => c.toMap()).toList(),
        'forecastMode': forecastMode,
        'recurs': recurs.map((r) => r.toMap()).toList(),
        'themeIndex': themeIndex,
      };

  static AppData? fromJson(Map<String, dynamic> map) {
    final raw = map['txns'];
    if (raw is! List) return null;
    final list = <Txn>[];
    for (final item in raw) {
      if (item is Map<String, dynamic>) {
        final t = Txn.fromMap(item);
        if (t != null) list.add(t);
      }
    }
    final changes = <SalaryChange>[];
    final rawChanges = map['salaryChanges'];
    if (rawChanges is List) {
      for (final item in rawChanges) {
        if (item is Map<String, dynamic>) {
          final c = SalaryChange.fromMap(item);
          if (c != null) changes.add(c);
        }
      }
    }
    changes.sort((a, b) => a.date.compareTo(b.date));
    final recurs = <Recur>[];
    final rawRecurs = map['recurs'];
    if (rawRecurs is List) {
      for (final item in rawRecurs) {
        if (item is Map<String, dynamic>) {
          final r = Recur.fromMap(item);
          if (r != null) recurs.add(r);
        }
      }
    }
    return AppData(
      txns: list,
      budget: double.tryParse(map['budget']?.toString() ?? '') ?? 0,
      salaryDay: int.tryParse(map['salaryDay']?.toString() ?? '') ?? 1,
      monthlySave: double.tryParse(map['monthlySave']?.toString() ?? '') ?? 0,
      salaryChanges: changes,
      forecastMode: (int.tryParse(map['forecastMode']?.toString() ?? '') ?? 0).clamp(0, 2),
      recurs: recurs,
      themeIndex: (int.tryParse(map['themeIndex']?.toString() ?? '') ?? 0).clamp(0, 99),
    );
  }

  /// 截至 d 那天有效的每月工资（0 表示未设置）
  double salaryAt(DateTime d) {
    double s = 0;
    for (final c in salaryChanges) {
      if (c.date.isAfter(d)) break;
      s = c.amount;
    }
    return s;
  }

  /// 截至 d 当天（含）的总结余
  double balanceUpTo(DateTime d) {
    final end = DateTime(d.year, d.month, d.day, 23, 59, 59, 999);
    double s = 0;
    for (final t in txns) {
      if (t.date.isAfter(end)) continue;
      s += t.income ? t.amount : -t.amount;
    }
    return s;
  }

  /// (from, to] 区间内已记录的净额（未来的计划账）
  double plannedNetBetween(DateTime from, DateTime to) {
    double s = 0;
    for (final t in txns) {
      if (!t.date.isAfter(from) || t.date.isAfter(to)) continue;
      s += t.income ? t.amount : -t.amount;
    }
    return s;
  }

  /// 最近 n 个完整自然月的平均收支（跳过整月没记录的月份）；都没有记录返回 null
  MonthAvg? recentMonthAvg([int n = 3]) {
    final now = DateTime.now();
    double inc = 0;
    double exp = 0;
    var months = 0;
    for (var i = 1; i <= n; i++) {
      final m = DateTime(now.year, now.month - i, 1);
      var has = false;
      for (final t in txns) {
        if (t.date.year != m.year || t.date.month != m.month) continue;
        has = true;
        if (t.income) {
          inc += t.amount;
        } else {
          exp += t.amount;
        }
      }
      if (has) months++;
    }
    if (months == 0) return null;
    return MonthAvg(inc / months, exp / months);
  }
}

String ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String fmtMoney(double v) {
  final neg = v < 0;
  final abs = v.abs();
  final yuan = abs.floor();
  final cents = ((abs - yuan) * 100).round();
  final yuanStr = yuan.toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+$)'),
        (m) => '${m[1]},',
      );
  final centsStr = cents.toString().padLeft(2, '0');
  return '${neg ? '-' : ''}$yuanStr.$centsStr';
}

String fmtYuan(double v) {
  // 负号要放在 ¥ 前面：-¥12.50，而不是 ¥-12.50
  final s = fmtMoney(v);
  if (!s.startsWith('-')) return '¥$s';
  final rest = s.substring(1);
  return rest == '0.00' ? '¥0.00' : '-¥$rest';
}

String dateLabel(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  if (day == today) return '今天';
  if (day.isAfter(today)) return '${d.month}/${d.day} · 计划';
  return '${d.month}/${d.day}';
}

int daysInMonth(DateTime d) {
  final first = DateTime(d.year, d.month, 1);
  final next = DateTime(d.year, d.month + 1, 1);
  return next.difference(first).inDays;
}

/// 2000–2099 年农历春节（正月初一）对应的公历日期，值为 月*100+日。
/// 与香港天文台公历农历对照表核对过；超出范围的年份按 1 月 1 日兜底。
const Map<int, int> _cnyTable = {
  2000: 205, 2001: 124, 2002: 212, 2003: 201, 2004: 122, 2005: 209,
  2006: 129, 2007: 218, 2008: 207, 2009: 126, 2010: 214,
  2011: 203, 2012: 123, 2013: 210, 2014: 131, 2015: 219,
  2016: 208, 2017: 128, 2018: 216, 2019: 205, 2020: 125,
  2021: 212, 2022: 201, 2023: 122, 2024: 210, 2025: 129,
  2026: 217, 2027: 206, 2028: 126, 2029: 213, 2030: 203,
  2031: 123, 2032: 211, 2033: 131, 2034: 219, 2035: 208,
  2036: 128, 2037: 215, 2038: 204, 2039: 124, 2040: 212,
  2041: 201, 2042: 122, 2043: 210, 2044: 130, 2045: 217,
  2046: 206, 2047: 126, 2048: 214, 2049: 202, 2050: 123,
  2051: 211, 2052: 201, 2053: 219, 2054: 208, 2055: 128,
  2056: 215, 2057: 204, 2058: 124, 2059: 212, 2060: 202,
  2061: 121, 2062: 209, 2063: 129, 2064: 217, 2065: 205,
  2066: 126, 2067: 214, 2068: 203, 2069: 123, 2070: 211,
  2071: 131, 2072: 219, 2073: 207, 2074: 127, 2075: 215,
  2076: 205, 2077: 124, 2078: 212, 2079: 202, 2080: 122,
  2081: 209, 2082: 129, 2083: 217, 2084: 206, 2085: 126,
  2086: 214, 2087: 203, 2088: 124, 2089: 210, 2090: 130,
  2091: 218, 2092: 207, 2093: 127, 2094: 215, 2095: 205,
  2096: 125, 2097: 212, 2098: 201, 2099: 121,
};

/// 某个公历年春节（正月初一）的公历日期
DateTime cnyOf(int year) {
  final v = _cnyTable[year];
  if (v != null) return DateTime(year, v ~/ 100, v % 100);
  return DateTime(year, 1, 1);
}

/// 存钱预测结果：现在有 + 未来计划账 + 常规月净流
class ForecastResult {
  final double base;
  final double planned;
  final double regular;

  const ForecastResult(this.base, this.planned, this.regular);

  double get total => base + planned + regular;
}

/// 预测到 [horizon] 当天能攒下多少钱
/// mode: 0 = 按每月计划存，1 = 按近 3 个月实际水平，2 = 按工资 − 预算 − 定期账
ForecastResult computeForecast(AppData data, DateTime horizon, int mode) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
  final horizonEnd = DateTime(horizon.year, horizon.month, horizon.day, 23, 59, 59, 999);

  final base = data.balanceUpTo(today);
  final planned = data.plannedNetBetween(today, horizonEnd);

  var regular = 0.0;
  if (mode == 0) {
    regular = data.monthlySave * (horizon.difference(today).inDays / 30.4375);
  } else if (mode == 1) {
    regular = (data.recentMonthAvg()?.net ?? 0) * (horizon.difference(today).inDays / 30.4375);
  } else {
    // 逐月推算：工资（按调薪记录）− 日常预算（按天折算）− 定期支出 + 定期收入
    var m = DateTime(today.year, today.month, 1);
    while (!m.isAfter(horizon)) {
      final dim = daysInMonth(m);
      final isStart = m.year == today.year && m.month == today.month;
      final isEnd = m.year == horizon.year && m.month == horizon.month;
      var coverDays = dim;
      if (isStart && isEnd) {
        coverDays = horizon.day - today.day;
      } else if (isStart) {
        coverDays = dim - today.day;
      } else if (isEnd) {
        coverDays = horizon.day;
      }
      if (coverDays > 0 && data.budget > 0) {
        regular -= data.budget * coverDays / dim;
      }
      for (final r in data.recurs) {
        final d = DateTime(m.year, m.month, r.day.clamp(1, dim));
        if (d.isAfter(endOfToday) && !d.isAfter(horizonEnd)) {
          regular += r.income ? r.amount : -r.amount;
        }
      }
      final payday = DateTime(m.year, m.month, data.salaryDay.clamp(1, dim));
      if (payday.isAfter(endOfToday) && !payday.isAfter(horizonEnd)) {
        regular += data.salaryAt(payday);
      }
      m = DateTime(m.year, m.month + 1, 1);
    }
  }
  return ForecastResult(base, planned, regular);
}

class CatDef {
  final String name;
  final IconData icon;
  final Color color;

  const CatDef(this.name, this.icon, this.color);
}

/// 支出分类
const List<CatDef> expenseCats = [
  CatDef('餐饮', Icons.restaurant, Color(0xFFD97742)),
  CatDef('交通', Icons.directions_transit, Color(0xFF3B82C4)),
  CatDef('购物', Icons.shopping_bag, Color(0xFF9C6BC7)),
  CatDef('居住', Icons.home, Color(0xFF8A813B)),
  CatDef('娱乐', Icons.celebration, Color(0xFF5B8DEF)),
  CatDef('医疗', Icons.medical_services, Color(0xFFD9534F)),
  CatDef('学习', Icons.school, Color(0xFF2E9E8F)),
  CatDef('人情', Icons.card_giftcard, Color(0xFFC2586E)),
  CatDef('其他', Icons.more_horiz, Color(0xFF7A8B8F)),
];

CatDef catOf(String name) {
  for (final c in expenseCats) {
    if (c.name == name) return c;
  }
  return expenseCats.last;
}

/// 主题定义
class ThemeDef {
  final String name;
  final bool dark;
  final Color primary; // 主色（收入 / 积极）
  final Color gradientEnd; // 大卡片渐变尾色
  final Color bg;
  final Color card;
  final Color softBg;
  final Color incomeBg;
  final Color trackBg;
  final Color text;
  final Color subtle;

  const ThemeDef({
    required this.name,
    required this.dark,
    required this.primary,
    required this.gradientEnd,
    required this.bg,
    required this.card,
    required this.softBg,
    required this.incomeBg,
    required this.trackBg,
    required this.text,
    required this.subtle,
  });
}

const List<ThemeDef> themeDefs = [
  ThemeDef(
    name: '薄荷绿',
    dark: false,
    primary: Color(0xFF1B8A5A),
    gradientEnd: Color(0xFF146B47),
    bg: Color(0xFFF4F6F5),
    card: Colors.white,
    softBg: Color(0xFFF1F5F3),
    incomeBg: Color(0xFFE3F2EC),
    trackBg: Color(0xFFE8EBEA),
    text: Colors.black87,
    subtle: Color(0xFF6B7370),
  ),
  ThemeDef(
    name: '樱花季',
    dark: false,
    primary: Color(0xFFD8679A),
    gradientEnd: Color(0xFFB84E7C),
    bg: Color(0xFFFDF4F7),
    card: Colors.white,
    softBg: Color(0xFFFBEFF4),
    incomeBg: Color(0xFFFBE3EC),
    trackBg: Color(0xFFF3E5EB),
    text: Colors.black87,
    subtle: Color(0xFF8A6E7A),
  ),
  ThemeDef(
    name: '夏日海空',
    dark: false,
    primary: Color(0xFF2E86C1),
    gradientEnd: Color(0xFF1B6FA8),
    bg: Color(0xFFF2F7FB),
    card: Colors.white,
    softBg: Color(0xFFEDF4F9),
    incomeBg: Color(0xFFDFEEF8),
    trackBg: Color(0xFFE3ECF2),
    text: Colors.black87,
    subtle: Color(0xFF5F7382),
  ),
  ThemeDef(
    name: '紫藤苑',
    dark: false,
    primary: Color(0xFF7C5CBF),
    gradientEnd: Color(0xFF61439C),
    bg: Color(0xFFF7F5FC),
    card: Colors.white,
    softBg: Color(0xFFF2EFFA),
    incomeBg: Color(0xFFEBE5F8),
    trackBg: Color(0xFFECE9F3),
    text: Colors.black87,
    subtle: Color(0xFF6E6782),
  ),
  ThemeDef(
    name: '落日黄昏',
    dark: false,
    primary: Color(0xFFE07B54),
    gradientEnd: Color(0xFFB05AA8),
    bg: Color(0xFFFBF5F1),
    card: Colors.white,
    softBg: Color(0xFFF9F0EA),
    incomeBg: Color(0xFFFAE5D9),
    trackBg: Color(0xFFF2E8E1),
    text: Colors.black87,
    subtle: Color(0xFF82706A),
  ),
  ThemeDef(
    name: '星夜紫',
    dark: true,
    primary: Color(0xFF9B8CFF),
    gradientEnd: Color(0xFF5D4FC4),
    bg: Color(0xFF131629),
    card: Color(0xFF1D2140),
    softBg: Color(0xFF242A4E),
    incomeBg: Color(0xFF2B2F58),
    trackBg: Color(0xFF2C3156),
    text: Colors.white,
    subtle: Color(0xFFA6ACCB),
  ),
  ThemeDef(
    name: '翡翠夜',
    dark: true,
    primary: Color(0xFF3FD694),
    gradientEnd: Color(0xFF15803D),
    bg: Color(0xFF0F1714),
    card: Color(0xFF17241F),
    softBg: Color(0xFF1D2E27),
    incomeBg: Color(0xFF1F332B),
    trackBg: Color(0xFF24352D),
    text: Colors.white,
    subtle: Color(0xFF9FB5AA),
  ),
  ThemeDef(
    name: '夜樱',
    dark: true,
    primary: Color(0xFFF48FB1),
    gradientEnd: Color(0xFF8E4A6E),
    bg: Color(0xFF1A141C),
    card: Color(0xFF251C27),
    softBg: Color(0xFF2D2230),
    incomeBg: Color(0xFF352638),
    trackBg: Color(0xFF332836),
    text: Colors.white,
    subtle: Color(0xFFC1A9B6),
  ),
];

/// 当前主题（AppRoot 构建时更新）
ThemeDef curTheme = themeDefs.first;

class _AmountInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;
    final dotIndex = text.indexOf('.');
    if (text.indexOf('.') != text.lastIndexOf('.')) return oldValue;
    if (dotIndex >= 0 && text.length - dotIndex - 1 > 2) return oldValue;
    final ok = RegExp(r'^\d{0,9}(\.\d{0,2})?$').hasMatch(text);
    if (!ok) return oldValue;
    return newValue;
  }
}

class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  // home Scaffold 的 key：_openSheet 需要用 MaterialApp 之内的 context
  //（Navigator / ScaffoldMessenger 都在 MaterialApp 内部创建，State 自己的
  //  context 在 MaterialApp 之上，用它打开弹窗会直接抛异常）
  final GlobalKey<ScaffoldState> _homeKey = GlobalKey<ScaffoldState>();

  AppData data = AppData.empty();
  bool loaded = false;
  int tab = 0;
  DateTime cursor = DateTime(DateTime.now().year, DateTime.now().month, 1);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storeKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          final parsed = AppData.fromJson(decoded);
          if (parsed != null) data = parsed;
        }
      }
    } catch (_) {}
    if (mounted) {
      setState(() => loaded = true);
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storeKey, jsonEncode(data.toJson()));
    } catch (_) {}
  }

  void _mutate(VoidCallback fn) {
    setState(fn);
    _save();
  }

  void _gotoPlan() => setState(() => tab = 2);

  void _addOrUpdate(Txn t) {
    _mutate(() {
      final idx = data.txns.indexWhere((x) => x.id == t.id);
      if (idx >= 0) {
        data.txns[idx] = t;
      } else {
        data.txns.add(t);
      }
      data.txns.sort((a, b) => b.date.compareTo(a.date));
      cursor = DateTime(t.date.year, t.date.month, 1);
    });
  }

  void _delete(String id) {
    _mutate(() => data.txns.removeWhere((x) => x.id == id));
  }

  void _setBudget(double v) => _mutate(() => data.budget = v);

  void _setSalaryDay(int v) => _mutate(() => data.salaryDay = v);

  void _setMonthlySave(double v) => _mutate(() => data.monthlySave = v);

  void _addSalaryChange(SalaryChange c) {
    _mutate(() {
      data.salaryChanges.add(c);
      data.salaryChanges.sort((a, b) => a.date.compareTo(b.date));
    });
  }

  void _deleteSalaryChange(String id) => _mutate(() => data.salaryChanges.removeWhere((x) => x.id == id));

  void _setForecastMode(int v) => _mutate(() => data.forecastMode = v);

  void _addRecur(Recur r) => _mutate(() => data.recurs.add(r));

  void _deleteRecur(String id) => _mutate(() => data.recurs.removeWhere((x) => x.id == id));

  void _setTheme(int v) => _mutate(() => data.themeIndex = v.clamp(0, themeDefs.length - 1));

  void _replaceData(AppData incoming) {
    _mutate(() {
      data.txns = incoming.txns..sort((a, b) => b.date.compareTo(a.date));
      data.budget = incoming.budget;
      data.salaryDay = incoming.salaryDay;
    });
  }

  void _clearAll() {
    _mutate(() => data = AppData.empty());
  }

  void _openSheet({Txn? initial}) {
    final homeCtx = _homeKey.currentContext;
    if (homeCtx == null) return; // Scaffold 还没挂载（理论上点不到）
    showModalBottomSheet<void>(
      context: homeCtx,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _TxnSheet(
        initial: initial,
        onSave: (t) {
          _addOrUpdate(t);
          ScaffoldMessenger.of(homeCtx).showSnackBar(
            SnackBar(content: Text(initial == null ? '已记一笔' : '已保存修改'), duration: const Duration(milliseconds: 900)),
          );
        },
        onDelete: initial == null
            ? null
            : (id) {
                _delete(id);
                ScaffoldMessenger.of(homeCtx).showSnackBar(
                  const SnackBar(content: Text('已删除'), duration: Duration(milliseconds: 900)),
                );
              },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    curTheme = themeDefs[data.themeIndex.clamp(0, themeDefs.length - 1)];
    final pages = [
      OverviewPage(
        data: data,
        cursor: cursor,
        onCursor: (d) => setState(() => cursor = d),
        onAdd: () => _openSheet(),
        onGotoPlan: _gotoPlan,
        onSetForecastMode: _setForecastMode,
      ),
      TxnsPage(data: data, onTap: (t) => _openSheet(initial: t), onAdd: () => _openSheet()),
      PlanPage(
        data: data,
        onSetBudget: _setBudget,
        onSetSalaryDay: _setSalaryDay,
        onSetMonthlySave: _setMonthlySave,
        onAddSalary: _addSalaryChange,
        onDeleteSalary: _deleteSalaryChange,
        onAddRecur: _addRecur,
        onDeleteRecur: _deleteRecur,
        onSetTheme: _setTheme,
        onImport: _replaceData,
        onClearAll: _clearAll,
      ),
    ];
    return MaterialApp(
      title: '我的小账本',
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [
        Locale('zh', 'CN'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: curTheme.primary,
          brightness: curTheme.dark ? Brightness.dark : Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: curTheme.bg,
        cardColor: curTheme.card,
        fontFamily: null,
      ),
      home: Scaffold(
        key: _homeKey,
        body: loaded
            ? SafeArea(child: pages[tab])
            : const Center(child: CircularProgressIndicator()),
        floatingActionButton: (loaded && tab == 1)
            ? FloatingActionButton.extended(
                onPressed: _openSheet,
                icon: const Icon(Icons.add),
                label: const Text('记一笔'),
              )
            : null,
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (i) => setState(() => tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: '概览'),
            NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: '明细'),
            NavigationDestination(icon: Icon(Icons.tune_outlined), selectedIcon: Icon(Icons.tune), label: '规划'),
          ],
        ),
      ),
    );
  }
}

class _MonthBar extends StatelessWidget {
  final DateTime cursor;
  final ValueChanged<DateTime> onCursor;

  const _MonthBar({required this.cursor, required this.onCursor});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isCurrent = cursor.year == now.year && cursor.month == now.month;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed: () => onCursor(DateTime(cursor.year, cursor.month - 1, 1)),
          icon: const Icon(Icons.chevron_left),
        ),
        InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => onCursor(DateTime(now.year, now.month, 1)),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: curTheme.card,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${cursor.year}年${cursor.month}月${isCurrent ? '' : ' · 回本月'}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        IconButton(
          onPressed: () => onCursor(DateTime(cursor.year, cursor.month + 1, 1)),
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}

class OverviewPage extends StatelessWidget {
  final AppData data;
  final DateTime cursor;
  final ValueChanged<DateTime> onCursor;
  final VoidCallback onAdd;
  final VoidCallback onGotoPlan;
  final ValueChanged<int> onSetForecastMode;

  const OverviewPage({
    super.key,
    required this.data,
    required this.cursor,
    required this.onCursor,
    required this.onAdd,
    required this.onGotoPlan,
    required this.onSetForecastMode,
  });

  @override
  Widget build(BuildContext context) {
    final monthTxns = data.txns.where((t) => t.date.year == cursor.year && t.date.month == cursor.month).toList();
    final income = monthTxns.where((t) => t.income).fold<double>(0, (s, t) => s + t.amount);
    final expense = monthTxns.where((t) => !t.income).fold<double>(0, (s, t) => s + t.amount);
    final balance = income - expense;

    final now = DateTime.now();

    // 当年农历春节（正月初一）之前的累计结余
    final cny = cnyOf(now.year);
    final beforeCny = data.txns.where((t) => t.date.isBefore(cny)).toList();
    final cnyIncome = beforeCny.where((t) => t.income).fold<double>(0, (s, t) => s + t.amount);
    final cnyExpense = beforeCny.where((t) => !t.income).fold<double>(0, (s, t) => s + t.amount);
    final cnyBalance = cnyIncome - cnyExpense;

    final isCurrentMonth = cursor.year == now.year && cursor.month == now.month;
    final budget = data.budget;
    final budgetLeft = budget - expense;
    final ratio = budget > 0 ? expense / budget : 0.0;

    int daysLeftInclToday = 0;
    if (isCurrentMonth) {
      daysLeftInclToday = daysInMonth(now) - now.day + 1;
    }
    final dailyAllowance = daysLeftInclToday > 0 && budgetLeft > 0 ? budgetLeft / daysLeftInclToday : budgetLeft > 0 ? budgetLeft : 0.0;

    // ===== 存钱预测 =====
    final today0 = DateTime(now.year, now.month, now.day);
    final thisCny = cnyOf(now.year);
    final nextCny = today0.isBefore(thisCny) ? thisCny : cnyOf(now.year + 1);
    final daysToCny = nextCny.difference(today0).inDays;
    final oneYearLater = DateTime(now.year + 1, now.month, now.day);
    final avg = data.recentMonthAvg();
    final recurExp = data.recurs.where((r) => !r.income).fold<double>(0, (s, r) => s + r.amount);
    final recurInc = data.recurs.where((r) => r.income).fold<double>(0, (s, r) => s + r.amount);
    final curSalary = data.salaryAt(now);
    final modeAvail = <bool>[
      data.monthlySave > 0,
      avg != null,
      curSalary > 0 || data.recurs.isNotEmpty,
    ];
    final effMode = modeAvail[data.forecastMode.clamp(0, 2)]
        ? data.forecastMode
        : modeAvail[0]
            ? 0
            : modeAvail[1]
                ? 1
                : 2;
    final fcny = computeForecast(data, nextCny, effMode);
    final fyear = computeForecast(data, oneYearLater, effMode);

    String modeHint(int m) {
      if (m == 0) {
        return modeAvail[0] ? '按“每月计划存 ${fmtYuan(data.monthlySave)}”估算，已记的未来计划账另算' : '还没设“每月计划存”，去规划页设置后可用';
      }
      if (m == 1) {
        return avg != null ? '按近 3 个月实际水平（平均每月存 ${fmtYuan(avg.net)}）估算，已记的未来计划账另算' : '近 3 个月还没有记录，先记几笔账';
      }
      if (curSalary <= 0 && data.recurs.isEmpty) return '先在规划页设置每月工资或添加定期账单';
      final parts = <String>[
        if (curSalary > 0) '工资 ${fmtYuan(curSalary)}',
        if (data.budget > 0) '日常预算 ${fmtYuan(data.budget)}',
        if (recurExp > 0) '定期支出 ${fmtYuan(recurExp)}',
        if (recurInc > 0) '定期收入 ${fmtYuan(recurInc)}',
      ];
      return '按每月 ${parts.join('、')} 逐月推算，未来的涨薪降薪会自动反映';
    }

    // ===== 本月支出构成 =====
    final catTotals = <String, double>{};
    for (final t in monthTxns) {
      if (t.income) continue;
      final key = t.category.isEmpty ? '其他' : t.category;
      catTotals[key] = (catTotals[key] ?? 0) + t.amount;
    }
    final catEntries = catTotals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final monthExpenseCount = monthTxns.where((t) => !t.income).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _MonthBar(cursor: cursor, onCursor: onCursor),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [curTheme.primary, curTheme.gradientEnd],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('本月结余', style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 14)),
              const SizedBox(height: 4),
              Text(
                fmtYuan(balance),
                style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.bold, height: 1.1),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('本月收入', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12)),
                        Text(fmtYuan(income), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('本月支出', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12)),
                        Text(fmtYuan(expense), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.insights_outlined, color: curTheme.primary, size: 20),
                const SizedBox(width: 8),
                const Text('存钱预测', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 4),
              Text('距 ${nextCny.year}/${nextCny.month}/${nextCny.day} 春节还有 $daysToCny 天',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('到过年预计', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                        Text(
                          fmtYuan(fcny.total),
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: fcny.total >= 0 ? curTheme.primary : Colors.red,
                          ),
                        ),
                        Text('过年能带回家的钱', style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('一年后预计', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                        Text(
                          fmtYuan(fyear.total),
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: fyear.total >= 0 ? curTheme.primary : Colors.red,
                          ),
                        ),
                        Text('到 ${oneYearLater.year}/${oneYearLater.month}', style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: curTheme.softBg, borderRadius: BorderRadius.circular(10)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('现在有 ${fmtYuan(fcny.base)}${fcny.planned.abs() > 0.005 ? ' · 已记的未来计划账 ${fmtYuan(fcny.planned)}' : ''}',
                        style: TextStyle(fontSize: 12, color: curTheme.subtle)),
                    if (avg != null)
                      Text('近 3 个月平均每月：收 ${fmtYuan(avg.income)} · 支 ${fmtYuan(avg.expense)} · 存 ${fmtYuan(avg.net)}',
                          style: TextStyle(fontSize: 12, color: curTheme.subtle)),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  for (var m = 0; m < 3; m++)
                    ChoiceChip(
                      label: Text(['按计划存', '按近3月实际', '按工资和支出'][m]),
                      selected: effMode == m,
                      onSelected: modeAvail[m] ? (_) => onSetForecastMode(m) : null,
                      labelStyle: const TextStyle(fontSize: 12),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(modeHint(effMode), style: TextStyle(fontSize: 11, color: Colors.grey.shade500, height: 1.4)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (budget > 0)
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('本月预算', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    Text('预算 ${fmtYuan(budget)}', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: ratio >= 1 ? 1 : ratio,
                    minHeight: 10,
                    backgroundColor: curTheme.trackBg,
                    color: ratio >= 1 ? Colors.red : ratio >= 0.8 ? Colors.orange : curTheme.primary,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('已花', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                          Text(fmtYuan(expense), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('还剩', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                          Text(
                            fmtYuan(budgetLeft),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: budgetLeft < 0 ? Colors.red : curTheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isCurrentMonth && budgetLeft > 0)
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('每天还能花', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                            Text(fmtYuan(dailyAllowance), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: curTheme.primary)),
                          ],
                        ),
                      ),
                  ],
                ),
                if (budgetLeft < 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('本月已超支 ${fmtYuan(budgetLeft.abs())}', style: const TextStyle(color: Colors.red, fontSize: 13)),
                  ),
              ],
            ),
          )
        else
          _Card(
            child: Row(
              children: [
                Icon(Icons.flag_outlined, color: curTheme.primary),
                const SizedBox(width: 12),
                const Expanded(child: Text('设置每月预算，帮你规划每天能花多少钱')),
                TextButton(onPressed: onGotoPlan, child: const Text('去设置')),
              ],
            ),
          ),
        if (expense > 0) ...[
          const SizedBox(height: 12),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${cursor.month}月支出构成', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('共 ${fmtYuan(expense)} · $monthExpenseCount 笔支出', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                for (final e in catEntries)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(catOf(e.key).icon, size: 15, color: catOf(e.key).color),
                            const SizedBox(width: 6),
                            Text(e.key, style: const TextStyle(fontSize: 13)),
                            const Spacer(),
                            Text('${fmtYuan(e.value)} · ${(e.value / expense * 100).toStringAsFixed(0)}%',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: e.value / expense,
                            minHeight: 4,
                            backgroundColor: curTheme.trackBg,
                            color: catOf(e.key).color,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        _Card(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('今年过年前累计结余', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                    Text(
                      fmtYuan(cnyBalance),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: cnyBalance >= 0 ? curTheme.primary : Colors.red,
                      ),
                    ),
                    Text(
                      beforeCny.isEmpty
                          ? '${cny.month}/${cny.day} 春节前还没有记录'
                          : '截至 ${cny.year}/${cny.month}/${cny.day} 春节前 · 收 ${fmtYuan(cnyIncome)} － 支 ${fmtYuan(cnyExpense)}',
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                    ),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: onAdd,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('记一笔'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;

  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: curTheme.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  final ThemeDef def;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeSwatch({required this.def, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [def.primary, def.gradientEnd], begin: Alignment.topLeft, end: Alignment.bottomRight),
              shape: BoxShape.circle,
              border: selected ? Border.all(color: def.dark ? Colors.white70 : def.primary, width: 2.5) : null,
              boxShadow: [BoxShadow(color: def.primary.withOpacity(selected ? 0.45 : 0.15), blurRadius: selected ? 8 : 3, spreadRadius: 1)],
            ),
            child: selected ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
          ),
          const SizedBox(height: 4),
          Text(def.name, style: TextStyle(fontSize: 11, color: selected ? curTheme.primary : curTheme.subtle)),
        ],
      ),
    );
  }
}

class TxnsPage extends StatelessWidget {
  final AppData data;
  final ValueChanged<Txn> onTap;
  final VoidCallback onAdd;

  const TxnsPage({super.key, required this.data, required this.onTap, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    if (data.txns.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_outlined, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text('还没有记录', style: TextStyle(color: Colors.grey.shade500)),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('记第一笔')),
          ],
        ),
      );
    }
    final sorted = [...data.txns]..sort((a, b) => b.date.compareTo(a.date));
    final groups = <String, List<Txn>>{};
    for (final t in sorted) {
      final key = '${t.date.year}-${t.date.month.toString().padLeft(2, '0')}';
      groups.putIfAbsent(key, () => []).add(t);
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      itemCount: groups.length,
      itemBuilder: (context, i) {
        final key = groups.keys.elementAt(i);
        final list = groups[key]!;
        final income = list.where((t) => t.income).fold<double>(0, (s, t) => s + t.amount);
        final expense = list.where((t) => !t.income).fold<double>(0, (s, t) => s + t.amount);
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 6, left: 4),
              child: Row(
                children: [
                  Text(key, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(width: 10),
                  Text('收 ${fmtMoney(income)} · 支 ${fmtMoney(expense)}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                ],
              ),
            ),
            ...list.map(
              (t) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: curTheme.card,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: ListTile(
                  onTap: () => onTap(t),
                  leading: CircleAvatar(
                    backgroundColor: t.income ? curTheme.incomeBg : catOf(t.category).color.withOpacity(0.12),
                    child: t.income
                        ? Icon(Icons.south_west, color: curTheme.primary, size: 20)
                        : Icon(catOf(t.category).icon, color: catOf(t.category).color, size: 20),
                  ),
                  title: Text(
                    t.note.isEmpty ? (t.income ? '收入' : catOf(t.category).name) : t.note,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15),
                  ),
                  subtitle: Text(dateLabel(t.date),
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                  trailing: Text(
                    '${t.income ? '+' : '-'}${fmtYuan(t.amount.abs())}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: t.income ? curTheme.primary : curTheme.text,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class PlanPage extends StatefulWidget {
  final AppData data;
  final ValueChanged<double> onSetBudget;
  final ValueChanged<int> onSetSalaryDay;
  final ValueChanged<double> onSetMonthlySave;
  final ValueChanged<SalaryChange> onAddSalary;
  final ValueChanged<String> onDeleteSalary;
  final ValueChanged<Recur> onAddRecur;
  final ValueChanged<String> onDeleteRecur;
  final ValueChanged<int> onSetTheme;
  final ValueChanged<AppData> onImport;
  final VoidCallback onClearAll;

  const PlanPage({
    super.key,
    required this.data,
    required this.onSetBudget,
    required this.onSetSalaryDay,
    required this.onSetMonthlySave,
    required this.onAddSalary,
    required this.onDeleteSalary,
    required this.onAddRecur,
    required this.onDeleteRecur,
    required this.onSetTheme,
    required this.onImport,
    required this.onClearAll,
  });

  @override
  State<PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends State<PlanPage> {
  late final TextEditingController budgetCtrl;
  late final TextEditingController saveCtrl;

  @override
  void initState() {
    super.initState();
    budgetCtrl = TextEditingController(text: widget.data.budget > 0 ? widget.data.budget.toStringAsFixed(2) : '');
    saveCtrl = TextEditingController(text: widget.data.monthlySave > 0 ? widget.data.monthlySave.toStringAsFixed(2) : '');
  }

  @override
  void dispose() {
    budgetCtrl.dispose();
    saveCtrl.dispose();
    super.dispose();
  }

  void _saveBudget() {
    final v = double.tryParse(budgetCtrl.text);
    if (v == null || v <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入正确的预算金额'), duration: Duration(milliseconds: 1200)));
      return;
    }
    widget.onSetBudget(v);
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('每月预算已设为 ${fmtYuan(v)}'), duration: const Duration(milliseconds: 1200)));
  }

  void _saveMonthlySave() {
    final v = double.tryParse(saveCtrl.text);
    if (v == null || v <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入正确的存钱目标'), duration: Duration(milliseconds: 1200)));
      return;
    }
    widget.onSetMonthlySave(v);
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('每月计划存已设为 ${fmtYuan(v)}'), duration: const Duration(milliseconds: 1200)));
  }

  /// 每月计划存的本月进度（只统计到今天，不算未来的计划账）
  Widget _saveProgress() {
    final target = widget.data.monthlySave;
    if (target <= 0) return const SizedBox.shrink();
    final now = DateTime.now();
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    double income = 0;
    double expense = 0;
    for (final t in widget.data.txns) {
      if (t.date.year != now.year || t.date.month != now.month || t.date.isAfter(endOfToday)) continue;
      if (t.income) {
        income += t.amount;
      } else {
        expense += t.amount;
      }
    }
    final saved = income - expense;
    final ratio = (saved / target).clamp(0.0, 1.0);
    final color = saved < 0 ? Colors.red : saved >= target ? curTheme.primary : Colors.orange;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(
          saved >= 0 ? '本月已存 ${fmtYuan(saved)} / 目标 ${fmtYuan(target)}' : '本月已超支 ${fmtYuan(saved.abs())}，还没存下钱',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(value: ratio, minHeight: 8, backgroundColor: curTheme.trackBg, color: color),
        ),
      ],
    );
  }

  List<Widget> _salaryHistory() {
    final list = widget.data.salaryChanges;
    final rows = <Widget>[];
    for (var i = 0; i < list.length; i++) {
      final c = list[i];
      final prev = i > 0 ? list[i - 1].amount : null;
      final diff = prev == null ? null : c.amount - prev;
      final up = diff != null && diff > 0;
      final down = diff != null && diff < 0;
      final color = up ? curTheme.primary : down ? Colors.red : Colors.grey;
      final label = diff == null
          ? '起点'
          : up
              ? '涨 ${fmtYuan(diff)}'
              : down
                  ? '降 ${fmtYuan(diff.abs())}'
                  : '持平';
      rows.add(
        ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 0),
          leading: Icon(
            up ? Icons.trending_up : down ? Icons.trending_down : Icons.flag_outlined,
            color: color,
            size: 20,
          ),
          title: Text('${c.date.year}/${c.date.month}/${c.date.day} 起 · 每月 ${fmtYuan(c.amount)}', style: const TextStyle(fontSize: 13)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: TextStyle(fontSize: 12, color: color)),
              IconButton(
                icon: Icon(Icons.close, size: 16, color: Colors.grey.shade400),
                onPressed: () => widget.onDeleteSalary(c.id),
              ),
            ],
          ),
        ),
      );
    }
    return rows;
  }

  Future<void> _addSalaryChange() async {
    var date = DateTime.now();
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(widget.data.salaryChanges.isEmpty ? '设置每月工资' : '添加调薪'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: date,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                    helpText: '生效日期',
                  );
                  if (picked != null) setDialogState(() => date = picked);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: '生效日期', border: OutlineInputBorder(), isDense: true),
                  child: Text('${date.year}/${date.month}/${date.day}'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [_AmountInputFormatter()],
                onChanged: (_) => setDialogState(() {}),
                decoration: const InputDecoration(
                  prefixText: '¥ ',
                  labelText: '每月工资',
                  hintText: '如 8000',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(
              onPressed: (double.tryParse(ctrl.text) ?? 0) > 0 ? () => Navigator.pop(ctx, true) : null,
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final v = double.tryParse(ctrl.text);
    if (v == null || v <= 0) return;
    widget.onAddSalary(
      SalaryChange(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        date: DateTime(date.year, date.month, date.day),
        amount: v,
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已保存：${date.year}/${date.month}/${date.day} 起每月 ${fmtYuan(v)}')),
      );
    }
  }

  Future<void> _addRecur() async {
    var isIncome = false;
    var day = 1;
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('添加定期账单'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('支出'), icon: Icon(Icons.north_east, size: 16)),
                  ButtonSegment(value: true, label: Text('收入'), icon: Icon(Icons.south_west, size: 16)),
                ],
                selected: {isIncome},
                onSelectionChanged: (s) => setDialogState(() => isIncome = s.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountCtrl,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [_AmountInputFormatter()],
                onChanged: (_) => setDialogState(() {}),
                decoration: const InputDecoration(
                  prefixText: '¥ ',
                  labelText: '每月金额',
                  hintText: '如 2000',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: day,
                decoration: const InputDecoration(labelText: '每月几号', border: OutlineInputBorder(), isDense: true),
                items: List.generate(31, (i) => i + 1).map((d) => DropdownMenuItem(value: d, child: Text('$d 号'))).toList(),
                onChanged: (v) {
                  if (v != null) setDialogState(() => day = v);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(labelText: '备注（如：房租）', border: OutlineInputBorder(), isDense: true),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(
              onPressed: (double.tryParse(amountCtrl.text) ?? 0) > 0 ? () => Navigator.pop(ctx, true) : null,
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final v = double.tryParse(amountCtrl.text);
    if (v == null || v <= 0) return;
    widget.onAddRecur(
      Recur(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        income: isIncome,
        amount: v,
        day: day,
        note: noteCtrl.text.trim(),
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已添加定期账单')));
    }
  }

  Future<void> _export() async {
    final json = const JsonEncoder.withIndent('  ').convert(widget.data.toJson());
    await Clipboard.setData(ClipboardData(text: json));
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('数据已复制'),
        content: SingleChildScrollView(child: Text('备份内容已复制到剪贴板，可粘贴到微信收藏、备忘录等地方保存。\n\n$json', style: const TextStyle(fontSize: 12))),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('知道了'))],
      ),
    );
  }

  Future<void> _import() async {
    final ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入备份'),
        content: TextField(
          controller: ctrl,
          maxLines: 6,
          decoration: const InputDecoration(hintText: '粘贴之前复制的备份内容', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('导入并替换')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final decoded = jsonDecode(ctrl.text.trim());
      if (decoded is Map<String, dynamic>) {
        final parsed = AppData.fromJson(decoded);
        if (parsed != null) {
          widget.onImport(parsed);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入成功，共 ${parsed.txns.length} 笔记录')));
          }
          return;
        }
      }
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('内容格式不对，导入失败')));
    }
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空所有数据'),
        content: const Text('所有记录和设置都会删除，无法恢复。确定吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok == true) widget.onClearAll();
  }

  @override
  Widget build(BuildContext context) {
    final currentSalary = widget.data.salaryAt(DateTime.now());
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('主题', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('换个心情记账，点击切换配色', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 12,
                children: [
                  for (var i = 0; i < themeDefs.length; i++)
                    _ThemeSwatch(
                      def: themeDefs[i],
                      selected: i == widget.data.themeIndex.clamp(0, themeDefs.length - 1),
                      onTap: () => widget.onSetTheme(i),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('每月预算', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('按月规划支出上限，概览页会自动算出每天还能花多少', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: budgetCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [_AmountInputFormatter()],
                      decoration: const InputDecoration(
                        prefixText: '¥ ',
                        hintText: '如 3000',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(onPressed: _saveBudget, child: const Text('保存')),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('每月计划存', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('定个每月存钱小目标', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: saveCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [_AmountInputFormatter()],
                      decoration: const InputDecoration(
                        prefixText: '¥ ',
                        hintText: '如 2000',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(onPressed: _saveMonthlySave, child: const Text('保存')),
                ],
              ),
              _saveProgress(),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('每月工资', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(
                          currentSalary > 0 ? '当前每月 ${fmtYuan(currentSalary)}' : '记下每月工资，涨薪降薪随时更新',
                          style: TextStyle(
                            fontSize: 13,
                            color: currentSalary > 0 ? curTheme.primary : Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 140,
                    child: DropdownButtonFormField<int>(
                      value: widget.data.salaryDay.clamp(1, 31),
                      isExpanded: true, // 避免“每月 N 号”撑破窄容器
                      decoration: const InputDecoration(labelText: '发薪日', border: OutlineInputBorder(), isDense: true),
                      items: List.generate(31, (i) => i + 1)
                          .map((d) => DropdownMenuItem(value: d, child: Text('每月 $d 号')))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) widget.onSetSalaryDay(v);
                      },
                    ),
                  ),
                ],
              ),
              if (widget.data.salaryChanges.isNotEmpty) ..._salaryHistory(),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _addSalaryChange,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(widget.data.salaryChanges.isEmpty ? '设置每月工资' : '添加调薪'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('定期账单', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('每月固定的收支（如房租、订阅），按月计入“按工资和支出”的预测',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              if (widget.data.recurs.isNotEmpty)
                for (final r in widget.data.recurs)
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 0),
                    leading: Icon(
                      r.income ? Icons.south_west : Icons.north_east,
                      size: 20,
                      color: r.income ? curTheme.primary : Colors.red,
                    ),
                    title: Text(
                      '${r.note.isEmpty ? (r.income ? '定期收入' : '定期支出') : r.note} · 每月 ${r.day} 号',
                      style: const TextStyle(fontSize: 13),
                    ),
                    subtitle: Text(
                      '${r.income ? '+' : '-'}${fmtYuan(r.amount.abs())}',
                      style: TextStyle(fontSize: 12, color: r.income ? curTheme.primary : Colors.red),
                    ),
                    trailing: IconButton(
                      icon: Icon(Icons.close, size: 16, color: Colors.grey.shade400),
                      onPressed: () => widget.onDeleteRecur(r.id),
                    ),
                  ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _addRecur,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('添加定期账单'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('备份与恢复', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('数据只存在这台手机上，换手机或清缓存前记得备份', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: FilledButton.tonalIcon(onPressed: _export, icon: const Icon(Icons.copy, size: 18), label: const Text('导出'))),
                  const SizedBox(width: 12),
                  Expanded(child: FilledButton.tonalIcon(onPressed: _import, icon: const Icon(Icons.paste, size: 18), label: const Text('导入'))),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text('清空所有数据', style: TextStyle(color: Colors.red)),
            onTap: _confirmClear,
          ),
        ),
      ],
    );
  }
}

class _TxnSheet extends StatefulWidget {
  final Txn? initial;
  final ValueChanged<Txn> onSave;
  final ValueChanged<String>? onDelete;

  const _TxnSheet({this.initial, required this.onSave, this.onDelete});

  @override
  State<_TxnSheet> createState() => _TxnSheetState();
}

class _TxnSheetState extends State<_TxnSheet> {
  late bool income;
  late DateTime date;
  late String category;
  late final TextEditingController amountCtrl;
  late final TextEditingController noteCtrl;

  @override
  void initState() {
    super.initState();
    income = widget.initial?.income ?? false;
    date = widget.initial?.date ?? DateTime.now();
    category = widget.initial?.category ?? '';
    amountCtrl = TextEditingController(text: widget.initial != null ? widget.initial!.amount.toStringAsFixed(2) : '');
    noteCtrl = TextEditingController(text: widget.initial?.note ?? '');
  }

  @override
  void dispose() {
    amountCtrl.dispose();
    noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: '选择日期',
    );
    if (picked != null) setState(() => date = picked);
  }

  void _submit() {
    final amount = double.tryParse(amountCtrl.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入金额'), duration: Duration(milliseconds: 1000)));
      return;
    }
    widget.onSave(
      Txn(
        id: widget.initial?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        income: income,
        amount: amount,
        date: DateTime(date.year, date.month, date.day),
        note: noteCtrl.text.trim(),
        category: income ? '' : category,
      ),
    );
    Navigator.pop(context);
  }

  void _delete() {
    final id = widget.initial?.id;
    if (id == null || widget.onDelete == null) return;
    widget.onDelete!(id);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final isToday = date.year == today.year && date.month == today.month && date.day == today.day;
    final isYesterday = date.year == today.year && date.month == today.month && date.day == today.day - 1;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 16),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('支出'), icon: Icon(Icons.north_east, size: 18)),
                ButtonSegment(value: true, label: Text('收入'), icon: Icon(Icons.south_west, size: 18)),
              ],
              selected: {income},
              onSelectionChanged: (s) => setState(() => income = s.first),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: amountCtrl,
              autofocus: widget.initial == null,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [_AmountInputFormatter()],
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                prefixText: '¥ ',
                prefixStyle: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: income ? curTheme.primary : Colors.red),
                hintText: '0.00',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            if (!income)
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final c in expenseCats)
                    ChoiceChip(
                      label: Text(c.name),
                      avatar: Icon(c.icon, size: 15, color: c.color),
                      selected: category == c.name,
                      onSelected: (_) => setState(() => category = category == c.name ? '' : c.name),
                      labelStyle: const TextStyle(fontSize: 13),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            if (!income) const SizedBox(height: 12),
            Row(
              children: [
                ChoiceChip(
                  label: const Text('今天'),
                  selected: isToday,
                  onSelected: (_) => setState(() => date = today),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('昨天'),
                  selected: isYesterday,
                  onSelected: (_) => setState(() => date = DateTime(today.year, today.month, today.day - 1)),
                ),
                const SizedBox(width: 8),
                ActionChip(
                  label: Text('${date.year}/${date.month}/${date.day}'),
                  avatar: const Icon(Icons.calendar_month, size: 18),
                  onPressed: _pickDate,
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteCtrl,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                hintText: '备注（比如：买菜、工资）',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                if (widget.onDelete != null)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                    onPressed: _delete,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('删除'),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: curTheme.primary,
                    ),
                    onPressed: _submit,
                    child: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('保存', style: TextStyle(fontSize: 16))),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
