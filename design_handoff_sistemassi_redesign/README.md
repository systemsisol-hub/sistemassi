# Handoff: Sistemassi — Rediseño Visual "Enterprise Quiet"

## Overview

This handoff package contains the complete visual redesign for **Sistemassi**, the internal operations platform for Sisol Soluciones Inmobiliarias. The existing application is built in **Flutter** (web-first, with Android/iOS support) and integrates with Supabase for auth, storage, and data.

The goal of this work is to **replace the current visual layer** (which uses a mix of glassmorphism, bright brand colors, and Inter typography) with a new **"Enterprise Quiet"** design system — a restrained, data-dense, Linear/Notion-inspired aesthetic that keeps the corporate blue but tones down saturation, introduces a cool-neutral scale, uses Geist typography, and favors 1px borders over shadows.

**Critically: only the visual/presentation layer changes. All business logic, Supabase calls, routing, PDF generation, camera checador, signatures generator, permissions, RPC, triggers, and data flows must remain exactly as they are today.**

---

## About the Design Files

The files under `design_files/` are **design references created as an HTML/React prototype** — they show the intended look, typography, spacing, interactions, and component vocabulary. **They are not production code to copy directly.**

Your task is to **recreate these designs in the existing Flutter codebase** using Flutter widgets and the project's existing architecture. A ready-to-use `si_theme.dart` is provided in `flutter_theme/` that translates every design token (colors, radii, spacing, typography, motion) into native Flutter `ThemeData` and `ThemeExtension` form. Start there.

---

## Fidelity

**High-fidelity (hifi).** The HTML prototype is pixel-accurate and final in terms of:

- Color palette (see Design Tokens below)
- Typography scale (Geist sans + Geist Mono)
- Radii (6 / 8 / 10 / 14 px)
- Spacing scale (4px base)
- Border-first (1px) over shadows
- Micro-interaction timings and easing
- Component vocabulary (chips, cards, buttons, tables)

Developers should aim to **match the prototype pixel-for-pixel** where feasible in Flutter, within the constraints of the Material widget library (or by building thin custom widgets where Material defaults don't match).

---

## Screens Covered

The prototype contains the full shell and all main module screens. Priority order for migration is:

### Priority 1 — Foundation (must land together)
1. **Theme setup** — wire `SiTheme.light` / `SiTheme.dark` into `MaterialApp`
2. **Login** (`login.jsx`)
3. **App Shell** (`shell.jsx`) — sidebar + header
4. **Mi Perfil / Dashboard** (`dashboard.jsx`)

### Priority 2 — Main modules (in `pages.jsx`)
5. Calendar
6. Incidencias (incidents)
7. Inventario ISSI (inventory)
8. Asistencia / Checador (attendance)
9. Usuarios (admin users)
10. BI (dashboard analytics)

### Priority 3 — Secondary modules
11. Firmas (email signature generator)
12. Contactos externos
13. Colaboradores
14. Social
15. Logs

---

## Screens — Detailed Specs

### 1. Login

**File:** `design_files/login.jsx` + `design_files/styles.css` (`.login-root`, `.login-form`, etc.)

- **Layout:** Single-column centered form, max-width ~400px, vertically centered on `--bg`. No split-panel, no marketing imagery.
- **Header:** Small "S" brand mark (28×28 rounded square, `--brand` bg, white letter), followed by "Sistemassi" (14px, 600) and "Sisol · Intranet" (11px, uppercase, `--ink-3`, letter-spacing 0.1em).
- **Title:** "Bienvenido de vuelta" (h1, 24px, 600, `-0.015em` tracking).
- **Subtitle:** "Accede a la plataforma operativa de Sisol Soluciones Inmobiliarias." (13px, `--ink-2`).
- **Fields:** Email + password. Each field uses a left icon adornment (`mail`, `key`). Password has a right-side eye toggle. Input height 40px, border 1px `--line`, focus border 1.5px `--brand`, radius 8px. Label is 12px, 500, `--ink-2`, 4px bottom margin.
- **"¿Olvidaste tu contraseña?"** right-aligned on the password label row, 12px, `--brand`, no underline until hover.
- **Submit:** Full-width primary button, height 38px, radius 8px, `--brand` background. Label "Iniciar sesión". Loading state: replace label with inline spinner, keep width fixed.
- **Micro-interactions:**
  - Form fade-in on mount (200ms ease-out)
  - Button press: scale 0.98 for 80ms
  - Input focus: border color transitions 120ms

### 2. App Shell

**File:** `design_files/shell.jsx` + `styles.css` (`.shell`, `.rail`, `.header`)

- **Layout:** `grid-template-columns: var(--rail-w) 1fr;` → rail (60px collapsed) + main (header 52px + content).
- **Sidebar (rail):**
  - Collapsed width: **60px**. Expanded width: **248px** on `hover` (in Flutter, on mouse region enter; on mobile, via a menu button).
  - Expansion animation: 220ms, ease-out cubic-bezier(0.2, 0.8, 0.2, 1.0).
  - Background: `--panel` (white), right border 1px `--line`.
  - Top: 28×28 brand mark "S". When expanded, show wordmark to the right.
  - Middle: nav items. Each item is 40px tall, 18px icon. Collapsed = icon-only centered. Expanded = icon + label (13px, 500). Active item: `--brand-tint` background, `--brand` icon + text, with a 2px left-edge `--brand` indicator bar.
  - Bottom: "Alejandra M." avatar (24px circle, initials "AM" on `--brand-tint`), chevron for menu.
- **Header (52px):**
  - Left: breadcrumbs or page title (16px, 600).
  - Center: global search (`⌘K` hint in mono 11px on the right of the field).
  - Right: notifications bell (with red dot if count > 0), date chip, user avatar.
- **Micro-interactions:**
  - Nav item hover: background fades to `--hover` in 120ms.
  - Rail expansion: width + label opacity animate together.

### 3. Mi Perfil / Dashboard

**File:** `design_files/dashboard.jsx`

A dense, multi-card profile view. The layout is a 12-column grid at 24px gutter, typical breakpoint ≥1280px.

- **Top card — Profile identity:** 96×96 avatar (initials "AM" on `--brand-tint`), name (20px, 600), title (13px, `--ink-2`), employee id chip (mono, `EMP-00248`), CURP chip (mono).
- **Row 2 — 3 cards across:**
  - **Jerarquía:** Director / Gerente / Jefe / Líder, each with 24px avatar placeholder + name + label.
  - **Ubicación & Contacto:** empresa, área, ubicación, teléfono, celular, correo. Each line: 12px label uppercase `--ink-3`, 13px value.
  - **Actividad (30 días):** Inline sparkline SVG (see ACTIVITY array in dashboard.jsx), 120×40px, stroke `--brand`, fill `--brand-tint`.
- **Row 3 — Equipment table:** Rows with icon (laptop / phone / badge), name (13px), tag (mono 12px `--ink-2`), meta chip. Hover row: bg `--hover`.
- **Row 4 — Credentials table:** 6 rows (MAIL, DRP, GP, BITRIX, ENK, OTRO). Columns: system (mono badge, 11px uppercase, `--brand-tint` bg, `--brand` fg), username (13px), password (mono, masked "••••••••••" by default, eye toggle).

### 4. Module pages (Calendar, Incidencias, ISSI, etc.)

**File:** `design_files/pages.jsx`

All share the same shell — content is wrapped in a main container with a page header row (title + actions) and a primary content region (table / grid / split).

- **Tables (Incidencias, ISSI, Usuarios, Logs):**
  - Compact rows, 40px tall.
  - Column headers: 11px uppercase, 500, `--ink-3`, letter-spacing 0.05em.
  - Body: 13px.
  - Mono font for IDs (folio `INC-0042`, SKU, timestamps).
  - Dividers: 1px `--line-2` between rows. No alternating fills.
  - Hover row: `--hover` background.
  - Chips for status (success/warn/danger + brand) — see Design Tokens.
- **Calendar:** Monthly grid, event pills colored by category. Toggle row for Personal/Grupal and Mes/Semana/Día/Lista, rendered as a segmented control (pill group, active = `--panel` on `--hover` track).
- **Asistencia / Checador:** Big circular clock-in button centered, pulsing ring animation (opacity 1 → 0 ping, 1.5s infinite). Below: today's entries as a vertical timeline.
- **BI:** 4 KPI cards at top (label 11px uppercase, number 28px 600, delta chip). Main area: SVG area chart, stroke `--brand`, fill `--brand-tint`, 240px tall. Below: ranked bars for "plazas".
- **Logs:** Monospace terminal-style list, each row with timestamp (mono 12px `--ink-3`), severity chip (INFO / WARN / ERROR), actor, action. Filter chips at the top.

---

## Interactions & Behavior

- **Sidebar expansion:** 220ms width + 180ms label opacity, ease-out. Collapses back with 160ms.
- **Button press:** scale(0.98) for 80ms, then back. Avoid ripples on small buttons.
- **Input focus:** 120ms border-color transition.
- **Modal/dialog open:** 180ms fade + 8px upward translate.
- **Toast notifications:** slide in from top-right, 220ms ease-out spring `cubic-bezier(0.34, 1.56, 0.64, 1.0)`.
- **Table row hover:** 100ms background fade.
- **Check-in button (Asistencia):** continuous ping ring (1.5s, ease-out, infinite).

All timings and curves are available as constants in `flutter_theme/si_theme.dart` under `SiMotion`.

---

## State Management

This is a visual refresh — **no changes to state management architecture**. The existing patterns (whatever Sistemassi uses today: Provider, Riverpod, Bloc, GetX, etc.) must be preserved. Only widget styling changes.

For any new micro-interactions:
- Sidebar `expanded` boolean — local state at shell root
- Toast queue — wherever it lives today
- Form focus / validation — same as today

---

## Design Tokens

All tokens are codified in `flutter_theme/si_theme.dart`. The authoritative values:

### Colors — Light

| Token | Hex | Purpose |
|---|---|---|
| `brand` | `#344092` | Corporate blue (primary) |
| `brandInk` | `#1A2466` | Darker on hover text |
| `brandTint` | `#EFF1FA` | Tinted bg for active/selected |
| `brandHover` | `#2A3577` | Hover on brand surfaces |
| `bg` | `#FBFBFC` | App background |
| `panel` | `#FFFFFF` | Cards, sheets, inputs |
| `ink` | `#1C2030` | Primary text |
| `ink2` | `#4A5068` | Secondary text |
| `ink3` | `#737A92` | Tertiary / labels |
| `ink4` | `#A2A7B8` | Disabled / icons |
| `line` | `#E4E6EC` | 1px borders |
| `line2` | `#EEF0F4` | Subtle dividers |
| `hover` | `#F4F5F8` | Row/item hover |
| `active` | `#EAECF2` | Pressed/active state |
| `success` | `#2E9460` | Green for approved |
| `successTint` | `#EAF6EE` | Green chip bg |
| `warn` | `#D99531` | Amber for pending |
| `warnTint` | `#FCF4E4` | Amber chip bg |
| `danger` | `#C93B2E` | Red for rejected/error |
| `dangerTint` | `#F9E9E6` | Red chip bg |

### Colors — Dark

| Token | Hex |
|---|---|
| `brand` | `#6B7BD6` |
| `bg` | `#0D0F14` |
| `panel` | `#14171F` |
| `ink` | `#EEF0F5` |
| `line` | `#24283A` |
| ... | (see `SiColors.dark` in `si_theme.dart`) |

### Radius

- `sm` 6px — chips, small tags
- `md` 8px — buttons, inputs, small cards
- `lg` 10px — medium cards
- `xl` 14px — large panels, dialogs
- `pill` 999px — status chips, segmented controls

### Spacing (4px base)

`x0.5 = 2`, `x1 = 4`, `x2 = 8`, `x3 = 12`, `x4 = 16`, `x5 = 20`, `x6 = 24`, `x8 = 32`, `x10 = 40`, `x12 = 48`.

### Typography

- **Sans:** Geist (via `google_fonts: geistTextTheme()`)
- **Mono:** Geist Mono (for IDs, SKUs, timestamps, codes)
- **Fallback:** Inter, system-ui

Scale (approximate, see `SiType` for exact mapping):

| Role | Size | Weight | Tracking |
|---|---|---|---|
| displayLarge | 40 | 600 | -0.02em |
| headlineLarge | 24 | 600 | -0.015em |
| titleLarge | 16 | 600 | -0.005em |
| titleMedium | 14 | 500 | 0 |
| bodyLarge | 14 | 400 | 0 |
| bodyMedium | 13 | 400 | 0 |
| bodySmall | 12 | 400 | 0 |
| labelSmall | 11 | 500 | +0.02em (uppercase for labels) |

### Layout constants

- `railCollapsed` 60px
- `railExpanded` 248px
- `headerHeight` 52px

### Motion

- `fast` 120ms, `normal` 180ms, `slow` 260ms, `railExpand` 220ms
- `easeOut` cubic(0.2, 0.8, 0.2, 1.0)
- `easeInOut` cubic(0.4, 0.0, 0.2, 1.0)
- `spring` cubic(0.34, 1.56, 0.64, 1.0)

---

## Migration Strategy (Recommended)

1. **Add dependency:** `flutter pub add google_fonts` (version ≥6.2.1).
2. **Drop in the theme:** copy `flutter_theme/si_theme.dart` to `lib/theme/si_theme.dart`.
3. **Wire it up:**
   ```dart
   MaterialApp(
     theme: SiTheme.light,
     darkTheme: SiTheme.dark,
     themeMode: ThemeMode.system,
     // ...
   )
   ```
4. **Build reusable widgets** in `lib/widgets/ui/`:
   - `SiCard` — wraps `Container` with `c.panel`, 1px `c.line` border, `SiRadius.rLg`.
   - `SiStatusChip` — parameterized by `kind: 'success' | 'warn' | 'danger' | 'brand'`.
   - `SiMonoText` — helper for monospace tokens (IDs, SKUs).
   - `SiTableRow` — 40px row, 13px text, hover via `MouseRegion`.
   - `SiSectionHeader` — uppercase 11px label, `c.ink3`.
5. **Migrate screen-by-screen** in the priority order above. Do not touch business logic — only the `build` methods of presentation widgets.
6. **Remove the old glassmorphism layer:** search for `BackdropFilter`, `ImageFilter.blur`, `_buildGlassPill`, `.withOpacity(0.` on brand colors. Replace those containers with `SiCard` or plain 1px-border containers.
7. **QA checklist per screen:**
   - Matches prototype pixel-spacing to within 2px
   - Uses mono font for IDs / SKUs / timestamps
   - All status chips use `successTint` / `warnTint` / `dangerTint` backgrounds with matching foreground text
   - Hover states work on web (use `MouseRegion` + `AnimatedContainer` where needed)
   - Dark mode renders correctly

---

## What MUST NOT Change

This is a visual refresh. The following are **explicitly out of scope** and must remain untouched:

- Supabase client, auth flow, session handling, RPC calls
- Database schema, triggers, `log_event`, RLS policies, storage buckets
- Routing / navigation structure
- PDF generation for incidencias
- Camera-based checador logic
- Email signature generator logic
- Calendar backend (Syncfusion or whichever library is currently integrated)
- Permissions system, role checks, user management logic
- Existing business rules and validation logic

If you find yourself refactoring any of the above, stop — the change is out of scope.

---

## Assets

- **Fonts:** Geist + Geist Mono are fetched via `google_fonts` package at runtime. No font files need to be bundled.
- **Icons:** The prototype uses a custom lightweight icon set (see `design_files/icons.jsx`). In Flutter, replace with equivalent `Icons.*` from Material or `lucide_icons` / `phosphor_flutter`.
  - mail → `Icons.mail_outline`
  - key → `Icons.key_outlined`
  - eye / eyeOff → `Icons.visibility_outlined` / `Icons.visibility_off_outlined`
  - calendar, clock, chart, users, box (inventory), signature, list, etc. — map 1:1 from icon name.
- **Images:** No photographs or illustrations are used. Avatars are rendered as colored circles with 1–2 letter initials.

---

## Files in this bundle

```
design_handoff_sistemassi_redesign/
├── README.md                           ← You are here
├── design_files/                       ← HTML/React prototype (reference only)
│   ├── Sistemassi.html                 ← Entry point — open this to view
│   ├── styles.css                      ← All CSS tokens + component styles
│   ├── login.jsx                       ← Login screen
│   ├── shell.jsx                       ← Sidebar + header scaffold
│   ├── dashboard.jsx                   ← Mi Perfil / Dashboard
│   ├── pages.jsx                       ← Calendar, Incidencias, ISSI, Asistencia,
│   │                                     Usuarios, BI, Firmas, Contactos,
│   │                                     Colaboradores, Social, Logs
│   ├── icons.jsx                       ← Inline SVG icon set
│   └── tweaks-panel.jsx                ← Design-time controls (ignore for impl)
└── flutter_theme/
    ├── si_theme.dart                   ← ★ Drop this into lib/theme/
    └── README.md                       ← Quick integration guide
```

To view the prototype, open `design_files/Sistemassi.html` in a browser. Navigate via the sidebar.

---

## Open questions for the developer

- Does the project already have a design-tokens file or theme extension? If yes, merge `SiColors` into it rather than duplicating.
- Does the project use a specific icon package today? Match that package rather than pulling in a new one.
- Does the sidebar on mobile (Android/iOS) need a different collapse model (e.g. Drawer)? If yes, use `Drawer` + the same token set — the rail-expand-on-hover pattern is web-only.
- Is there a preference for Material 3 switches/dialogs vs. custom Cupertino-flavored? The theme defaults to Material 3 — override per widget if needed.
