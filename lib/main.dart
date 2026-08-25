import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _storeKey = 'ledger_data_v1';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '我的小账本',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1B8A5A)),
        useMaterial3: true,
        fontFamily: null,
      ),
      home: const AppRoot(),
    );
  }
}

class Txn {
  String id;
  bool income;
  double amount;
  DateTime date;
  String note;

  Txn({
    required this.id,
    required this.income,
    required this.amount,
    required this.date,
    required this.note,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'income': income,
      'amount': amount,
      'date': ymd(date),
      'note': note,
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
    );
  }
}

class AppData {
  List<Txn> txns;
  double budget;
  int salaryDay;

  AppData({required this.txns, required this.budget, required this.salaryDay});

  factory AppData.empty() => AppData(txns: [], budget: 0, salaryDay: 1);

  Map<String, dynamic> toJson() => {
        'txns': txns.map((t) => t.toMap()).toList(),
        'budget': budget,
        'salaryDay': salaryDay,
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
    return AppData(
      txns: list,
      budget: double.tryParse(map['budget']?.toString() ?? '') ?? 0,
      salaryDay: int.tryParse(map['salaryDay']?.toString() ?? '') ?? 1,
    );
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

String fmtYuan(double v) => '¥${fmtMoney(v)}';

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
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _TxnSheet(
        initial: initial,
        onSave: (t) {
          _addOrUpdate(t);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(initial == null ? '已记一笔' : '已保存修改'), duration: const Duration(milliseconds: 900)),
          );
        },
        onDelete: initial == null
            ? null
            : (id) {
                _delete(id);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已删除'), duration: Duration(milliseconds: 900)),
                );
              },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      OverviewPage(data: data, cursor: cursor, onCursor: (d) => setState(() => cursor = d), onAdd: () => _openSheet(), onGotoPlan: _gotoPlan),
      TxnsPage(data: data, onTap: (t) => _openSheet(initial: t), onAdd: () => _openSheet()),
      PlanPage(
        data: data,
        onSetBudget: _setBudget,
        onSetSalaryDay: _setSalaryDay,
        onImport: _replaceData,
        onClearAll: _clearAll,
      ),
    ];
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F5),
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
              color: Colors.white,
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

  const OverviewPage({
    super.key,
    required this.data,
    required this.cursor,
    required this.onCursor,
    required this.onAdd,
    required this.onGotoPlan,
  });

  @override
  Widget build(BuildContext context) {
    final monthTxns = data.txns.where((t) => t.date.year == cursor.year && t.date.month == cursor.month).toList();
    final income = monthTxns.where((t) => t.income).fold<double>(0, (s, t) => s + t.amount);
    final expense = monthTxns.where((t) => !t.income).fold<double>(0, (s, t) => s + t.amount);
    final balance = income - expense;

    final totalIncome = data.txns.where((t) => t.income).fold<double>(0, (s, t) => s + t.amount);
    final totalExpense = data.txns.where((t) => !t.income).fold<double>(0, (s, t) => s + t.amount);
    final totalBalance = totalIncome - totalExpense;

    final now = DateTime.now();
    final isCurrentMonth = cursor.year == now.year && cursor.month == now.month;
    final budget = data.budget;
    final budgetLeft = budget - expense;
    final ratio = budget > 0 ? expense / budget : 0.0;

    int daysLeftInclToday = 0;
    if (isCurrentMonth) {
      daysLeftInclToday = daysInMonth(now) - now.day + 1;
    }
    final dailyAllowance = daysLeftInclToday > 0 && budgetLeft > 0 ? budgetLeft / daysLeftInclToday : budgetLeft > 0 ? budgetLeft : 0.0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _MonthBar(cursor: cursor, onCursor: onCursor),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1B8A5A), Color(0xFF146B47)],
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
                    backgroundColor: Colors.grey.shade200,
                    color: ratio >= 1 ? Colors.red : ratio >= 0.8 ? Colors.orange : Color(0xFF1B8A5A),
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
                              color: budgetLeft < 0 ? Colors.red : Color(0xFF1B8A5A),
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
                            Text(fmtYuan(dailyAllowance), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF1B8A5A))),
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
                const Icon(Icons.flag_outlined, color: Color(0xFF1B8A5A)),
                const SizedBox(width: 12),
                const Expanded(child: Text('设置每月预算，帮你规划每天能花多少钱')),
                TextButton(onPressed: onGotoPlan, child: const Text('去设置')),
              ],
            ),
          ),
        const SizedBox(height: 12),
        _Card(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('累计总结余', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                    Text(
                      fmtYuan(totalBalance),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: totalBalance >= 0 ? Color(0xFF1B8A5A) : Colors.red,
                      ),
                    ),
                    Text('全部收入 ${fmtYuan(totalIncome)} － 支出 ${fmtYuan(totalExpense)}',
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
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
        const SizedBox(height: 12),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('以后的日子', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              const SizedBox(height: 6),
              Text(
                '提前把工资、要花的钱记到未来月份，这里就会显示规划结果。当前查看的 ${cursor.month} 月'
                '${monthTxns.isEmpty ? '还没有记录' : '已有 ${monthTxns.length} 笔记录，结余 ${fmtYuan(balance)}'}。',
                style: const TextStyle(fontSize: 14, height: 1.5),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
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
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: ListTile(
                  onTap: () => onTap(t),
                  leading: CircleAvatar(
                    backgroundColor: (t.income ? const Color(0xFFE3F2EC) : Colors.red.shade50),
                    child: Icon(
                      t.income ? Icons.south_west : Icons.north_east,
                      color: t.income ? const Color(0xFF1B8A5A) : Colors.red,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    t.note.isEmpty ? (t.income ? '收入' : '支出') : t.note,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15),
                  ),
                  subtitle: Text(dateLabel(t.date),
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                  trailing: Text(
                    '${t.income ? '+' : '-'}${fmtYuan(t.amount)}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: t.income ? const Color(0xFF1B8A5A) : Colors.black87,
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
  final ValueChanged<AppData> onImport;
  final VoidCallback onClearAll;

  const PlanPage({
    super.key,
    required this.data,
    required this.onSetBudget,
    required this.onSetSalaryDay,
    required this.onImport,
    required this.onClearAll,
  });

  @override
  State<PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends State<PlanPage> {
  late final TextEditingController budgetCtrl;

  @override
  void initState() {
    super.initState();
    budgetCtrl = TextEditingController(text: widget.data.budget > 0 ? widget.data.budget.toStringAsFixed(2) : '');
  }

  @override
  void dispose() {
    budgetCtrl.dispose();
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
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
              const Text('几号发工资', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('记账周期按自然月统计，此项仅作提醒参考', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                value: widget.data.salaryDay.clamp(1, 31),
                decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                items: List.generate(31, (i) => i + 1)
                    .map((d) => DropdownMenuItem(value: d, child: Text('每月 $d 号')))
                    .toList(),
                onChanged: (v) {
                  if (v != null) widget.onSetSalaryDay(v);
                },
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
  late final TextEditingController amountCtrl;
  late final TextEditingController noteCtrl;

  @override
  void initState() {
    super.initState();
    income = widget.initial?.income ?? false;
    date = widget.initial?.date ?? DateTime.now();
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
                prefixStyle: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: income ? const Color(0xFF1B8A5A) : Colors.red),
                hintText: '0.00',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
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
                      backgroundColor: income ? const Color(0xFF1B8A5A) : Theme.of(context).colorScheme.primary,
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
