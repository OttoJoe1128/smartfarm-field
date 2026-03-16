import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfarm_field/features/auth/saha_giris_sayfasi.dart';

void main() {
  group('SahaGirisSayfasi UI', () {
    testWidgets('temel bilesenler gorunur', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SahaGirisSayfasi(
            onLoginSuccess: () {},
          ),
        ),
      );
      expect(find.text('SmartFarm Field'), findsOneWidget);
      expect(find.text('Saha Veri Toplama'), findsOneWidget);
      expect(find.text('E-posta'), findsOneWidget);
      expect(find.text('Sifre'), findsOneWidget);
      expect(find.text('Giris Yap'), findsOneWidget);
    });
    testWidgets('bos formda dogrulama mesaji gosterir', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SahaGirisSayfasi(
            onLoginSuccess: () {},
          ),
        ),
      );
      await tester.tap(find.text('Giris Yap'));
      await tester.pumpAndSettle();
      expect(find.text('E-posta adresi giriniz'), findsOneWidget);
      expect(find.text('Sifre giriniz'), findsOneWidget);
    });
    testWidgets('gecersiz eposta formatinda uyari gosterir', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SahaGirisSayfasi(
            onLoginSuccess: () {},
          ),
        ),
      );
      await tester.enterText(find.byType(TextFormField).first, 'ornek_eposta');
      await tester.enterText(find.byType(TextFormField).last, '123456');
      await tester.tap(find.text('Giris Yap'));
      await tester.pumpAndSettle();
      expect(find.text('Gecerli bir e-posta adresi giriniz'), findsOneWidget);
    });
    testWidgets('sifre gorunurluk ikonu obscureText degerini degistirir', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SahaGirisSayfasi(
            onLoginSuccess: () {},
          ),
        ),
      );
      final Finder inputAlanlari = find.byType(EditableText);
      final EditableText ilkDurumSifreInput = tester.widgetList<EditableText>(inputAlanlari).last;
      expect(ilkDurumSifreInput.obscureText, true);
      await tester.tap(find.byIcon(Icons.visibility));
      await tester.pumpAndSettle();
      final EditableText guncelSifreInput = tester.widgetList<EditableText>(inputAlanlari).last;
      expect(guncelSifreInput.obscureText, false);
    });
  });
}
