import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Los avisos vigentes de quien está dentro, vivos fuera del árbol de widgets.
///
/// ─── Por qué un almacén y no tres consultas ──────────────────────────────────
///
/// Los mismos avisos se pintan en tres lugares: el banner bajo la barra, la ventana emergente y la
/// tercera columna de Social. Con cada widget consultando por su cuenta serían tres viajes por lo
/// mismo, y además tres estados que se desincronizan: cerrar el emergente no apagaría el banner del
/// mismo aviso hasta recargar.
///
/// El banner tiene además el problema que ya resolvió [AsistenteStore]: vive en el shell, y hay dos
/// shells —escritorio y móvil— que se reemplazan al cruzar los 800px. Con el estado en el `State`
/// del shell, redimensionar la ventana resucitaría un banner ya descartado.
///
/// ─── Qué se lee ──────────────────────────────────────────────────────────────
///
/// Sólo la vista `avisos_para_mi`, que ya resuelve vigencia, segmentación y acuse. Aquí NO se repiten
/// esas reglas: si estuvieran en Dart habría que mantenerlas iguales en tres widgets, y basta con que
/// una se quede atrás para mostrarle a alguien un aviso que no era para él.
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

  /// Los ids cuyo emergente ya se mostró en ESTA sesión.
  ///
  /// Es lo que hace distinto a `insistir` de «reaparece cada segundo»: un aviso insistente vuelve en
  /// la siguiente sesión, no cada vez que el shell se reconstruye —y el shell se reconstruye al
  /// cambiar de página, al redimensionar y al cambiar de tema.
  final Set<String> _mostradosEnSesion = {};

  bool get cargado => _cargado;
  bool get cargando => _cargando;

  /// Los del banner que la persona no ha descartado.
  List<Aviso> get banners =>
      _avisos.where((a) => a.enBanner && !a.visto).toList();

  /// Los del muro social: todos los vigentes, descartados o no. El muro es consulta, no acuse.
  List<Aviso> get social => _avisos.where((a) => a.enSocial).toList();

  /// Los emergentes que faltan por mostrar, del más grave al menos grave.
  ///
  /// Un aviso ya acusado vuelve sólo si es `insistir`, y aun así una vez por sesión.
  List<Aviso> get modalesPendientes {
    final lista = _avisos
        .where((a) =>
            a.enModal &&
            (!a.visto || a.insistir) &&
            !_mostradosEnSesion.contains(a.id))
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
          .select(
              'id, titulo, cuerpo, nivel, en_modal, en_banner, en_social, insistir, desde, hasta, visto')
          // Del más grave al más nuevo. El orden del nivel se resuelve en Dart —`peso`— porque en SQL
          // sería un CASE que habría que repetir en cada consulta.
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

  /// Acusa un aviso: desaparece del banner y el emergente no vuelve.
  ///
  /// El estado local se actualiza ANTES de escribir. Si la inserción falla, el aviso ya no molesta en
  /// esta sesión y el acuse se reintenta la próxima; al revés —esperar la respuesta— el banner se
  /// quedaría clavado en pantalla cada vez que la red va lenta.
  Future<void> marcarVisto(String id) async {
    final i = _avisos.indexWhere((a) => a.id == id);
    if (i != -1) _avisos[i] = _avisos[i].copiaVista();
    _mostradosEnSesion.add(id);
    notifyListeners();

    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await Supabase.instance.client
          .from('avisos_vistos')
          // La llave compuesta hace esto idempotente, así que no hace falta consultar antes.
          .upsert({'aviso_id': id, 'profile_id': uid},
              onConflict: 'aviso_id,profile_id', ignoreDuplicates: true);
    } catch (e) {
      debugPrint('avisos: no se pudo guardar el acuse de $id: $e');
    }
  }

  /// Marca que el emergente ya se mostró en esta sesión, sin acusarlo.
  ///
  /// Hace falta para los `insistir`: se muestran una vez por sesión, y si la persona cierra sin
  /// acusar no deben reaparecer en cuanto el shell se reconstruya.
  void marcarMostrado(String id) {
    _mostradosEnSesion.add(id);
  }

  void limpiar() {
    _avisos = [];
    _mostradosEnSesion.clear();
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
    required this.insistir,
    required this.visto,
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
        insistir: f['insistir'] == true,
        visto: f['visto'] == true,
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
  final bool insistir;
  final bool visto;
  final DateTime? desde;
  final DateTime? hasta;

  /// Para ordenar: primero lo grave.
  int get peso => switch (nivel) {
        NivelAviso.critico => 0,
        NivelAviso.advertencia => 1,
        NivelAviso.info => 2,
      };

  Aviso copiaVista() => Aviso(
        id: id,
        titulo: titulo,
        cuerpo: cuerpo,
        nivel: nivel,
        enModal: enModal,
        enBanner: enBanner,
        enSocial: enSocial,
        insistir: insistir,
        visto: true,
        desde: desde,
        hasta: hasta,
      );
}

enum NivelAviso { info, advertencia, critico }
