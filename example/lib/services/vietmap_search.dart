import 'dart:convert';

import 'package:http/http.dart' as http;

import '../env.dart';

/// One autocomplete suggestion from the VietMap search API.
class SearchResult {
  const SearchResult({required this.refId, required this.display});
  final String refId;
  final String display;
}

/// Thin client over the VietMap search / autocomplete API (v4).
///
/// - `GET /autocomplete/v4?apikey=KEY&text=<q>` → suggestions
/// - `GET /place/v4?apikey=KEY&refid=<ref_id>` → lat/lng
class VietmapSearch {
  static const String _base = 'https://maps.vietmap.vn/api';

  /// Autocomplete a free-text query into a list of suggestions.
  static Future<List<SearchResult>> autocomplete(String text) async {
    if (text.trim().isEmpty) return const [];
    final uri = Uri.parse('$_base/autocomplete/v4').replace(queryParameters: {
      'apikey': Env.vietmapApiKey,
      'text': text,
    });
    final res = await http.get(uri);
    if (res.statusCode != 200) return const [];
    final data = jsonDecode(res.body);
    if (data is! List) return const [];
    return data
        .map((e) => SearchResult(
              refId: (e['ref_id'] ?? '').toString(),
              display: (e['display'] ?? e['address'] ?? e['name'] ?? '').toString(),
            ))
        .where((r) => r.refId.isNotEmpty)
        .toList();
  }

  /// Resolve a suggestion `refId` into coordinates `[lat, lng]`, or null.
  static Future<List<double>?> place(String refId) async {
    final uri = Uri.parse('$_base/place/v4').replace(queryParameters: {
      'apikey': Env.vietmapApiKey,
      'refid': refId,
    });
    final res = await http.get(uri);
    if (res.statusCode != 200) return null;
    final data = jsonDecode(res.body);
    final lat = data is Map ? data['lat'] : null;
    final lng = data is Map ? data['lng'] : null;
    if (lat is num && lng is num) return [lat.toDouble(), lng.toDouble()];
    return null;
  }
}
