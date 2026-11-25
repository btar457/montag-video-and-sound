import 'package:material_ui/material_ui.dart';

void main() {
  runApp(const LaqtaApp());
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
