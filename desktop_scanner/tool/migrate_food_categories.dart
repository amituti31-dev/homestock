// One-off migration: re-classifies existing items with category: "food"
// into the new food subcategories (dairy, meatFish, vegetablesFruits, ...)
// using the same keyword rules as CategoryClassifier, now that "food" is a
// catch-all rather than the only food bucket.
//
// Self-contained (doesn't import category_classifier.dart or
// inventory_category.dart) because those pull in flutter/material.dart ->
// dart:ui, which isn't available under plain `dart run` — see
// import_price_file.dart for the same constraint. The keyword lists here
// must stay in sync with lib/services/category_classifier.dart.
//
// Reuses this machine's already-authenticated desktop_scanner session
// (the cached refresh token in shared_preferences.json) rather than signing
// up a fresh anonymous user, since a fresh user wouldn't be a household
// member and every item read/write is gated on membership.
//
// Usage:
//   dart run tool/migrate_food_categories.dart            # dry run, prints only
//   dart run tool/migrate_food_categories.dart --apply    # writes the changes
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const _projectId = 'home-inventory-32dd1';
const _apiKey = 'AIzaSyA3HRxJe36Z3ngQMa0FK5vE4UO4Ht7-9lE';
const _documentsPath = 'projects/$_projectId/databases/(default)/documents';
const _firestoreBase = 'https://firestore.googleapis.com/v1/$_documentsPath';

// Order matters: checked top-to-bottom, first match wins. Must match
// lib/services/category_classifier.dart exactly.
const _rules = <String, List<String>>{
  'dairy': [
    'חלב', 'גבינ', 'יוגורט', 'שמנת', 'חמאה', 'קוטג\'', 'קפיר',
    'מעדן חלב', 'קצפת',
  ],
  'meatFish': [
    'בשר', 'עוף', 'הודו', 'נקניק', 'סלמון', 'טונה', 'דג ', 'דגים', 'כבד',
    'קציצות', 'המבורגר', 'שניצל', 'פסטרמה', 'סלמי', 'בקר', 'כבש', 'פילה',
    'סטייק', 'צלי',
  ],
  'beverages': [
    'מיץ', 'משקה קל', 'קולה', 'סודה', 'בקבוק מים', 'מים מינרל', 'בירה',
    'יין', 'ליקר', 'משקה אנרגי', 'נביעות', 'סירופ מייפל',
  ],
  'frozen': [
    'קפוא', 'קפואה', 'קפואים', 'גלידה', 'גלידת',
  ],
  'spicesSauces': [
    'תבלין', 'רוטב', 'קטשופ', 'מיונז', 'חרדל', 'שמן זית', 'חומץ',
    'אבקת קארי', 'זעתר', 'פפריקה', 'כמון', 'קארי', 'קימל', 'אורגנו', 'ממרח',
  ],
  'cannedDry': [
    'שימור', 'פסטה', 'אורז', 'קטני', 'עדשים', 'חומוס יבש', 'קמח', 'סוכר',
    'מלח', 'דגני בוקר', 'גרעיני', 'קינואה', 'בורגול', 'שעועית',
  ],
  'vegetablesFruits': [
    'עגבני', 'מלפפון', 'תפוח אדמה', 'תפוח עץ', 'בננה', 'גזר', 'בצל', 'חסה',
    'פלפל', 'אבוקדו', 'לימון', 'תפוז', 'ענבים', 'אבטיח', 'מלון',
    ' שום', 'שום ',
    'פטריות', 'ירק ', 'ירקות', 'פרי ', 'פירות', 'תות', 'אגס', 'אפרסק',
  ],
  'snacks': [
    'חטיף', 'במבה', 'ביסלי', 'צ\'יפס', 'עוגי', 'שוקולד', 'ממתק', 'סוכריה',
    'סוכריות', 'וופל', 'קרקר', 'פופקורן', 'חטיפי',
  ],
  'breadBakery': [
    'לחם', 'פיתה', 'בגט', 'לחמניה', 'חלה', 'מאפה', 'קרואסון', 'עוגה',
    'בורקס', 'לחמניות',
  ],
};

String? _classify(String name) {
  final normalized = name.trim();
  for (final entry in _rules.entries) {
    if (entry.value.any((keyword) => normalized.contains(keyword))) {
      return entry.key;
    }
  }
  return null; // stays "food" — nothing more specific matched
}

Future<void> main(List<String> args) async {
  final apply = args.contains('--apply');

  final prefsFile = File(
      '${Platform.environment['APPDATA']}\\HomeStock\\HomeStock Scanner\\shared_preferences.json');
  if (!prefsFile.existsSync()) {
    stderr.writeln('No cached session at ${prefsFile.path} — run the '
        'desktop app at least once on this machine first.');
    exit(1);
  }
  final prefs = jsonDecode(prefsFile.readAsStringSync()) as Map<String, dynamic>;
  final refreshToken = prefs['flutter.firebase_refresh_token'] as String?;
  final householdId = prefs['flutter.household_id'] as String?;
  if (refreshToken == null || householdId == null) {
    stderr.writeln('Cached session is missing a refresh token or household id.');
    exit(1);
  }

  stdout.writeln('Household: $householdId');
  stdout.writeln(apply ? 'Mode: APPLY (writing changes)' : 'Mode: DRY RUN (pass --apply to write)');
  stdout.writeln('');

  final tokenResponse = await http.post(
    Uri.parse('https://securetoken.googleapis.com/v1/token?key=$_apiKey'),
    headers: {'Content-Type': 'application/x-www-form-urlencoded'},
    body: {'grant_type': 'refresh_token', 'refresh_token': refreshToken},
  );
  if (tokenResponse.statusCode != 200) {
    stderr.writeln('Token refresh failed: ${tokenResponse.body}');
    exit(1);
  }
  final idToken =
      (jsonDecode(tokenResponse.body) as Map<String, dynamic>)['id_token'] as String;
  final headers = {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $idToken',
  };

  final queryResponse = await http.post(
    Uri.parse('$_firestoreBase/households/$householdId:runQuery'),
    headers: headers,
    body: jsonEncode({
      'structuredQuery': {
        'from': [
          {'collectionId': 'items'}
        ],
        'where': {
          'fieldFilter': {
            'field': {'fieldPath': 'category'},
            'op': 'EQUAL',
            'value': {'stringValue': 'food'},
          }
        },
      }
    }),
  );
  if (queryResponse.statusCode != 200) {
    stderr.writeln('Query failed: ${queryResponse.body}');
    exit(1);
  }

  final rows = jsonDecode(queryResponse.body) as List;
  final docs = rows
      .map((row) => (row as Map<String, dynamic>)['document'])
      .whereType<Map<String, dynamic>>()
      .toList();

  stdout.writeln('Found ${docs.length} item(s) tagged "food".\n');

  final writes = <Map<String, dynamic>>[];
  var unchanged = 0;
  for (final doc in docs) {
    final docName = doc['name'] as String;
    final fields = doc['fields'] as Map<String, dynamic>;
    final name = (fields['name']?['stringValue'] as String?) ?? '';
    final newCategory = _classify(name);

    if (newCategory == null) {
      unchanged++;
      continue;
    }

    stdout.writeln('$name: food -> $newCategory');
    writes.add({
      'update': {
        'name': docName,
        'fields': {
          'category': {'stringValue': newCategory},
        },
      },
      'updateMask': {
        'fieldPaths': ['category']
      },
      'currentDocument': {'exists': true},
    });
  }

  stdout.writeln('\n${writes.length} item(s) to reclassify, $unchanged staying "food".');

  if (!apply) {
    stdout.writeln('\nDry run only — re-run with --apply to write these changes.');
    return;
  }
  if (writes.isEmpty) {
    stdout.writeln('\nNothing to write.');
    return;
  }

  final commitResponse = await http.post(
    Uri.parse('$_firestoreBase:commit'),
    headers: headers,
    body: jsonEncode({'writes': writes}),
  );
  if (commitResponse.statusCode != 200) {
    stderr.writeln('\nCommit failed: ${commitResponse.body}');
    exit(1);
  }
  stdout.writeln('\nDone — ${writes.length} item(s) updated.');
}
