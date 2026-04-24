# Sistemassi — Integración del Theme en Flutter

## 1) Agregar dependencia

```yaml
# pubspec.yaml
dependencies:
  flutter:
    sdk: flutter
  google_fonts: ^6.2.1
```

Luego `flutter pub get`.

## 2) Copiar el archivo

Copia `si_theme.dart` a tu proyecto en:

```
lib/theme/si_theme.dart
```

## 3) Conectar en `main.dart`

```dart
import 'package:flutter/material.dart';
import 'theme/si_theme.dart';

void main() => runApp(const SistemassiApp());

class SistemassiApp extends StatelessWidget {
  const SistemassiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sistemassi',
      theme: SiTheme.light,
      darkTheme: SiTheme.dark,
      themeMode: ThemeMode.system,
      // ...resto igual: router, home, etc.
    );
  }
}
```

## 4) Usar los tokens en widgets

```dart
import 'theme/si_theme.dart';

class MiCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);

    return Container(
      padding: const EdgeInsets.all(SiSpace.x4),
      decoration: BoxDecoration(
        color: c.panel,
        border: Border.all(color: c.line),
        borderRadius: SiRadius.rLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Folio', style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: SiSpace.x1),
          Text('INC-0042', style: SiType.mono(size: 13, color: c.ink)),
        ],
      ),
    );
  }
}
```

## 5) Chips de estado (success / warn / danger)

```dart
Widget statusChip(BuildContext ctx, String text, {required String kind}) {
  final c = SiColors.of(ctx);
  final (bg, fg) = switch (kind) {
    'success' => (c.successTint, c.success),
    'warn'    => (c.warnTint, c.warn),
    'danger'  => (c.dangerTint, c.danger),
    _         => (c.hover, c.ink2),
  };
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: SiRadius.rPill,
      border: Border.all(color: fg.withValues(alpha: 0.25)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(
          color: fg, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(
          fontSize: 11.5, fontWeight: FontWeight.w500, color: fg)),
      ],
    ),
  );
}
```

## 6) Sidebar colapsable con animación

```dart
AnimatedContainer(
  duration: SiMotion.railExpand,
  curve: SiMotion.easeOut,
  width: expanded ? SiLayout.railExpanded : SiLayout.railCollapsed,
  decoration: BoxDecoration(
    color: SiColors.of(context).panel,
    border: Border(right: BorderSide(
      color: SiColors.of(context).line)),
  ),
  // ...items
)
```

## 7) Migración sugerida (pantalla por pantalla)

Orden recomendado para no romper nada:

1. **Envolver `MaterialApp`** con `SiTheme.light` — ya cambia toda la app
2. **Login** — reemplazar fondo, inputs y botón primario
3. **Sidebar / shell** — usar `NavigationRail` con el theme de arriba
4. **Mi Perfil / Dashboard** — cards con `c.panel` + `c.line`
5. **Tablas** (Incidencias, ISSI, Usuarios, Logs) — filas con `Divider()` y texto mono en columnas de folio/SKU
6. **Calendario / BI** — mantener Syncfusion y custom charts, pero pasar los colores de `SiColors`

## 8) Lo que NO cambia

- Lógica Supabase, auth, RPC, triggers, buckets
- Estructura de rutas y navegación
- Generadores de PDF, firmas, checador con cámara
- Tablas, queries, permisos por rol

Solo estás cambiando la **capa visual**. Todos los datos y flujos siguen exactamente igual.
