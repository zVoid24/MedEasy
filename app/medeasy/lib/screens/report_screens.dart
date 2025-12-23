import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/config.dart';

class SalesReportScreen extends StatelessWidget {
  final String title;
  final List<dynamic> sales;

  const SalesReportScreen({
    super.key,
    required this.title,
    required this.sales,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), centerTitle: true),
      body: sales.isEmpty
          ? const Center(child: Text('No sales found for this period.'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: sales.length,
              itemBuilder: (context, index) {
                final sale = sales[index];
                return _SaleCard(sale: sale);
              },
            ),
    );
  }
}

class _SaleCard extends StatelessWidget {
  final dynamic sale;

  const _SaleCard({required this.sale});

  @override
  Widget build(BuildContext context) {
    final date = DateTime.parse(sale['created_at']);
    final formattedDate = DateFormat('MMM dd, yyyy hh:mm a').format(date);
    final total = double.parse(sale['total_amount'].toString());
    final items = sale['items'] as List;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => SaleDetailScreen(sale: sale)),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Sale #${sale['id']}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: AppColors.primary,
                    ),
                  ),
                  if (sale['is_pending'] == true) ...[
                    const SizedBox(width: 8),
                    Tooltip(
                      message: 'Waiting to sync',
                      child: Icon(Icons.sync, size: 16, color: Colors.orange),
                    ),
                  ],
                  Text(
                    formattedDate,
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Total Amount',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${total.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${items.length} Items',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SaleDetailScreen extends StatelessWidget {
  final dynamic sale;

  const SaleDetailScreen({super.key, required this.sale});

  @override
  Widget build(BuildContext context) {
    final date = DateTime.parse(sale['created_at']);
    final formattedDate = DateFormat('MMM dd, yyyy hh:mm a').format(date);
    final items = sale['items'] as List;
    final total = double.parse(sale['total_amount'].toString());
    final discount = double.parse(sale['discount'].toString());
    final paid = double.parse(sale['paid_amount'].toString());
    final due = double.parse(sale['due_amount'].toString());
    final roundOff = double.tryParse(sale['round_off']?.toString() ?? '0') ?? 0;
    final changeReturned =
        double.tryParse(sale['change_returned']?.toString() ?? '0') ?? 0;

    return Scaffold(
      appBar: AppBar(title: Text('Sale #${sale['id']} Details')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Info
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total Amount',
                    style: TextStyle(color: Colors.white.withOpacity(0.8)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${total.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _HeaderInfo(label: 'Date', value: formattedDate),
                      _HeaderInfo(
                        label: 'Sold By',
                        value: 'User #${sale['user_id']}',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('Items', style: AppTextStyle.sectionTitle),
            const SizedBox(height: 8),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (context, index) {
                final item = items[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    item['brand_name'],
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text('${item['quantity']} x ${item['unit_price']}'),
                  trailing: Text(
                    '${item['subtotal']}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                );
              },
            ),
            const Divider(height: 32),
            Text('Payment Summary', style: AppTextStyle.sectionTitle),
            const SizedBox(height: 16),
            _SummaryRow(label: 'Subtotal', value: total.toStringAsFixed(2)),
            _SummaryRow(
              label: 'Discount',
              value: '-${discount.toStringAsFixed(2)}',
              color: AppColors.error,
            ),
            if (roundOff != 0)
              _SummaryRow(
                label: 'Round Off',
                value:
                    '${roundOff > 0 ? '+' : ''}${roundOff.toStringAsFixed(2)}',
              ),
            const Divider(),
            _SummaryRow(
              label: 'Net Payable',
              value: (total - discount + roundOff).toStringAsFixed(2),
              isBold: true,
            ),
            const SizedBox(height: 8),
            _SummaryRow(
              label: 'Paid Amount',
              value: paid.toStringAsFixed(2),
              color: AppColors.primary,
            ),
            if (changeReturned > 0)
              _SummaryRow(
                label: 'Change Returned',
                value: changeReturned.toStringAsFixed(2),
                color: Colors.green,
              ),
            _SummaryRow(
              label: 'Due Amount',
              value: due.toStringAsFixed(2),
              color: due > 0 ? AppColors.error : Colors.grey,
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderInfo extends StatelessWidget {
  final String label;
  final String value;

  const _HeaderInfo({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;
  final Color? color;

  const _SummaryRow({
    required this.label,
    required this.value,
    this.isBold = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              fontSize: isBold ? 16 : 14,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              fontSize: isBold ? 16 : 14,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
