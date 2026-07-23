import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../firebase_config.dart';
import '../models/inventory_item.dart';
import 'auth_service.dart';
import 'rest_value.dart';

/// Firestore access over the REST API, scoped to a single household — the
/// desktop counterpart of the mobile app's `FirestoreService`.
///
/// Writes go to `households/{id}/items`, the same collection the phone reads,
/// so a scan here shows up there immediately.
class FirestoreService {
  FirestoreService(this.auth);

  final AuthService auth;

  Future<Map<String, String>> _headers() async => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${await auth.idToken()}',
      };

  Uri _uri(String path, [Map<String, dynamic>? query]) =>
      Uri.parse('${FirebaseConfig.firestoreBase}/$path').replace(
        queryParameters: query?.map((k, v) => MapEntry(k, v)),
      );

  /// Fully-qualified document name, as `:commit` writes require.
  String _itemPath(String householdId, String itemId) =>
      '${FirebaseConfig.documentsPath}/households/$householdId/items/$itemId';

  /// Firestore's own auto-ID format: 20 characters of base62. Generated
  /// client-side because `:commit` needs the document name up front, unlike
  /// createDocument which can allocate one.
  static String _autoId() {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    return List.generate(20, (_) => chars[random.nextInt(chars.length)]).join();
  }

  /// Runs a batch of writes through `documents:commit`, the only endpoint that
  /// supports field transforms — server timestamps and atomic increments.
  /// Returns the `writeResults` so callers can read transform outputs back.
  Future<List<dynamic>> _commit(List<Map<String, dynamic>> writes) async {
    final response = await http.post(
      _uri(':commit'),
      headers: await _headers(),
      body: jsonEncode({'writes': writes}),
    );

    if (response.statusCode != 200) {
      throw Exception(_errorMessage(response));
    }
    return (jsonDecode(response.body) as Map<String, dynamic>)['writeResults']
            as List? ??
        const [];
  }

  static Map<String, dynamic> _serverTimestamp(String fieldPath) => {
        'fieldPath': fieldPath,
        'setToServerValue': 'REQUEST_TIME',
      };

  /// Reads a household document. Returns null when the ID doesn't exist, which
  /// is how the settings screen validates a pasted invite code.
  Future<Map<String, dynamic>?> getHousehold(String householdId) async {
    final response =
        await http.get(_uri('households/$householdId'), headers: await _headers());

    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw Exception('קריאת הבית נכשלה: ${_errorMessage(response)}');
    }
    return (jsonDecode(response.body) as Map<String, dynamic>)['fields']
        as Map<String, dynamic>?;
  }

  /// Adds this machine's uid to the household's `members` list. Required before
  /// any item read/write: the security rules check membership on every request.
  ///
  /// The rules only permit a non-member to update the document if the result
  /// includes them in `members`, so the list is read first and re-sent whole.
  Future<String> joinHousehold(String householdId) async {
    final fields = await getHousehold(householdId);
    if (fields == null) throw Exception('קוד הזמנה לא נמצא');

    final uid = auth.uid;
    if (uid == null) throw Exception('לא מחובר');

    final members = decodeStringList(
        fields['members'] as Map<String, dynamic>?);
    if (!members.contains(uid)) members.add(uid);

    final response = await http.patch(
      _uri('households/$householdId', {
        'updateMask.fieldPaths': ['members', 'memberProfiles.$uid'],
      }),
      headers: await _headers(),
      body: jsonEncode({
        'fields': {
          'members': encodeStringList(members),
          'memberProfiles.$uid': {
            'mapValue': {
              'fields': {
                'displayName': encodeString('סורק שולחני'),
                'email': {'nullValue': null},
                'isAnonymous': encodeBool(true),
              }
            }
          },
        }
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('ההצטרפות לבית נכשלה: ${_errorMessage(response)}');
    }
    return householdId;
  }

  String householdName(Map<String, dynamic>? fields) =>
      decodeString(fields?['name'] as Map<String, dynamic>?) ?? 'הבית שלי';

  Future<InventoryItem?> findItemByBarcode(
      String householdId, String barcode) async {
    final results = await _runQuery(householdId, {
      'from': [
        {'collectionId': 'items'}
      ],
      'where': {
        'fieldFilter': {
          'field': {'fieldPath': 'barcode'},
          'op': 'EQUAL',
          'value': {'stringValue': barcode},
        }
      },
      'limit': 1,
    });
    return results.isEmpty ? null : results.first;
  }

  Future<List<InventoryItem>> recentItems(String householdId,
      {int limit = 20}) async {
    return _runQuery(householdId, {
      'from': [
        {'collectionId': 'items'}
      ],
      'orderBy': [
        {
          'field': {'fieldPath': 'addedAt'},
          'direction': 'DESCENDING'
        }
      ],
      'limit': limit,
    });
  }

  Future<List<InventoryItem>> _runQuery(
      String householdId, Map<String, dynamic> structuredQuery) async {
    final response = await http.post(
      _uri('households/$householdId:runQuery'),
      headers: await _headers(),
      body: jsonEncode({'structuredQuery': structuredQuery}),
    );

    if (response.statusCode != 200) {
      throw Exception('שאילתת המלאי נכשלה: ${_errorMessage(response)}');
    }

    final rows = jsonDecode(response.body) as List;
    return rows
        .map((row) => (row as Map<String, dynamic>)['document'])
        .whereType<Map<String, dynamic>>()
        .map((doc) => InventoryItem.fromRest(
            doc['name'] as String, doc['fields'] as Map<String, dynamic>))
        .toList();
  }

  Future<String> addItem(String householdId, InventoryItem item) async {
    final itemId = _autoId();
    try {
      await _commit([
        {
          'update': {
            'name': _itemPath(householdId, itemId),
            'fields': item.toRestFields(),
          },
          'updateTransforms': [
            _serverTimestamp('addedAt'),
            _serverTimestamp('updatedAt'),
          ],
          // Guards against the (vanishingly unlikely) auto-ID collision.
          'currentDocument': {'exists': false},
        }
      ]);
    } catch (e) {
      throw Exception('הוספת המוצר נכשלה: ${_bare(e)}');
    }
    return itemId;
  }

  /// Overwrites the editable fields of an existing item. `addedAt` is left
  /// alone so the item keeps its original position in the mobile app's list.
  Future<void> updateItem(String householdId, InventoryItem item) async {
    final fields = item.toRestFields();
    try {
      await _commit([
        {
          'update': {
            'name': _itemPath(householdId, item.id!),
            'fields': fields,
          },
          'updateMask': {'fieldPaths': fields.keys.toList()},
          'updateTransforms': [_serverTimestamp('updatedAt')],
          'currentDocument': {'exists': true},
        }
      ]);
    } catch (e) {
      throw Exception('עדכון המוצר נכשל: ${_bare(e)}');
    }
  }

  /// Atomically bumps an item's quantity and returns the server's resulting
  /// value.
  ///
  /// Read-modify-write would lose a scan whenever the phone and the desktop
  /// touch the same item at once, so the increment is done as a field transform
  /// — the server applies it, not this client.
  Future<double> incrementQuantity(
      String householdId, String itemId, double delta) async {
    final List<dynamic> results;
    try {
      results = await _commit([
        {
          'transform': {
            'document': _itemPath(householdId, itemId),
            'fieldTransforms': [
              {
                'fieldPath': 'quantity',
                'increment': {'doubleValue': delta},
              },
              _serverTimestamp('updatedAt'),
            ],
          },
          'currentDocument': {'exists': true},
        }
      ]);
    } catch (e) {
      throw Exception('עדכון הכמות נכשל: ${_bare(e)}');
    }

    final transformResults =
        (results.firstOrNull as Map<String, dynamic>?)?['transformResults']
            as List?;
    final quantity = decodeDouble(
        transformResults?.firstOrNull as Map<String, dynamic>?);
    if (quantity == null) {
      throw Exception('עדכון הכמות נכשל: השרת לא החזיר כמות');
    }
    return quantity;
  }

  /// Deletes an item document outright.
  Future<void> deleteItem(String householdId, String itemId) async {
    try {
      await _commit([
        {
          'delete': _itemPath(householdId, itemId),
          'currentDocument': {'exists': true},
        }
      ]);
    } catch (e) {
      throw Exception('מחיקת המוצר נכשלה: ${_bare(e)}');
    }
  }

  static String _bare(Object error) =>
      error.toString().replaceFirst('Exception: ', '');

  static String _errorMessage(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      final error = body is List ? body.first['error'] : body['error'];
      return error?['message']?.toString() ?? response.body;
    } catch (_) {
      return 'HTTP ${response.statusCode}';
    }
  }
}
