import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml_events.dart';

/// A product as published in the price-transparency files.
class IndexedProduct {
  IndexedProduct({required this.name, this.manufacturer, this.price});

  final String name;
  final String? manufacturer;
  final double? price;

  Map<String, dynamic> toJson() => {
        'n': name,
        if (manufacturer != null) 'm': manufacturer,
        if (price != null) 'p': price,
      };

  factory IndexedProduct.fromJson(Map<String, dynamic> json) => IndexedProduct(
        name: json['n'] as String,
        manufacturer: json['m'] as String?,
        price: (json['p'] as num?)?.toDouble(),
      );
}

/// A local barcode → product index built from Israeli supermarket price files.
///
/// Israeli chains are required to publish their full catalogue, barcodes and
/// Hebrew names included. That covers household goods Open Food Facts knows
/// nothing about, so it is consulted *before* the network lookup — and being
/// local, it also makes the common case instant.
///
/// Shufersal is used because its files are served without a login. Other chains
/// publish the same XML schema behind per-chain credentials; adding one means
/// adding a downloader, not a new parser.
class ProductIndexService {
  static const _catalogueUrl =
      'https://prices.shufersal.co.il/FileObject/UpdateCategory?catID=2&storeId=0';
  static const _indexFileName = 'product_index.json';
  static const _userAgent = 'HomeStock-DesktopScanner/1.0';

  /// The catalogue barely moves day to day, and the download is a few hundred
  /// KB, so a weekly refresh is plenty.
  static const refreshInterval = Duration(days: 7);

  Map<String, IndexedProduct> _index = {};
  DateTime? _updatedAt;

  int get size => _index.length;
  DateTime? get updatedAt => _updatedAt;
  bool get isStale =>
      _updatedAt == null ||
      DateTime.now().difference(_updatedAt!) > refreshInterval;

  IndexedProduct? lookup(String barcode) => _index[barcode];

  Future<File> _indexFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}$_indexFileName');
  }

  /// Loads the cached index from disk. Safe to call on a cold start — a missing
  /// or corrupt cache just leaves the index empty.
  Future<void> load() async {
    try {
      final file = await _indexFile();
      if (!await file.exists()) return;

      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      _updatedAt = DateTime.tryParse(data['updatedAt'] as String? ?? '');
      _index = (data['products'] as Map<String, dynamic>).map(
        (barcode, json) => MapEntry(
            barcode, IndexedProduct.fromJson(json as Map<String, dynamic>)),
      );
    } catch (_) {
      _index = {};
      _updatedAt = null;
    }
  }

  Future<void> _save() async {
    final file = await _indexFile();
    await file.writeAsString(jsonEncode({
      'updatedAt': _updatedAt?.toIso8601String(),
      'products': _index.map((k, v) => MapEntry(k, v.toJson())),
    }));
  }

  /// Downloads the newest Shufersal price file and merges it into the index.
  /// Barcodes from other chains (imported separately, e.g. via
  /// tool/import_price_file.dart) are kept — only barcodes present in this
  /// download are added or updated. Returns the total number of products in
  /// the index after the merge.
  Future<int> refresh() async {
    final fileUrl = await _newestPriceFileUrl();
    final response = await http
        .get(Uri.parse(fileUrl), headers: {'User-Agent': _userAgent})
        .timeout(const Duration(seconds: 90));

    if (response.statusCode != 200) {
      throw Exception('הורדת קובץ המחירים נכשלה (HTTP ${response.statusCode})');
    }

    // The published files are gzipped XML.
    final xml = utf8.decode(gzip.decode(response.bodyBytes), allowMalformed: true);
    final products = parsePriceFile(xml);
    if (products.isEmpty) {
      throw Exception('קובץ המחירים לא הכיל מוצרים');
    }

    _index.addAll(products);
    _updatedAt = DateTime.now();
    await _save();
    return _index.length;
  }

  /// Downloads the maintainer's pre-merged multi-chain index (product_index.json
  /// attached as a release asset — see CLAUDE.md) and merges it in. Used on a
  /// fresh machine's setup so it isn't limited to the plain weekly
  /// Shufersal-only refresh() that `refresh()` does on its own.
  ///
  /// Scans releases newest-first for the first one carrying the asset, rather
  /// than assuming the very latest release has it — the seed is attached
  /// manually and won't be present on every automated release. Returns the
  /// total number of products in the index after the merge.
  Future<int> downloadSeed() async {
    final response = await http.get(
      Uri.parse('https://api.github.com/repos/amituti31-dev/homestock/releases'),
      headers: {'User-Agent': _userAgent, 'Accept': 'application/vnd.github+json'},
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('רשימת הגרסאות לא זמינה (HTTP ${response.statusCode})');
    }

    final releases = jsonDecode(response.body) as List;
    final tagPattern = RegExp(r'^v\d+$');

    Map<String, dynamic>? seedAsset;
    for (final release in releases.cast<Map<String, dynamic>>()) {
      if (!tagPattern.hasMatch(release['tag_name'] as String? ?? '')) continue;
      final assets = (release['assets'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      seedAsset = assets.cast<Map<String, dynamic>?>().firstWhere(
            (a) => a?['name'] == _indexFileName,
            orElse: () => null,
          );
      if (seedAsset != null) break;
    }
    if (seedAsset == null) {
      throw Exception('לא נמצא מאגר מוצרים מוכן להורדה');
    }

    final seedResponse = await http
        .get(Uri.parse(seedAsset['browser_download_url'] as String),
            headers: {'User-Agent': _userAgent})
        .timeout(const Duration(seconds: 30));
    if (seedResponse.statusCode != 200) {
      throw Exception('הורדת המאגר נכשלה (HTTP ${seedResponse.statusCode})');
    }

    final data = jsonDecode(seedResponse.body) as Map<String, dynamic>;
    final seedProducts = (data['products'] as Map<String, dynamic>).map(
      (barcode, json) =>
          MapEntry(barcode, IndexedProduct.fromJson(json as Map<String, dynamic>)),
    );

    _index.addAll(seedProducts);
    _updatedAt ??= DateTime.now();
    await _save();
    return _index.length;
  }

  Future<String> _newestPriceFileUrl() async {
    final response = await http
        .get(Uri.parse(_catalogueUrl), headers: {'User-Agent': _userAgent})
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception('רשימת קבצי המחירים לא זמינה (HTTP ${response.statusCode})');
    }

    final match = RegExp(r'href="(https?://[^"]*?PriceFull[^"]*?)"')
        .firstMatch(response.body);
    if (match == null) {
      throw Exception('לא נמצא קובץ מחירים בעמוד');
    }
    // Links are HTML-escaped, and the blob URL's signature carries `&`.
    return match.group(1)!.replaceAll('&amp;', '&');
  }

  /// Parses the price-file XML into a barcode → product map.
  ///
  /// Uses the streaming event parser: these files reach ~5 MB of XML, and
  /// building a full document tree for a flat list of items is wasteful.
  static Map<String, IndexedProduct> parsePriceFile(String xml) {
    final products = <String, IndexedProduct>{};

    String? currentTag;
    String? code, name, manufacturer, price;

    void flush() {
      final barcode = code?.trim();
      final productName = name?.trim();
      if (barcode != null &&
          barcode.isNotEmpty &&
          productName != null &&
          productName.isNotEmpty) {
        products[barcode] = IndexedProduct(
          name: productName,
          manufacturer: manufacturer?.trim().isEmpty ?? true
              ? null
              : manufacturer!.trim(),
          price: double.tryParse(price?.trim() ?? ''),
        );
      }
      code = name = manufacturer = price = null;
    }

    for (final event in parseEvents(xml)) {
      if (event is XmlStartElementEvent) {
        currentTag = event.name;
      } else if (event is XmlTextEvent && currentTag != null) {
        switch (currentTag) {
          case 'ItemCode':
            code = event.value;
          case 'ItemName':
            name = event.value;
          case 'ManufacturerName':
            manufacturer = event.value;
          case 'ItemPrice':
            price = event.value;
        }
      } else if (event is XmlEndElementEvent) {
        if (event.name == 'Item') flush();
        currentTag = null;
      }
    }

    return products;
  }
}
