# Fix de build — fuentes locales (sin google_fonts)

El build falló porque `google_fonts 6.3.3` no tiene `GoogleFonts.geist()` ni `GoogleFonts.geistMono()`. La solución definitiva es bundlear las fuentes localmente.

## Archivos a actualizar

### 1. `lib/theme/si_theme.dart`
Reemplaza completo por el archivo `si_theme.dart` de este bundle (ya no importa `google_fonts`).

### 2. `pubspec.yaml`

**Remueve** la línea de `google_fonts`:
```yaml
# ❌ QUITAR:
google_fonts: ^8.0.2
```

**Añade** las fuentes locales en la sección `flutter:`:
```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/
    - assets/firmcred/
    - .env
  fonts:
    - family: Geist
      fonts:
        - asset: assets/fonts/Geist-Regular.ttf
          weight: 400
        - asset: assets/fonts/Geist-Medium.ttf
          weight: 500
        - asset: assets/fonts/Geist-SemiBold.ttf
          weight: 600
        - asset: assets/fonts/Geist-Bold.ttf
          weight: 700
    - family: GeistMono
      fonts:
        - asset: assets/fonts/GeistMono-Regular.ttf
          weight: 400
        - asset: assets/fonts/GeistMono-Medium.ttf
          weight: 500
```

### 3. Descarga las fuentes

**Geist (recomendado):** https://vercel.com/font → descarga el zip y copia los `.ttf` a `assets/fonts/` con los nombres exactos de arriba.

**Alternativa (si no quieres Geist):** usa Inter desde https://rsms.me/inter/download/ y cambia en `si_theme.dart`:
```dart
static const String fontFamily = 'Inter';
```
Y renombra las familias/assets en `pubspec.yaml` a `Inter-Regular.ttf`, etc.

### 4. `web/index.html`

**Remueve** las líneas de preconnect y el stylesheet de Google Fonts si las agregaste antes:
```html
<!-- ❌ QUITAR estas 3 líneas: -->
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Geist..." rel="stylesheet">
```

Las fuentes ya van en el bundle; no dependes de la red.

### 5. Limpia referencias a GoogleFonts en el resto del código

```bash
grep -rn "GoogleFonts\|google_fonts" lib/
```

Cualquier uso (e.g. `GoogleFonts.inter(...)`) reemplázalo por:
```dart
TextStyle(fontFamily: 'Geist', fontSize: 14, ...)
// o
SiType.sans(size: 14, weight: FontWeight.w500, color: c.ink)
```

### 6. Build

```bash
flutter clean
flutter pub get
flutter build web
```

Si compila local, push y el deploy debería pasar.

---

## Por qué esta solución es mejor

1. **Sin dependencia de red** en producción — las fuentes están en el bundle
2. **Sin riesgo de CSP / firewall** bloqueando fonts.gstatic.com
3. **FOUT eliminado** — no hay parpadeo cargando la fuente
4. **Independiente de versiones de google_fonts** — nunca más este error
5. **Carga más rápida** — menos requests al arrancar
