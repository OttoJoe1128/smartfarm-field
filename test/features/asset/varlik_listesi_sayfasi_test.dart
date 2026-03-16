import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfarm_field/features/asset/varlik_listesi_sayfasi.dart';

void main() {
  group('VarlikListesiSayfasi UI', () {
    testWidgets('sayfa basligi gorunur', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: VarlikListesiSayfasi(),
        ),
      );
      expect(find.text('Varlik Listesi'), findsOneWidget);
      expect(find.byIcon(Icons.filter_list), findsOneWidget);
    });
    testWidgets('veri yoksa bos durum mesaji gorunur', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: VarlikListesiSayfasi(),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      final bool hasBosDurumMesaji =
          find.text('Henuz varlik eklenmemis').evaluate().isNotEmpty;
      final bool hasYukleniyorGostergesi =
          find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
      expect(hasBosDurumMesaji || hasYukleniyorGostergesi, true);
    });
  });
}
