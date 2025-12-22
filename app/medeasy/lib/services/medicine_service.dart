import 'dart:convert';

import '../core/http_client.dart';
import '../models/medicine.dart';

class MedicineService {
  Future<List<Medicine>> search(String token, {String query = ''}) async {
    final client = ApiClient(token: token);
    final response =
        await client.get('/medicines', params: query.isEmpty ? null : {'query': query});
    if (response.statusCode != 200) {
      throw ApiError('Unable to fetch medicines');
    }
    final data = jsonDecode(response.body) as List<dynamic>;
    return data.map((e) => Medicine.fromJson(e as Map<String, dynamic>)).toList();
  }
}
