import 'barcode_lookup_service.dart';
import 'product_index_service.dart';

enum ProductSource {
  /// Local index built from the supermarket price files.
  priceIndex,
  openFoodFacts,

  /// Both sources: the Hebrew name from the index, the photo from OFF.
  combined,
  none,
}

class ResolvedProduct {
  ResolvedProduct({
    required this.name,
    required this.source,
    this.imageUrl,
    this.price,
  });

  final String name;
  final ProductSource source;
  final String? imageUrl;
  final double? price;

  String get sourceLabel => switch (source) {
        ProductSource.priceIndex => 'מדד מחירים',
        ProductSource.openFoodFacts => 'Open Food Facts',
        ProductSource.combined => 'מדד מחירים + תמונה מ-OFF',
        ProductSource.none => 'לא זוהה',
      };
}

/// Resolves a barcode against every source available, best first.
///
/// The local price index wins on names: it is instant, in Hebrew, and covers
/// household goods Open Food Facts has no idea about. Open Food Facts is still
/// worth asking, because it is the only one of the two with photos.
///
/// Duplicated from desktop_scanner's copy — see its CLAUDE.md note on
/// duplication.
class ProductResolver {
  ProductResolver({required this.index, BarcodeLookupService? lookup})
      : _lookup = lookup ?? BarcodeLookupService();

  final ProductIndexService index;
  final BarcodeLookupService _lookup;

  Future<ResolvedProduct?> resolve(String barcode) async {
    final indexed = index.lookup(barcode);
    final online = await _lookup.lookup(barcode);

    if (indexed != null) {
      return ResolvedProduct(
        name: indexed.name,
        // The index has no photos, so borrow one when OFF happens to know the
        // product too.
        imageUrl: online?.imageUrl,
        price: indexed.price,
        source: online?.imageUrl != null
            ? ProductSource.combined
            : ProductSource.priceIndex,
      );
    }

    if (online != null) {
      return ResolvedProduct(
        name: online.displayName,
        imageUrl: online.imageUrl,
        source: ProductSource.openFoodFacts,
      );
    }

    return null;
  }
}
