import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Dónde se puede descartar un aviso. El muro social no aparece porque ahí no se descarta nada.
enum CanalAviso { modal, banner }

/// Los avisos vigentes de quien está dentro, vivos fuera del árbol de widgets.
///
/// ─── Por qué un almacén y no tres consultas ──────────────────────────────────
///
/// Los mismos avisos se pintan en tres lugares: el banner bajo la barra, la ventana emergente y la
/// tercera columna de Social. Con cada widget consultando por su cuenta serían tres viajes por lo
/// mismo, y tres estados que se desincronizan.
///
/// El banner tiene además el problema que ya resolvió [AsistenteStore]: vive en el shell, y hay dos
/// shells —escritorio y móvil— que se reemplazan al cruzar los 800px. Con el estado en el `State`
/// del shell, redimensionar la ventana resucitaría un banner ya descartado.
///
/// ─── El acuse es por canal ───────────────────────────────────────────────────
///
/// Cada canal se descarta por su cuenta. La primera versión guardaba un solo acuse por aviso, y con
/// un aviso publicado en los tres lugares apretar «Entendido» en el emergente hacía desaparecer el
/// banner —que nadie había descartado— y no volvía nunca. Eran tres decisiones metidas en un dato.
class AvisosStore extends ChangeNotifier {
  AvisosStore._() {
    // Se limpia al cerrar sesión, por lo mismo que el almacén del asistente: si no, quien entre
    // después en el mismo navegador vería los avisos del usuario anterior —que pueden estar
    // dirigidos a otra ubicación— hasta la primera recarga.
    try {
      _auth = Supabase.instance.client.auth.onAuthStateChange.listen((estado) {
        if (estado.event == AuthChangeEvent.signedOut) limpiar();
      });
    } catch (_) {
      // Supabase sin inicializar: pasa en las pruebas. Se atrapa para que el almacén se pueda
      // construir igual en lugar de tumbar al primero que lo toque.
    }
  }

  static final AvisosStore instancia = AvisosStore._();

  StreamSubscription<AuthState>? _auth;

  List<Aviso> _avisos = [];
  bool _cargado = false;
  bool _cargando = false;

  /// Lo que ya se resolvió en ESTA carga de la pantalla, por canal.
  ///
  /// Es lo que hace que «insistir» signifique «vuelve al recargar» y no «vuelve cada instante»: el
  /// shell se reconstruye al cambiar de página, al redimensionar y al cambiar de tema, y sin esto un
  /// aviso insistente reaparecería en cada una de esas veces.
  final Set<String> _modalesMostrados = {};
  final Set<String> _bannersDescartados = {};

  bool get cargado => _cargado;
  bool get cargando => _cargando;

  /// Los banners que toca mostrar ahora.
  List<Aviso> get banners => _avisos
      .where((a) =>
          a.debeVerseEnBanner(descartadoEnSesion: _bannersDescartados.contains(a.id)))
      .toList();

  /// Los del muro social: todos los vigentes, descartados o no. El muro es consulta, no acuse.
  List<Aviso> get social => _avisos.where((a) => a.enSocial).toList();

  /// Los emergentes que faltan por mostrar, del más grave al menos grave.
  List<Aviso> get modalesPendientes {
    final lista = _avisos
        .where((a) => a.debeVerseEnModal(
            mostradoEnSesion: _modalesMostrados.contains(a.id)))
        .toList()
      ..sort((a, b) => a.peso.compareTo(b.peso));
    return lista;
  }

  Future<void> cargar({bool forzar = false}) async {
    if (_cargando || (_cargado && !forzar)) return;
    _cargando = true;
    notifyListeners();
    try {
      final filas = await Supabase.instance.client
          .from('avisos_para_mi')
          .select('id, titulo, cuerpo, nivel, en_modal, en_banner, en_social, '
              'insistir_modal, insistir_banner, visto_modal, visto_banner, '
              'desde, hasta')
          // El orden del nivel se resuelve en Dart —`peso`— porque en SQL sería un CASE repetido en
          // cada consulta.
          .order('creado_en', ascending: false);
      _avisos = [
        for (final f in List<Map<String, dynamic>>.from(filas)) Aviso.desde(f)
      ];
      _cargado = true;
    } catch (e) {
      // Un aviso que no carga no debe impedir usar el sistema: se deja la lista vacía y la app sigue.
      debugPrint('avisos: no se pudieron leer: $e');
    } finally {
      _cargando = false;
      notifyListeners();
    }
  }

  /// Acusa un aviso EN UN CANAL. Cerrar el emergente no descarta el banner.
  ///
  /// El estado local se actualiza ANTES de escribir. Si la inserción falla, el aviso ya no molesta en
  /// esta pantalla y el acuse se reintenta a la próxima; al revés —esperar la respuesta— el banner se
  /// quedaría clavado cada vez que la red va lenta.
  Future<void> marcarVisto(String id, CanalAviso canal) async {
    final i = _avisos.indexWhere((a) => a.id == id);
    if (i != -1) _avisos[i] = _avisos[i].copiaVista(canal);
    switch (canal) {
      case CanalAviso.modal:
        _modalesMostrados.add(id);
      case CanalAviso.banner:
        _bannersDescartados.add(id);
    }
    notifyListeners();

    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await Supabase.instance.client.from('avisos_vistos').upsert(
        {'aviso_id': id, 'profile_id': uid, 'canal': _nombreCanal(canal)},
        // La llave incluye el canal, así que esto es idempotente por canal y no hace falta consultar
        // antes de escribir.
        onConflict: 'aviso_id,profile_id,canal',
        ignoreDuplicates: true,
      );
    } catch (e) {
      debugPrint('avisos: no se pudo guardar el acuse de $id: $e');
    }
  }

  static String _nombreCanal(CanalAviso c) =>
      c == CanalAviso.modal ? 'MODAL' : 'BANNER';

  /// Marca que el emergente ya se mostró en esta pantalla, sin acusarlo.
  ///
  /// Hace falta para los insistentes: se muestran una vez por carga, y si la persona cierra con Escape
  /// —sin acusar— no deben reaparecer en cuanto el shell se reconstruya.
  void marcarMostrado(String id) {
    _modalesMostrados.add(id);
  }

  void limpiar() {
    _avisos = [];
    _modalesMostrados.clear();
    _bannersDescartados.clear();
    _cargado = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _auth?.cancel();
    super.dispose();
  }
}

/// Un aviso ya interpretado. Existe para no andar sacando claves de un `Map` en tres widgets.
class Aviso {
  const Aviso({
    required this.id,
    required this.titulo,
    required this.cuerpo,
    required this.nivel,
    required this.enModal,
    required this.enBanner,
    required this.enSocial,
    required this.insistirModal,
    required this.insistirBanner,
    required this.vistoModal,
    required this.vistoBanner,
    this.desde,
    this.hasta,
  });

  factory Aviso.desde(Map<String, dynamic> f) => Aviso(
        id: f['id'].toString(),
        titulo: (f['titulo'] ?? '').toString(),
        cuerpo: (f['cuerpo'] ?? '').toString(),
        // Un nivel desconocido cae a INFO en lugar de reventar: si mañana se agrega un cuarto nivel
        // en la base, una versión vieja del cliente lo pinta en verde y sigue funcionando.
        nivel: switch ((f['nivel'] ?? '').toString()) {
          'CRITICO' => NivelAviso.critico,
          'ADVERTENCIA' => NivelAviso.advertencia,
          _ => NivelAviso.info,
        },
        enModal: f['en_modal'] == true,
        enBanner: f['en_banner'] == true,
        enSocial: f['en_social'] == true,
        insistirModal: f['insistir_modal'] == true,
        insistirBanner: f['insistir_banner'] == true,
        vistoModal: f['visto_modal'] == true,
        vistoBanner: f['visto_banner'] == true,
        desde: DateTime.tryParse((f['desde'] ?? '').toString()),
        hasta: DateTime.tryParse((f['hasta'] ?? '').toString()),
      );

  final String id;
  final String titulo;
  final String cuerpo;
  final NivelAviso nivel;
  final bool enModal;
  final bool enBanner;
  final bool enSocial;
  final bool insistirModal;
  final bool insistirBanner;
  final bool vistoModal;
  final bool vistoBanner;
  final DateTime? desde;
  final DateTime? hasta;

  /// Si el banner debe verse. Función pura: es la regla que se puede probar sin sesión, y donde
  /// estaba el fallo de que un «Entendido» apagara el banner.
  bool debeVerseEnBanner({bool descartadoEnSesion = false}) =>
      enBanner && !descartadoEnSesion && (!vistoBanner || insistirBanner);

  /// Si el emergente debe abrirse.
  bool debeVerseEnModal({bool mostradoEnSesion = false}) =>
      enModal && !mostradoEnSesion && (!vistoModal || insistirModal);

  /// Para ordenar: primero lo grave.
  int get peso => switch (nivel) {
        NivelAviso.critico => 0,
        NivelAviso.advertencia => 1,
        NivelAviso.info => 2,
      };

  /// El mismo aviso con el acuse de UN canal puesto. El otro canal no se toca.
  Aviso copiaVista(CanalAviso canal) => Aviso(
        id: id,
        titulo: titulo,
        cuerpo: cuerpo,
        nivel: nivel,
        enModal: enModal,
        enBanner: enBanner,
        enSocial: enSocial,
        insistirModal: insistirModal,
        insistirBanner: insistirBanner,
        vistoModal: vistoModal || canal == CanalAviso.modal,
        vistoBanner: vistoBanner || canal == CanalAviso.banner,
        desde: desde,
        hasta: hasta,
      );
}

enum NivelAviso { info, advertencia, critico }
