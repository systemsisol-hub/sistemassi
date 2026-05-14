# Agent Guidelines for sistemassi

This document provides guidance for AI agents working with this Flutter/Dart codebase.

## Project Overview

- **Framework**: Flutter with Dart
- **Backend**: Supabase (PostgreSQL + Realtime)
- **Minimum SDK**: Dart 3.0.0
- **Target Platforms**: Android, iOS, Web
- **State Management**: StatefulWidget/StatelessWidget with Supabase streams
- **UI Language**: Spanish

## Build/Lint/Test Commands

```bash
# Analyze code for errors and warnings
flutter analyze

# Run all tests
flutter test

# Run a single test file
flutter test test/widget_test.dart

# Run tests with coverage
flutter test --coverage

# Build debug APK
flutter build apk --debug

# Build release APK
flutter build apk --release

# Build for web
flutter build web

# Build for iOS (macOS only)
flutter build ios

# Get dependencies
flutter pub get

# Update dependencies
flutter pub upgrade

# Clean and rebuild
flutter clean && flutter pub get

# Run with specific device
flutter run -d <device_id>

# List available devices
flutter devices

# Auto-fix analysis issues
dart fix --dry-run && dart fix --apply

# Generate icons
flutter pub run flutter_launcher_icons
```

## Code Style Guidelines

### Formatting
- 2 spaces for indentation
- Trailing commas for multi-line collections
- `const` constructors where possible
- Single quotes for strings
- `=>` for single-expression functions
- Border radius: `BorderRadius.circular(12)`

### Imports
```dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'main_navigation.dart';
import 'login_page.dart';
import 'services/notification_service.dart';
```

### Naming Conventions
| Type | Convention | Example |
|------|------------|---------|
| Classes | PascalCase | `AttendanceHubPage` |
| Variables | camelCase | `isLoading`, `currentUserId` |
| Private variables | _camelCase | `_permissions` |
| Files | snake_case | `attendance_hub_page.dart` |
| StatefulWidget State | _WidgetNameState | `_LoginPageState` |
| Functions | camelCase | `fetchData()` |

## Widget Patterns

### StatefulWidget with mounted check
```dart
class MyPage extends StatefulWidget {
  const MyPage({super.key});

  @override
  State<MyPage> createState() => _MyPageState();
}

class _MyPageState extends State<MyPage> {
  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      // async operations
    } catch (e) {
      debugPrint('Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ...
  }
}
```

### StatelessWidget for pure UI
```dart
class MyCard extends StatelessWidget {
  final String title;
  final VoidCallback? onTap;

  const MyCard({super.key, required this.title, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Text(title),
      ),
    );
  }
}
```

## Error Handling
```dart
try {
  await supabase.from('table').select().eq('id', id);
} on AuthException catch (e) {
  debugPrint('Auth error: ${e.message}');
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.message), backgroundColor: Colors.red),
    );
  }
} catch (e) {
  debugPrint('Unexpected error: $e');
  if (mounted) setState(() => _hasError = true);
}
```

## Supabase Patterns
```dart
// Query with error handling
final response = await Supabase.instance.client
    .from('profiles')
    .select('role, permissions')
    .eq('id', userId)
    .single();

// Real-time stream
Supabase.instance.client
    .from('notifications')
    .stream(primaryKey: ['id'])
    .eq('user_id', userId)
    .order('created_at', ascending: false);

// RPC call
await Supabase.instance.client.rpc('function_name', params: {
  'param1': value1,
});
```

## Theme & Styling
- Primary: `Color(0xFF344092)` (blue)
- Secondary: `Color(0xFFB1CB34)` (green)
- Tertiary: `Color(0xFFEA54A4)` (pink)
- Surface: `Colors.grey[50]`
- Use `useMaterial3: true`
- Use `theme.colorScheme.primary` instead of hardcoded colors

## File Organization
```
lib/
  main.dart              # Entry point, Supabase init
  login_page.dart        # Auth page
  main_navigation.dart   # Navigation shell
  *_page.dart            # Feature pages
  *_stub.dart            # Platform stub implementations
  *_native.dart          # Platform-specific implementations
  *_web*.dart            # Web-specific implementations
  widgets/               # Reusable widgets
  services/              # Business logic & API
```

## Platform Channels
The app uses conditional imports for platform-specific features:
- `checador_camera_stub.dart` - Default stub implementation
- `checador_camera_native.dart` - Native (Android/iOS) implementation
- `checador_web_impl.dart` - Web implementation
- Use `if (kIsWeb)` and `defaultTargetPlatform` for runtime checks

## Analysis Options
```yaml
include: package:flutter_lints/analysis_options.yaml
analyzer:
  errors:
    todo: ignore
linter:
  rules:
    public_member_api_docs: false
```

## Environment Configuration
- `.env` file for local development (`SB_URL`, `SB_TOKEN`)
- Environment variables as fallback
- Never commit secrets; use `.env.example` for template

## Testing Guidelines
- Tests in `test/` directory
- Use `WidgetTester` for widget tests
- Mock Supabase client when testing components that use it
- Always call `tester.pump()` or `tester.pumpAndSettle()` after interactions
