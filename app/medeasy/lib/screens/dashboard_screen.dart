import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/config.dart';
import '../models/medicine.dart';
import '../providers/auth_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/medicine_provider.dart';
import '../providers/report_provider.dart';
import 'login_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    return Scaffold(
      appBar: AppBar(
        title: const Text('MedEasy POS'),
        actions: [
          if (user != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: Text('${user.username} (${user.role})'),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              context.read<AuthProvider>().logout();
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
          )
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Inventory'),
            Tab(text: 'Employees'),
            Tab(text: 'Reports'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          InventoryTab(),
          EmployeeTab(),
          ReportTab(),
        ],
      ),
    );
  }
}

class InventoryTab extends StatefulWidget {
  const InventoryTab({super.key});

  @override
  State<InventoryTab> createState() => _InventoryTabState();
}

class _InventoryTabState extends State<InventoryTab> {
  final _searchCtrl = TextEditingController();
  final _quantityCtrl = TextEditingController();
  final _costCtrl = TextEditingController();
  final _saleCtrl = TextEditingController();
  final _expiryCtrl =
      TextEditingController(text: DateFormat('yyyy-MM-dd').format(DateTime.now().add(const Duration(days: 90))));
  Medicine? _selected;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _quantityCtrl.dispose();
    _costCtrl.dispose();
    _saleCtrl.dispose();
    _expiryCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final auth = context.read<AuthProvider>();
    if (auth.token == null) return;
    await context
        .read<MedicineProvider>()
        .search(auth.token!, query: _searchCtrl.text.trim());
  }

  Future<void> _addInventory() async {
    final auth = context.read<AuthProvider>();
    if (auth.token == null || _selected == null) return;
    final quantity = int.tryParse(_quantityCtrl.text) ?? 0;
    final costPrice = double.tryParse(_costCtrl.text) ?? 0;
    final salePrice = double.tryParse(_saleCtrl.text) ?? 0;
    if (quantity <= 0 || costPrice <= 0 || salePrice <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fill quantity, cost and sale price')),
      );
      return;
    }
    await context.read<InventoryProvider>().addInventory(
          token: auth.token!,
          medicineId: _selected!.id,
          quantity: quantity,
          costPrice: costPrice,
          salePrice: salePrice,
          expiryDate: _expiryCtrl.text.trim(),
        );
    final error = context.read<InventoryProvider>().error;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inventory item added')),
      );
      _quantityCtrl.clear();
      _costCtrl.clear();
      _saleCtrl.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final medicineProv = context.watch<MedicineProvider>();
    final inventoryProv = context.watch<InventoryProvider>();
    final auth = context.watch<AuthProvider>();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Add inventory (owner & employee)', style: AppTextStyle.sectionTitle),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Search medicine',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onSubmitted: (_) => _search(),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: auth.token == null || medicineProv.loading ? null : _search,
                child: const Text('Search'),
              ),
            ],
          ),
          if (medicineProv.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                medicineProv.error!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          const SizedBox(height: 12),
          SizedBox(
            height: 180,
            child: ListView.builder(
              itemCount: medicineProv.results.length,
              itemBuilder: (context, index) {
                final medicine = medicineProv.results[index];
                final selected = _selected?.id == medicine.id;
                return ListTile(
                  title: Text(medicine.brandName),
                  subtitle: Text('${medicine.genericName} • ${medicine.manufacturer}'),
                  trailing: selected ? const Icon(Icons.check, color: AppColors.primary) : null,
                  selected: selected,
                  onTap: () => setState(() => _selected = medicine),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 140,
                child: TextField(
                  controller: _quantityCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Quantity'),
                ),
              ),
              SizedBox(
                width: 160,
                child: TextField(
                  controller: _costCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Total cost price'),
                ),
              ),
              SizedBox(
                width: 160,
                child: TextField(
                  controller: _saleCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Total sale price'),
                ),
              ),
              SizedBox(
                width: 170,
                child: TextField(
                  controller: _expiryCtrl,
                  decoration: const InputDecoration(labelText: 'Expiry (YYYY-MM-DD)'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: inventoryProv.saving ? null : _addInventory,
            icon: const Icon(Icons.add_box),
            label: Text(inventoryProv.saving ? 'Saving...' : 'Add to inventory'),
          ),
          const Divider(height: 32),
          Text('Your inventory', style: AppTextStyle.sectionTitle),
          const SizedBox(height: 8),
          FutureBuilder(
            future: auth.token != null
                ? context.read<InventoryProvider>().search(
                      token: auth.token!,
                      query: '',
                    )
                : null,
            builder: (context, snapshot) {
              final items = inventoryProv.items;
              if (inventoryProv.loading) {
                return const Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(),
                );
              }
              if (items.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('No inventory items found'),
                );
              }
              return Column(
                children: items
                    .map(
                      (e) => Card(
                        child: ListTile(
                          title: Text(e.brandName),
                          subtitle: Text(
                              'Stock: ${e.quantity} • Cost: ${e.unitCost.toStringAsFixed(2)} • Price: ${e.unitPrice.toStringAsFixed(2)}'),
                          trailing: e.expiryDate != null
                              ? Text('Exp ${e.expiryDate}')
                              : const Text('No expiry'),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class EmployeeTab extends StatefulWidget {
  const EmployeeTab({super.key});

  @override
  State<EmployeeTab> createState() => _EmployeeTabState();
}

class _EmployeeTabState extends State<EmployeeTab> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await context.read<AuthProvider>().createEmployee(
            username: _nameCtrl.text.trim(),
            email: _emailCtrl.text.trim(),
            password: _passCtrl.text.trim(),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Employee created')),
        );
        _formKey.currentState?.reset();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.user?.isOwner != true) {
      return const Center(child: Text('Only owners can create employees.'));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Create employee', style: AppTextStyle.sectionTitle),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'Username'),
                  validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailCtrl,
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passCtrl,
                  decoration: const InputDecoration(labelText: 'Password'),
                  obscureText: true,
                  validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _saving ? null : _submit,
                  child: Text(_saving ? 'Saving...' : 'Create employee'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ReportTab extends StatefulWidget {
  const ReportTab({super.key});

  @override
  State<ReportTab> createState() => _ReportTabState();
}

class _ReportTabState extends State<ReportTab> {
  final _startCtrl = TextEditingController();
  final _endCtrl = TextEditingController();

  @override
  void dispose() {
    _startCtrl.dispose();
    _endCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBasics() async {
    final auth = context.read<AuthProvider>();
    if (auth.token == null) return;
    final report = context.read<ReportProvider>();
    await Future.wait([
      report.loadDaily(auth.token!),
      report.loadMonthly(auth.token!),
    ]);
  }

  Future<void> _loadRange() async {
    final auth = context.read<AuthProvider>();
    if (auth.token == null) return;
    await context.read<ReportProvider>().loadRange(
          auth.token!,
          start: _startCtrl.text.trim().isEmpty ? null : _startCtrl.text.trim(),
          end: _endCtrl.text.trim().isEmpty ? null : _endCtrl.text.trim(),
        );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final report = context.watch<ReportProvider>();
    if (auth.user?.isOwner != true) {
      return const Center(child: Text('Reports are owner-only.'));
    }
    return RefreshIndicator(
      onRefresh: _loadBasics,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Daily & Monthly', style: AppTextStyle.sectionTitle),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  label: 'Daily revenue',
                  value: report.daily?['revenue']?.toString() ?? '-',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  label: 'Daily sales',
                  value: report.daily?['sales_count']?.toString() ?? '-',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  label: 'Monthly revenue',
                  value: report.monthly?['revenue']?.toString() ?? '-',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  label: 'Monthly sales',
                  value: report.monthly?['sales_count']?.toString() ?? '-',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: report.loading ? null : _loadBasics,
            icon: const Icon(Icons.refresh),
            label: Text(report.loading ? 'Loading...' : 'Refresh summaries'),
          ),
          const Divider(height: 32),
          Text('Custom range', style: AppTextStyle.sectionTitle),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _startCtrl,
                  decoration: const InputDecoration(labelText: 'Start (YYYY-MM-DD)'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _endCtrl,
                  decoration: const InputDecoration(labelText: 'End (YYYY-MM-DD)'),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: report.loading ? null : _loadRange,
                child: Text(report.loading ? 'Loading...' : 'Load'),
              ),
            ],
          ),
          if (report.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(report.error!, style: const TextStyle(color: Colors.red)),
            ),
          const SizedBox(height: 12),
          ...report.range.map((entry) => Card(
                child: ListTile(
                  title: Text('Sale #${entry.id}'),
                  subtitle: Text(
                      'Amount: ${entry.totalAmount.toStringAsFixed(2)} | Paid: ${entry.paidAmount.toStringAsFixed(2)} | Due: ${entry.dueAmount.toStringAsFixed(2)}'),
                  trailing: Text(entry.createdAt),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: Text('Sale #${entry.id} items'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: entry.items
                              .map((item) => ListTile(
                                    dense: true,
                                    title: Text(item.brandName),
                                    subtitle: Text(
                                        '${item.quantity} pcs @ ${item.unitPrice.toStringAsFixed(2)}'),
                                    trailing: Text(item.subtotal.toStringAsFixed(2)),
                                  ))
                              .toList(),
                        ),
                      ),
                    );
                  },
                ),
              )),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 6),
            Text(
              value,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(color: AppColors.primary),
            )
          ],
        ),
      ),
    );
  }
}
