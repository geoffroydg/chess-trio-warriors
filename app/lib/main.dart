import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'services/notification_service.dart';
import 'services/storage.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(
      [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  final storage = await Storage.open();
  final notifications = NotificationService();
  final appState = AppState(storage: storage, notifications: notifications);
  await appState.init();
  runApp(ChessTrioApp(appState: appState));
  // Notifications et Firebase après le premier affichage (non bloquant, facultatif).
  notifications.init();
}
