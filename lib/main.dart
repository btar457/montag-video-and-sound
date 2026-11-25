import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import 'core/media/media_cleanup.dart';
import 'core/media/media_library.dart';
import 'core/storage/project_repository.dart';
import 'core/storage/temp_files.dart';
import 'features/editor/editor_controller.dart';
import 'features/export/export_screen.dart';
import 'features/home/home_screen.dart';
import 'features/import/import_service.dart';

/// Folders inside the app's private documents directory.
const projectsFolder = 'projects';
const mediaFolder = 'media';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final documents = await getApplicationDocumentsDirectory();
  final cache = await getTemporaryDirectory(); // where the picker puts copies
  String inDocuments(String name) =>
      '${documents.path}${Platform.pathSeparator}$name';

  final projects = ProjectRepository(Directory(inDocuments(projectsFolder)));
  final media = MediaLibrary(
    Directory(inDocuments(mediaFolder)),
    movableFrom: cache,
  );

  // Must match ExportHandler.kt, which only writes inside cache/exports.
  final exports = Directory('${cache.path}${Platform.pathSeparator}exports');

  try {
    await cleanUnusedMedia(projects, media);
    // Renders are temporary: leftovers from earlier runs (finished or cut
    // short when the app was killed) are not needed any more.
    await clearFiles(exports);
  } catch (_) {
    // Cleanup is best-effort; never block the app from starting.
  }

  runApp(
    ProviderScope(
      overrides: [
        projectRepositoryProvider.overrideWithValue(projects),
        mediaLibraryProvider.overrideWithValue(media),
        exportDirectoryProvider.overrideWithValue(exports),
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
