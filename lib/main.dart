import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import 'core/storage/project_repository.dart';
import 'features/editor/editor_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final documents = await getApplicationDocumentsDirectory();
  final projectsDir = Directory(
    '${documents.path}${Platform.pathSeparator}projects',
  );
  runApp(
    ProviderScope(
      overrides: [
        projectRepositoryProvider.overrideWithValue(
          ProjectRepository(projectsDir),
        ),
      ],
      child: const LaqtaApp(),
    ),
  );
}

class LaqtaApp extends StatelessWidget {
  const LaqtaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'لقطة',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF4D2E),
          brightness: Brightness.dark,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

/// Start screen. Lists saved projects once project storage lands (v0.1).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('لقطة')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.movie_creation_outlined,
              size: 72,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text('لا توجد مشاريع بعد', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'ابدأ مشروعك الأول بقصّ ودمج مقاطعك',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
