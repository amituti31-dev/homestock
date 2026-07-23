/// Encoding/decoding helpers for the Firestore REST API's typed value format.
///
/// The REST API represents every field as a single-key object describing its
/// type (`{"stringValue": "x"}`), unlike the `cloud_firestore` plugin which
/// takes plain Dart values. These helpers keep that noise out of the models.
library;

Map<String, dynamic> encodeString(String? v) =>
    v == null ? {'nullValue': null} : {'stringValue': v};

Map<String, dynamic> encodeDouble(double? v) =>
    v == null ? {'nullValue': null} : {'doubleValue': v};

Map<String, dynamic> encodeBool(bool v) => {'booleanValue': v};

/// Firestore requires RFC 3339 in UTC.
Map<String, dynamic> encodeTimestamp(DateTime? v) => v == null
    ? {'nullValue': null}
    : {'timestampValue': v.toUtc().toIso8601String()};

Map<String, dynamic> encodeStringList(List<String> values) => {
      'arrayValue': {
        'values': values.map((v) => {'stringValue': v}).toList(),
      }
    };

String? decodeString(Map<String, dynamic>? field) =>
    field == null ? null : field['stringValue'] as String?;

/// Firestore stores whole numbers written as doubles back as `integerValue`,
/// so both spellings have to be accepted on read.
double? decodeDouble(Map<String, dynamic>? field) {
  if (field == null) return null;
  final d = field['doubleValue'];
  if (d != null) return (d as num).toDouble();
  final i = field['integerValue'];
  if (i != null) return double.parse(i.toString());
  return null;
}

DateTime? decodeTimestamp(Map<String, dynamic>? field) {
  final raw = field?['timestampValue'] as String?;
  return raw == null ? null : DateTime.parse(raw).toLocal();
}

List<String> decodeStringList(Map<String, dynamic>? field) {
  final values = field?['arrayValue']?['values'] as List?;
  if (values == null) return [];
  return values
      .map((v) => (v as Map)['stringValue'] as String?)
      .whereType<String>()
      .toList();
}

/// Last path segment of a REST document `name` — the document ID.
String documentId(String name) => name.split('/').last;
