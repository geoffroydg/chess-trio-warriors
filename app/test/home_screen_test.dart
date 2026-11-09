import 'package:flutter/material.dart';
import 'package:chesstrio/app.dart';
import 'package:chesstrio/services/storage.dart';
import 'package:chesstrio/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('écran d\'accueil : titre, pseudo mémorisé, boutons', (tester) async {
    SharedPreferences.setMockInitialValues({'pseudo': 'Ana'});
    final storage = await Storage.open();
    final app = AppState(storage: storage);
    await app.init();
    await tester.pumpWidget(ChessTrioApp(appState: app));
    await tester.pumpAndSettle();

    expect(find.text('Chess Trio Warriors'), findsOneWidget);
    expect(find.text('Jouer seul'), findsOneWidget);
    expect(find.text('Créer un salon'), findsOneWidget);
    expect(find.text('Rejoindre'), findsOneWidget);
    expect(find.text('Ana'), findsOneWidget);

    // Sans pseudo, on est prévenu.
    await tester.enterText(find.byType(EditableText).first, '');
    await tester.tap(find.text('Créer un salon'));
    await tester.pump();
    expect(find.text('Choisis d\'abord un pseudo.'), findsOneWidget);

    // Avec pseudo, on arrive sur la création de salon.
    await tester.enterText(find.byType(EditableText).first, 'Bob');
    await tester.tap(find.text('Créer un salon'));
    await tester.pumpAndSettle();
    expect(find.text('Premier mat'), findsOneWidget);
    expect(find.text('Deux mats'), findsOneWidget);
    expect(app.pseudo, 'Bob');
  });
}
