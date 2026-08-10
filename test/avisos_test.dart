import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistemassi/avisos_store.dart';
import 'package:sistemassi/theme/si_theme.dart';
import 'package:sistemassi/widgets/banner_avisos.dart';
import 'package:sistemassi/widgets/dialogo_aviso.dart';
import 'package:sistemassi/widgets/imagen_aviso.dart';
import 'package:sistemassi/widgets/lista_avisos.dart';

/// Los tres lugares donde sale un aviso —banner, ventana emergente y muro social— y la traducción de
/// una fila de `avisos_para_mi` a lo que se pinta.
///
/// Se prueban con datos planos porque es la única forma: montar la app pide sesión, permisos y RLS.
/// Es la misma disciplina que destapó el calendario en blanco.
void main() {
  Aviso aviso({
    String id = 'a1',
    String titulo = 'Mantenimiento del sistema',
    String cuerpo = 'El sistema estará fuera de servicio el sábado.',
    NivelAviso nivel = NivelAviso.advertencia,
    bool enModal = false,
    bool enBanner = true,
    bool enSocial = false,
    bool insistirModal = false,
    bool insistirBanner = false,
    bool vistoModal = false,
    bool vistoBanner = false,
    String? imagenUrl,
    DateTime? hasta,
  }) =>
      Aviso(
        id: id,
        titulo: titulo,
        cuerpo: cuerpo,
        nivel: nivel,
        imagenUrl: imagenUrl,
        enModal: enModal,
        enBanner: enBanner,
        enSocial: enSocial,
        insistirModal: insistirModal,
        insistirBanner: insistirBanner,
        vistoModal: vistoModal,
        vistoBanner: vistoBanner,
        hasta: hasta,
      );

  Widget envolver(Widget hijo, {double ancho = 900, bool oscuro = false}) =>
      MaterialApp(
        theme: oscuro ? SiTheme.dark : SiTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(width: ancho, child: hijo),
          ),
        ),
      );

  // ── Interpretación de la fila ──────────────────────────────────────────────

  group('Aviso.desde', () {
    test('lee los canales, el nivel y el acuse', () {
      final a = Aviso.desde({
        'id': 'x',
        'titulo': 'T',
        'cuerpo': 'C',
        'nivel': 'CRITICO',
        'en_modal': true,
        'en_banner': false,
        'en_social': true,
        'insistir_modal': true,
        'insistir_banner': false,
        'visto_modal': true,
        'visto_banner': false,
        'desde': '2026-08-01T00:00:00Z',
        'hasta': null,
      });
      expect(a.nivel, NivelAviso.critico);
      expect(a.enModal, isTrue);
      expect(a.enBanner, isFalse);
      expect(a.enSocial, isTrue);
      expect(a.insistirModal, isTrue);
      expect(a.insistirBanner, isFalse);
      expect(a.vistoModal, isTrue);
      expect(a.vistoBanner, isFalse);
      expect(a.hasta, isNull);
    });

    test('la imagen vacia o ausente queda en null, no en cadena vacia', () {
      // Importa: los widgets deciden con `imagenUrl != null`, y una cadena vacia pintaria un hueco
      // con el mensaje de error de carga en lugar de nada.
      expect(Aviso.desde({'id': 'x', 'titulo': 'T', 'cuerpo': 'C'}).imagenUrl, isNull);
      expect(Aviso.desde({'id': 'x', 'titulo': 'T', 'cuerpo': 'C', 'imagen_url': ''})
          .imagenUrl, isNull);
      expect(Aviso.desde({'id': 'x', 'titulo': 'T', 'cuerpo': 'C', 'imagen_url': '   '})
          .imagenUrl, isNull);
      expect(
          Aviso.desde({'id': 'x', 'titulo': 'T', 'cuerpo': 'C',
                       'imagen_url': 'https://x/y.png'}).imagenUrl,
          'https://x/y.png');
    });

    test('copiaVista conserva la imagen', () {
      final a = aviso(enModal: true, imagenUrl: 'https://x/y.png');
      expect(a.copiaVista(CanalAviso.modal).imagenUrl, 'https://x/y.png');
    });

    test('un nivel desconocido cae a informativo en lugar de reventar', () {
      // Si mañana se agrega un cuarto nivel en la base, un cliente viejo debe seguir funcionando.
      final a = Aviso.desde({'id': 'x', 'titulo': 'T', 'cuerpo': 'C', 'nivel': 'MORADO'});
      expect(a.nivel, NivelAviso.info);
    });

    test('el peso ordena lo grave primero', () {
      final lista = [
        aviso(id: '1', nivel: NivelAviso.info),
        aviso(id: '2', nivel: NivelAviso.critico),
        aviso(id: '3', nivel: NivelAviso.advertencia),
      ]..sort((a, b) => a.peso.compareTo(b.peso));
      expect(lista.map((a) => a.id), ['2', '3', '1']);
    });
  });

  // ── Las reglas por canal ──────────────────────────────────────────────────
  //
  // Aquí vivía el fallo que se reportó: un aviso publicado en los tres lugares perdía el banner al
  // apretar «Entendido» en el emergente, porque había UN acuse para tres canales.

  group('reglas por canal', () {
    test('cerrar el emergente NO descarta el banner del mismo aviso', () {
      // El caso exacto reportado: aviso en los tres canales, acuse sólo del emergente.
      final a = aviso(enModal: true, enBanner: true, enSocial: true, vistoModal: true);
      expect(a.debeVerseEnModal(), isFalse, reason: 'el emergente ya se acusó');
      expect(a.debeVerseEnBanner(), isTrue,
          reason: 'nadie descartó el banner: debe seguir ahí');
    });

    test('descartar el banner NO cierra el emergente', () {
      final a = aviso(enModal: true, enBanner: true, vistoBanner: true);
      expect(a.debeVerseEnBanner(), isFalse);
      expect(a.debeVerseEnModal(), isTrue);
    });

    test('sin insistir, el banner descartado no vuelve al recargar', () {
      final a = aviso(enBanner: true, vistoBanner: true);
      expect(a.debeVerseEnBanner(), isFalse);
    });

    test('con insistir_banner, el banner descartado vuelve al recargar', () {
      // Recargar es una sesión nueva: el conjunto de descartados de la pantalla empieza vacío.
      final a = aviso(enBanner: true, vistoBanner: true, insistirBanner: true);
      expect(a.debeVerseEnBanner(descartadoEnSesion: false), isTrue);
      // Pero dentro de la misma pantalla, la ✕ tiene que surtir efecto: si no, no serviría de nada.
      expect(a.debeVerseEnBanner(descartadoEnSesion: true), isFalse);
    });

    test('con insistir_modal el emergente vuelve, pero una vez por pantalla', () {
      final a = aviso(enModal: true, vistoModal: true, insistirModal: true);
      expect(a.debeVerseEnModal(mostradoEnSesion: false), isTrue);
      expect(a.debeVerseEnModal(mostradoEnSesion: true), isFalse);
    });

    test('los canales apagados no se muestran ni sin acuse', () {
      final a = aviso(enModal: false, enBanner: false, enSocial: true);
      expect(a.debeVerseEnModal(), isFalse);
      expect(a.debeVerseEnBanner(), isFalse);
    });

    test('copiaVista sólo toca el canal que se acusó', () {
      final a = aviso(enModal: true, enBanner: true);
      final trasModal = a.copiaVista(CanalAviso.modal);
      expect(trasModal.vistoModal, isTrue);
      expect(trasModal.vistoBanner, isFalse);

      final trasBanner = trasModal.copiaVista(CanalAviso.banner);
      expect(trasBanner.vistoModal, isTrue, reason: 'no se debe perder el acuse anterior');
      expect(trasBanner.vistoBanner, isTrue);
    });
  });

  // ── Banner ────────────────────────────────────────────────────────────────

  group('BannerAvisos', () {
    testWidgets('sin avisos no ocupa alto', (tester) async {
      await tester.pumpWidget(
          envolver(BannerAvisos(avisos: const [], alDescartar: (_) {})));
      expect(tester.getSize(find.byType(BannerAvisos)).height, 0);
    });

    testWidgets('muestra el más grave y ofrece el resto', (tester) async {
      await tester.pumpWidget(envolver(BannerAvisos(
        avisos: [
          aviso(id: '1', titulo: 'Informativo', nivel: NivelAviso.info),
          aviso(id: '2', titulo: 'Grave', nivel: NivelAviso.critico),
          aviso(id: '3', titulo: 'Ojo', nivel: NivelAviso.advertencia),
        ],
        alDescartar: (_) {},
      )));
      await tester.pumpAndSettle();

      // Uno visible, los otros detrás del contador: apilar tres franjas se come el alto de la página.
      expect(find.text('Grave'), findsOneWidget);
      expect(find.text('Ojo'), findsNothing);
      expect(find.text('+2 más'), findsOneWidget);

      await tester.tap(find.text('+2 más'));
      await tester.pumpAndSettle();
      expect(find.text('Ojo'), findsOneWidget);
      expect(find.text('Informativo'), findsOneWidget);
    });

    testWidgets('la ✕ devuelve el id que hay que acusar', (tester) async {
      final descartados = <String>[];
      await tester.pumpWidget(envolver(BannerAvisos(
        avisos: [aviso(id: 'abc')],
        alDescartar: descartados.add,
      )));
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(descartados, ['abc']);
    });

    testWidgets('los tres niveles se pintan de colores distintos', (tester) async {
      Color colorDe(NivelAviso n) {
        final c = SiColors.light;
        return colorDeNivel(c, n).$1;
      }

      // El fallo que se quiere evitar es el del día de regreso en Incidencias: dos cosas distintas
      // del mismo color.
      final colores = {
        colorDe(NivelAviso.info),
        colorDe(NivelAviso.advertencia),
        colorDe(NivelAviso.critico),
      };
      expect(colores.length, 3);
    });

    testWidgets('en tema oscuro también son tres colores distintos', (tester) async {
      final c = SiColors.dark;
      final colores = {
        colorDeNivel(c, NivelAviso.info).$1,
        colorDeNivel(c, NivelAviso.advertencia).$1,
        colorDeNivel(c, NivelAviso.critico).$1,
      };
      expect(colores.length, 3);
    });
  });

  // ── Ventana emergente ─────────────────────────────────────────────────────

  group('DialogoAviso', () {
    testWidgets('pinta título, cuerpo y nivel', (tester) async {
      await tester.pumpWidget(envolver(DialogoAviso(
          aviso: aviso(nivel: NivelAviso.critico, enModal: true))));
      await tester.pumpAndSettle();

      expect(find.text('Mantenimiento del sistema'), findsOneWidget);
      expect(find.textContaining('fuera de servicio'), findsOneWidget);
      expect(find.text('CRÍTICO'), findsOneWidget);
      expect(find.text('Entendido'), findsOneWidget);
    });

    testWidgets('avisa cuando el aviso va a insistir', (tester) async {
      await tester.pumpWidget(
          envolver(DialogoAviso(aviso: aviso(insistirModal: true, enModal: true))));
      await tester.pumpAndSettle();
      expect(find.text('Este aviso volverá a mostrarse'), findsOneWidget);
    });

    testWidgets('sin insistir no promete que vuelva', (tester) async {
      await tester.pumpWidget(envolver(DialogoAviso(aviso: aviso(enModal: true))));
      await tester.pumpAndSettle();
      expect(find.text('Este aviso volverá a mostrarse'), findsNothing);
    });
  });

  // ── Muro social ───────────────────────────────────────────────────────────

  // ── La imagen ─────────────────────────────────────────────────────────────
  //
  // En las pruebas ninguna descarga funciona, asi que Image.network cae siempre a su errorBuilder.
  // Eso resulta util: es exactamente el caso de una imagen borrada del bucket, y aqui se comprueba
  // que el aviso se siga leyendo en lugar de romper la tarjeta.

  group('imagen', () {
    testWidgets('el emergente la pinta y no tapa el texto', (tester) async {
      await tester.pumpWidget(envolver(DialogoAviso(
          aviso: aviso(enModal: true, imagenUrl: 'https://x/cartel.png'))));
      await tester.pumpAndSettle();

      expect(find.byType(ImagenAviso), findsOneWidget);
      expect(find.text('Mantenimiento del sistema'), findsOneWidget);
      expect(find.textContaining('fuera de servicio'), findsOneWidget);
      expect(find.text('Entendido'), findsOneWidget);
    });

    testWidgets('sin imagen el emergente no deja hueco', (tester) async {
      await tester.pumpWidget(envolver(DialogoAviso(aviso: aviso(enModal: true))));
      await tester.pumpAndSettle();
      expect(find.byType(ImagenAviso), findsNothing);
    });

    testWidgets('el muro social la pinta', (tester) async {
      await tester.pumpWidget(envolver(
        ListaAvisos(avisos: [
          aviso(enSocial: true, imagenUrl: 'https://x/cartel.png'),
        ]),
        ancho: 380,
      ));
      await tester.pumpAndSettle();

      expect(find.byType(ImagenAviso), findsOneWidget);
      expect(find.text('Mantenimiento del sistema'), findsOneWidget);
    });

    testWidgets('una imagen que no carga avisa y no rompe la tarjeta',
        (tester) async {
      await tester.pumpWidget(envolver(
        ListaAvisos(avisos: [
          aviso(enSocial: true, imagenUrl: 'https://no-existe/nada.png'),
        ]),
        ancho: 380,
      ));
      await tester.pumpAndSettle();

      // El aviso se sigue leyendo; solo falta la ilustracion.
      expect(find.text('No se pudo cargar la imagen'), findsOneWidget);
      expect(find.textContaining('fuera de servicio'), findsOneWidget);
    });

    testWidgets('el banner NO pinta imagenes: es una franja', (tester) async {
      await tester.pumpWidget(envolver(BannerAvisos(
        avisos: [aviso(imagenUrl: 'https://x/cartel.png')],
        alDescartar: (_) {},
      )));
      await tester.pumpAndSettle();

      expect(find.byType(ImagenAviso), findsNothing);
      expect(find.text('Mantenimiento del sistema'), findsOneWidget);
    });
  });

  group('ListaAvisos', () {
    testWidgets('sin avisos lo dice en lugar de dejar la columna vacía',
        (tester) async {
      await tester.pumpWidget(envolver(const ListaAvisos(avisos: []), ancho: 380));
      await tester.pumpAndSettle();
      expect(find.text('Sin avisos por ahora'), findsOneWidget);
    });

    testWidgets('lista todos y cuenta, con lo grave arriba', (tester) async {
      await tester.pumpWidget(envolver(
        ListaAvisos(avisos: [
          aviso(id: '1', titulo: 'Suave', nivel: NivelAviso.info, enSocial: true),
          aviso(id: '2', titulo: 'Grave', nivel: NivelAviso.critico, enSocial: true),
        ]),
        ancho: 380,
      ));
      await tester.pumpAndSettle();

      expect(find.text('2'), findsOneWidget);
      expect(find.text('Grave'), findsOneWidget);
      expect(find.text('Suave'), findsOneWidget);
      // Lo grave primero: su posición vertical es menor.
      expect(tester.getTopLeft(find.text('Grave')).dy,
          lessThan(tester.getTopLeft(find.text('Suave')).dy));
    });

    testWidgets('un aviso ya visto SIGUE en el muro', (tester) async {
      // El muro es a donde uno vuelve a consultar lo que ya quitó de en medio; esconder lo acusado
      // vaciaría justo eso.
      await tester.pumpWidget(envolver(
        ListaAvisos(avisos: [aviso(vistoBanner: true, enSocial: true)]),
        ancho: 380,
      ));
      await tester.pumpAndSettle();
      expect(find.text('Mantenimiento del sistema'), findsOneWidget);
    });

    testWidgets('muestra la vigencia cuando el aviso caduca', (tester) async {
      await tester.pumpWidget(envolver(
        ListaAvisos(
            avisos: [aviso(enSocial: true, hasta: DateTime(2026, 8, 12))]),
        ancho: 380,
      ));
      await tester.pumpAndSettle();
      // Sin intl inicializado cae al formato numérico, y eso es justo lo que no debe tumbar la
      // columna: se comprueba que algo de vigencia aparezca.
      expect(find.textContaining('Vigente hasta'), findsOneWidget);
    });
  });
}
