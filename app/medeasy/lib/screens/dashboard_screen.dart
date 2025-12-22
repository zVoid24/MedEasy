import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/config.dart';
import '../models/medicine.dart';
import '../models/inventory_item.dart';
import '../providers/auth_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/medicine_provider.dart';

import '../providers/sales_provider.dart';
import 'login_screen.dart';
import 'report_screens.dart';
import '../widgets/month_year_picker.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isOwner = false;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    _isOwner = auth.user?.role == 'owner';
    // Tabs: Sales, Inventory List, Add Inventory (Owner/Employee), Employees (Owner), Reports (Owner)
    // Employee: Sales, Inventory List, Add Inventory
    // Owner: Sales, Inventory List, Add Inventory, Employees, Reports
    final tabCount = _isOwner ? 5 : 3;
    _tabController = TabController(length: tabCount, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    // Re-check role in build in case it changes (though usually requires re-login)
    final isOwner = auth.user?.role == 'owner';

    return Scaffold(
      appBar: AppBar(
        title: const Text('MedEasy POS'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              context.read<AuthProvider>().logout();
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: Center(
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.center,
              indicatorColor: Colors.white,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              tabs: [
                const Tab(text: 'Sales', icon: Icon(Icons.point_of_sale)),
                const Tab(text: 'Inventory', icon: Icon(Icons.inventory)),
                const Tab(text: 'Add Items', icon: Icon(Icons.add_box)),
                if (isOwner) ...[
                  const Tab(text: 'Employees', icon: Icon(Icons.people)),
                  const Tab(text: 'Reports', icon: Icon(Icons.analytics)),
                ],
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          const SalesTab(),
          const InventoryListTab(),
          const AddInventoryTab(),
          if (isOwner) ...[const EmployeeTab(), const ReportTab()],
        ],
      ),
    );
  }
}

class AddInventoryTab extends StatefulWidget {
  const AddInventoryTab({super.key});

  @override
  State<AddInventoryTab> createState() => _AddInventoryTabState();
}

class _AddInventoryTabState extends State<AddInventoryTab> {
  final _searchCtrl = TextEditingController();
  final _quantityCtrl = TextEditingController();
  final _costCtrl = TextEditingController();
  final _saleCtrl = TextEditingController();
  final _expiryCtrl = TextEditingController();
  Timer? _debounce;
  Medicine? _selected;
  DateTime? _expiryDate;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _quantityCtrl.dispose();
    _costCtrl.dispose();
    _saleCtrl.dispose();
    _expiryCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (query.isNotEmpty) {
        _search();
      }
    });
  }

  Future<void> _search() async {
    final auth = context.read<AuthProvider>();
    if (auth.token == null) return;
    await context.read<MedicineProvider>().search(
      token: auth.token!,
      query: _searchCtrl.text.trim(),
    );
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDialog<DateTime>(
      context: context,
      builder: (context) => MonthYearPicker(
        initialDate: DateTime.now(),
        firstDate: DateTime.now(),
        lastDate: DateTime(2101),
      ),
    );

    if (picked != null) {
      setState(() {
        _expiryDate = picked;
        _expiryCtrl.text = DateFormat('MMM yyyy').format(picked);
      });
    }
  }

  Future<void> _addInventory() async {
    if (_selected == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a medicine')));
      return;
    }
    final auth = context.read<AuthProvider>();
    if (auth.token == null) return;

    final qty = int.tryParse(_quantityCtrl.text) ?? 0;
    final cost = double.tryParse(_costCtrl.text) ?? 0;
    final sale = double.tryParse(_saleCtrl.text) ?? 0;

    await context.read<InventoryProvider>().addInventory(
      token: auth.token!,
      medicineId: _selected!.id,
      quantity: qty,
      costPrice: cost,
      salePrice: sale,
      expiryDate: _expiryDate != null
          ? DateFormat('yyyy-MM-dd').format(_expiryDate!)
          : null,
    );

    final error = context.read<InventoryProvider>().error;
    if (mounted) {
      if (error != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error)));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Inventory added successfully')),
        );
        _quantityCtrl.clear();
        _costCtrl.clear();
        _saleCtrl.clear();
        _expiryCtrl.clear();
        _searchCtrl.clear();
        setState(() {
          _selected = null;
        });
        // Refresh inventory list
        context.read<InventoryProvider>().loadInventory(token: auth.token!);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final medicineProv = context.watch<MedicineProvider>();
    final inventoryProv = context.watch<InventoryProvider>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Add Inventory', style: AppTextStyle.headline),
          const SizedBox(height: 16),
          TextField(
            controller: _searchCtrl,
            decoration: const InputDecoration(
              labelText: 'Search medicine...',
              prefixIcon: Icon(Icons.search),
              hintText: 'Type to search automatically',
            ),
            onChanged: _onSearchChanged,
          ),
          if (medicineProv.loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (medicineProv.results.isNotEmpty &&
              _searchCtrl.text.isNotEmpty &&
              !medicineProv.loading) ...[
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 400),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: medicineProv.results.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final medicine = medicineProv.results[index];
                  final isSelected = _selected?.id == medicine.id;
                  return ListTile(
                    title: Text(
                      medicine.brandName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${medicine.genericName} • ${medicine.manufacturer}',
                    ),
                    trailing: isSelected
                        ? const Icon(
                            Icons.check_circle,
                            color: AppColors.primary,
                          )
                        : null,
                    selected: isSelected,
                    selectedTileColor: AppColors.primary.withOpacity(0.1),
                    onTap: () => setState(() => _selected = medicine),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (_selected != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Selected: ${_selected!.brandName}',
                      style: AppTextStyle.sectionTitle,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _quantityCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Quantity',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _expiryCtrl,
                            readOnly: true,
                            decoration: const InputDecoration(
                              labelText: 'Expiry (MMM yyyy)',
                              suffixIcon: Icon(Icons.calendar_today),
                            ),
                            onTap: () => _selectDate(context),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _costCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Total Cost',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _saleCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Total Sale',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: inventoryProv.saving ? null : _addInventory,
                        icon: const Icon(Icons.add_box),
                        label: Text(
                          inventoryProv.saving
                              ? 'Saving...'
                              : 'Add to Inventory',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class InventoryListTab extends StatefulWidget {
  const InventoryListTab({super.key});

  @override
  State<InventoryListTab> createState() => _InventoryListTabState();
}

class _InventoryListTabState extends State<InventoryListTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInventory();
    });
  }

  Future<void> _loadInventory() async {
    final auth = context.read<AuthProvider>();
    if (auth.token != null) {
      await context.read<InventoryProvider>().loadInventory(token: auth.token!);
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'N/A';
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('MMM, yyyy').format(date);
    } catch (e) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    final inventoryProv = context.watch<InventoryProvider>();
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _loadInventory,
        child: const Icon(Icons.refresh),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your Inventory', style: AppTextStyle.headline),
            const SizedBox(height: 16),
            if (inventoryProv.loading)
              const Center(child: CircularProgressIndicator())
            else if (inventoryProv.items.isEmpty)
              const Center(
                child: Text(
                  'No inventory items found',
                  style: AppTextStyle.label,
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: inventoryProv.items.length,
                  itemBuilder: (context, index) {
                    final e = inventoryProv.items[index];
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppColors.primary.withOpacity(0.1),
                          child: Text(
                            e.quantity.toString(),
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          e.brandName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          'Cost: ${e.unitCost.toStringAsFixed(2)} | Price: ${e.unitPrice.toStringAsFixed(2)}',
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _formatDate(e.expiryDate),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Employee created')));
        _formKey.currentState?.reset();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
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
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailCtrl,
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passCtrl,
                  decoration: const InputDecoration(labelText: 'Password'),
                  obscureText: true,
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Required' : null,
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
  final _startDateCtrl = TextEditingController();
  final _endDateCtrl = TextEditingController();
  bool _loading = false;
  List<dynamic> _expiryAlerts = [];
  bool _loadingAlerts = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadExpiryAlerts();
    });
  }

  @override
  void dispose() {
    _startDateCtrl.dispose();
    _endDateCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadExpiryAlerts() async {
    final auth = context.read<AuthProvider>();
    if (auth.token == null) return;
    setState(() => _loadingAlerts = true);
    try {
      final response = await http.get(
        Uri.parse('${AppConfig.apiBaseUrl}/inventory/expiry-alert?days=90'),
        headers: {'Authorization': 'Bearer ${auth.token}'},
      );
      if (response.statusCode == 200) {
        setState(() {
          _expiryAlerts = jsonDecode(response.body);
        });
      }
    } catch (e) {
      // Handle error silently
    } finally {
      if (mounted) setState(() => _loadingAlerts = false);
    }
  }

  Future<void> _downloadReport(String type) async {
    final auth = context.read<AuthProvider>();
    if (auth.token == null) return;

    setState(() => _loading = true);
    try {
      String startDate = '';
      String endDate = '';
      String title = '';

      final now = DateTime.now();
      if (type == 'daily') {
        startDate = DateFormat('yyyy-MM-dd').format(now);
        endDate = startDate;
        title = 'Daily Sales (${DateFormat('MMM dd').format(now)})';
      } else if (type == 'monthly') {
        final start = DateTime(now.year, now.month, 1);
        final end = DateTime(now.year, now.month + 1, 0);
        startDate = DateFormat('yyyy-MM-dd').format(start);
        endDate = DateFormat('yyyy-MM-dd').format(end);
        title = 'Monthly Sales (${DateFormat('MMM yyyy').format(now)})';
      } else if (type == 'custom') {
        if (_startDateCtrl.text.isEmpty || _endDateCtrl.text.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Select start and end dates')),
          );
          setState(() => _loading = false);
          return;
        }
        startDate = _startDateCtrl.text;
        endDate = _endDateCtrl.text;
        title = 'Custom Report ($startDate to $endDate)';
      }

      final url =
          '${AppConfig.apiBaseUrl}/reports/sales?start_date=$startDate&end_date=$endDate';

      final response = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer ${auth.token}'},
      );

      if (response.statusCode == 200) {
        if (mounted) {
          final List<dynamic> sales = jsonDecode(response.body);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SalesReportScreen(title: title, sales: sales),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: ${response.body}')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _selectDate(
    BuildContext context,
    TextEditingController ctrl,
  ) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        ctrl.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Sales Reports', style: AppTextStyle.headline),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _ReportCard(
                  title: 'Daily Sales',
                  icon: Icons.today,
                  onTap: () => _downloadReport('daily'),
                  loading: _loading,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _ReportCard(
                  title: 'Monthly Sales',
                  icon: Icons.calendar_month,
                  onTap: () => _downloadReport('monthly'),
                  loading: _loading,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Custom Report', style: AppTextStyle.sectionTitle),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _startDateCtrl,
                          readOnly: true,
                          decoration: const InputDecoration(
                            labelText: 'Start Date',
                            suffixIcon: Icon(Icons.calendar_today),
                          ),
                          onTap: () => _selectDate(context, _startDateCtrl),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _endDateCtrl,
                          readOnly: true,
                          decoration: const InputDecoration(
                            labelText: 'End Date',
                            suffixIcon: Icon(Icons.calendar_today),
                          ),
                          onTap: () => _selectDate(context, _endDateCtrl),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _loading
                          ? null
                          : () => _downloadReport('custom'),
                      child: Text(_loading ? 'Loading...' : 'Generate Report'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          Text('Expiry Alerts (Next 90 Days)', style: AppTextStyle.headline),
          const SizedBox(height: 16),
          if (_loadingAlerts)
            const Center(child: CircularProgressIndicator())
          else if (_expiryAlerts.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: Text(
                    'No items expiring soon',
                    style: AppTextStyle.label,
                  ),
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _expiryAlerts.length,
              itemBuilder: (context, index) {
                final item = _expiryAlerts[index];
                String formattedDate = item['expiry_date'] ?? 'N/A';
                try {
                  formattedDate = DateFormat(
                    'MMM yyyy',
                  ).format(DateTime.parse(item['expiry_date']));
                } catch (_) {}

                return Card(
                  color: AppColors.error.withOpacity(0.1),
                  child: ListTile(
                    leading: const Icon(Icons.warning, color: AppColors.error),
                    title: Text(
                      item['brand_name'] ?? 'Unknown',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      'Expires: $formattedDate | Stock: ${item['quantity']}',
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final bool loading;

  const _ReportCard({
    required this.title,
    required this.icon,
    required this.onTap,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: loading ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(icon, size: 32, color: AppColors.primary),
              const SizedBox(height: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}

class SalesTab extends StatefulWidget {
  const SalesTab({super.key});

  @override
  State<SalesTab> createState() => _SalesTabState();
}

class _SalesTabState extends State<SalesTab> {
  final _searchCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController();
  final _paidCtrl = TextEditingController();
  final _discountCtrl = TextEditingController(text: '0');
  final _roundOffCtrl = TextEditingController(text: '0');
  Timer? _debounce;
  final _qtyFocus = FocusNode();

  List<Map<String, dynamic>> _cart = [];
  InventoryItem? _selectedItem;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _qtyCtrl.dispose();
    _paidCtrl.dispose();
    _discountCtrl.dispose();
    _roundOffCtrl.dispose();
    _qtyFocus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (query.isNotEmpty) {
        context.read<InventoryProvider>().search(
          token: context.read<AuthProvider>().token!,
          query: query,
        );
      }
    });
  }

  void _addToCart() {
    if (_selectedItem == null) return;
    final qty = int.tryParse(_qtyCtrl.text) ?? 0;
    if (qty <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invalid quantity')));
      return;
    }
    if (qty > _selectedItem!.quantity) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Insufficient stock')));
      return;
    }

    // Check if item already in cart
    final index = _cart.indexWhere(
      (item) => item['inventory_id'] == _selectedItem!.inventoryId,
    );
    if (index != -1) {
      setState(() {
        _cart[index]['quantity'] = (_cart[index]['quantity'] as int) + qty;
        _selectedItem = null;
        _qtyCtrl.clear();
        _searchCtrl.clear();
        _qtyFocus.unfocus();
      });
    } else {
      setState(() {
        _cart.add({
          'inventory_id': _selectedItem!.inventoryId,
          'medicine_id': _selectedItem!.medicineId,
          'quantity': qty,
          'item': _selectedItem, // For UI display
        });
        _selectedItem = null;
        _qtyCtrl.clear();
        _searchCtrl.clear();
        _qtyFocus.unfocus(); // Unfocus after adding
      });
    }
    context.read<InventoryProvider>().search(
      token: context.read<AuthProvider>().token!,
      query: '',
    ); // Clear search results
  }

  void _removeFromCart(int index) {
    setState(() {
      _cart.removeAt(index);
    });
  }

  Future<void> _checkout() async {
    if (_cart.isEmpty) return;
    final auth = context.read<AuthProvider>();
    if (auth.token == null) return;

    final discountPercent = double.tryParse(_discountCtrl.text) ?? 0;
    final paid = double.tryParse(_paidCtrl.text) ?? 0;
    final roundOff = double.tryParse(_roundOffCtrl.text) ?? 0;

    await context.read<SalesProvider>().createSale(
      token: auth.token!,
      items: _cart
          .map(
            (e) => {
              'inventory_id': e['inventory_id'],
              'medicine_id': e['medicine_id'],
              'quantity': e['quantity'],
            },
          )
          .toList(),
      discountPercent: discountPercent,
      paidAmount: paid,
      roundOff: roundOff,
    );

    final error = context.read<SalesProvider>().error;
    if (mounted) {
      if (error != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error)));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sale created successfully')),
        );
        setState(() {
          _cart.clear();
          _paidCtrl.clear();
          _discountCtrl.text = '0';
          _roundOffCtrl.text = '0';
        });
      }
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'N/A';
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('MMM, yyyy').format(date);
    } catch (e) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    final inventoryProv = context.watch<InventoryProvider>();
    final salesProv = context.watch<SalesProvider>();

    double total = 0;
    for (var item in _cart) {
      final invItem = item['item'] as InventoryItem;
      total += invItem.unitPrice * (item['quantity'] as int);
    }
    final discountPercent = double.tryParse(_discountCtrl.text) ?? 0;
    final discountAmount = (total * discountPercent) / 100;
    final roundOff = double.tryParse(_roundOffCtrl.text) ?? 0;

    // Calculate integers for display
    final totalRounded = total.roundToDouble();
    final discountRounded = discountAmount.roundToDouble();
    final roundOffRounded = roundOff.roundToDouble();

    final netPayable = totalRounded - discountRounded + roundOffRounded;

    final paidAmount = double.tryParse(_paidCtrl.text) ?? 0;
    final changeReturned = paidAmount > netPayable
        ? paidAmount - netPayable
        : 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('New Sale', style: AppTextStyle.headline),
          const SizedBox(height: 16),
          TextField(
            controller: _searchCtrl,
            decoration: const InputDecoration(
              labelText: 'Search medicine...',
              prefixIcon: Icon(Icons.search),
              hintText: 'Type to search automatically',
            ),
            onChanged: _onSearchChanged,
          ),
          if (inventoryProv.loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_selectedItem == null &&
              inventoryProv.items.isNotEmpty &&
              _searchCtrl.text.isNotEmpty &&
              !inventoryProv.loading) ...[
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 250),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: inventoryProv.items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = inventoryProv.items[index];
                  final isSelected =
                      _selectedItem?.inventoryId == item.inventoryId;
                  return ListTile(
                    title: Text(
                      item.brandName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      'Stock: ${item.quantity} | Price: ${item.unitPrice} | Exp: ${_formatDate(item.expiryDate)}',
                    ),
                    selected: isSelected,
                    selectedTileColor: AppColors.primary.withOpacity(0.1),
                    onTap: () {
                      setState(() {
                        _selectedItem = item;
                        _searchCtrl.text = item.brandName;
                        // Clear results to hide list, but keep selection
                        context.read<InventoryProvider>().search(
                          token: context.read<AuthProvider>().token!,
                          query: '',
                        );
                        FocusScope.of(
                          context,
                        ).requestFocus(_qtyFocus); // Auto-focus quantity
                      });
                    },
                    trailing: isSelected
                        ? const Icon(
                            Icons.check_circle,
                            color: AppColors.primary,
                          )
                        : const Icon(
                            Icons.add_circle_outline,
                            color: AppColors.primary,
                          ),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (_selectedItem != null)
            Card(
              color: AppColors.primary.withOpacity(0.1),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Selected: ${_selectedItem!.brandName}',
                          style: AppTextStyle.sectionTitle,
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            setState(() {
                              _selectedItem = null;
                              _searchCtrl.clear();
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _qtyCtrl,
                            focusNode: _qtyFocus,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Quantity',
                            ),
                            onSubmitted: (_) => _addToCart(), // Add on enter
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton(
                          onPressed: _addToCart,
                          child: const Text('Add to Cart'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 24),
          Text('Cart Items', style: AppTextStyle.sectionTitle),
          const SizedBox(height: 8),
          if (_cart.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: const Text(
                'Your cart is empty',
                style: AppTextStyle.label,
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _cart.length,
              itemBuilder: (context, index) {
                final item = _cart[index];
                final invItem = item['item'] as InventoryItem;
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.primary.withOpacity(0.1),
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(color: AppColors.primary),
                      ),
                    ),
                    title: Text(
                      invItem.brandName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${item['quantity']} x ${invItem.unitPrice} = ${(item['quantity'] as int) * invItem.unitPrice}',
                    ),
                    trailing: IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        color: AppColors.error,
                      ),
                      onPressed: () => _removeFromCart(index),
                    ),
                  ),
                );
              },
            ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _discountCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Discount (%)',
                            suffixText: '%',
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _roundOffCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Round Off (+/-)',
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _paidCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Paid Amount',
                      prefixText: '৳ ',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total:', style: AppTextStyle.body),
                      Text(
                        totalRounded.toStringAsFixed(0),
                        style: AppTextStyle.sectionTitle,
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Discount:', style: AppTextStyle.body),
                      Text(
                        '-${discountRounded.toStringAsFixed(0)}',
                        style: const TextStyle(
                          color: AppColors.error,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  if (roundOffRounded != 0)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Round Off:', style: AppTextStyle.body),
                        Text(
                          '${roundOffRounded > 0 ? '+' : ''}${roundOffRounded.toStringAsFixed(0)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Net Payable:', style: AppTextStyle.headline),
                      Text(
                        netPayable.toStringAsFixed(0),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Change Return:',
                        style: AppTextStyle.headline,
                      ),
                      Text(
                        changeReturned.toStringAsFixed(0),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _cart.isEmpty || salesProv.saving
                          ? null
                          : _checkout,
                      icon: const Icon(Icons.check),
                      label: Text(
                        salesProv.saving ? 'Processing...' : 'Complete Sale',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
