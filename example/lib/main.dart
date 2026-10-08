import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/map_screen.dart';
import 'state/alert_controller.dart';
import 'state/permission_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MapZoneSpeedAlertExampleApp());
}

/// App root. State is split into two focused [ChangeNotifier]s provided at the
/// top of the tree:
///   - [AlertController]      → the speed-alert engine, streams and voice.
///   - [PermissionController] → runtime location / notification permissions.
class MapZoneSpeedAlertExampleApp extends StatelessWidget {
  const MapZoneSpeedAlertExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AlertController()..init()),
        ChangeNotifierProvider(create: (_) => PermissionController()..refresh()),
      ],
      child: MaterialApp(
        title: 'MapZone Speed Alert',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        home: const MapScreen(),
      ),
    );
  }
}
