import 'package:flutter/foundation.dart';

import '../models/medicine.dart';
import '../services/medicine_service.dart';

class MedicineProvider extends ChangeNotifier {
  final _service = MedicineService();

  List<Medicine> _results = [];
  bool _loading = false;
  String? _error;

  List<Medicine> get results => _results;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> search({required String token, String query = ''}) async {
    _loading = true;
    notifyListeners();
    try {
      _results = await _service.search(token, query: query);
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
