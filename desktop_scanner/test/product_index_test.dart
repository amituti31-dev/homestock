import 'package:desktop_scanner/services/product_index_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Trimmed to the fields the index needs, but the element names and nesting
/// match a real Shufersal PriceFull file.
const _priceFileXml = '''
<?xml version="1.0" encoding="utf-8"?>
<root>
  <ChainId>7290027600007</ChainId>
  <StoreId>001</StoreId>
  <Items Count="3">
    <Item>
      <PriceUpdateDate>2026-07-20 03:00</PriceUpdateDate>
      <ItemCode>7290004127336</ItemCode>
      <ItemName>קוטג' 9%</ItemName>
      <ManufacturerName>תנובה</ManufacturerName>
      <ItemPrice>7.90</ItemPrice>
    </Item>
    <Item>
      <ItemCode>10900302814</ItemCode>
      <ItemName>ניילון נצמד 30ס"מ*30 מטר</ItemName>
      <ManufacturerName></ManufacturerName>
      <ItemPrice>10.00</ItemPrice>
    </Item>
    <Item>
      <ItemCode>99999999</ItemCode>
      <ItemName></ItemName>
      <ItemPrice>1.00</ItemPrice>
    </Item>
  </Items>
</root>
''';

void main() {
  group('ProductIndexService.parsePriceFile', () {
    final products = ProductIndexService.parsePriceFile(_priceFileXml);

    test('indexes products by barcode', () {
      expect(products.keys, containsAll(['7290004127336', '10900302814']));
    });

    test('keeps the Hebrew name, manufacturer and price', () {
      final cottage = products['7290004127336']!;
      expect(cottage.name, 'קוטג\' 9%');
      expect(cottage.manufacturer, 'תנובה');
      expect(cottage.price, 7.90);
    });

    test('covers non-food products, which Open Food Facts does not', () {
      expect(products['10900302814']!.name, 'ניילון נצמד 30ס"מ*30 מטר');
    });

    test('treats an empty manufacturer as absent', () {
      expect(products['10900302814']!.manufacturer, isNull);
    });

    test('skips entries with no name rather than indexing a blank', () {
      expect(products.containsKey('99999999'), isFalse);
    });

    test('does not carry fields over from the previous item', () {
      // The third item has no ManufacturerName element at all; if parser state
      // leaked it would inherit "תנובה" from the first.
      final leaked = products.values.where((p) => p.manufacturer == 'תנובה');
      expect(leaked.length, 1);
    });
  });

  group('IndexedProduct JSON', () {
    test('round-trips through the on-disk cache format', () {
      final original =
          IndexedProduct(name: 'במבה', manufacturer: 'אסם', price: 4.5);
      final restored = IndexedProduct.fromJson(original.toJson());

      expect(restored.name, 'במבה');
      expect(restored.manufacturer, 'אסם');
      expect(restored.price, 4.5);
    });

    test('omits absent optional fields instead of writing nulls', () {
      expect(IndexedProduct(name: 'x').toJson(), {'n': 'x'});
    });
  });
}
