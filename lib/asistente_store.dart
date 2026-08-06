import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// La conversación con el asistente de RH, viva fuera del árbol de widgets.
///
/// ─── Por qué existe ──────────────────────────────────────────────────────────
///
/// La conversación vivía en el `State` de `AiPage`, y el shell de navegación pinta la página
/// como `Expanded(child: currentPage['widget'])`. Al cambiar de página Flutter reemplaza ese
/// subárbol y destruye el `State`, así que los mensajes se perdían — incluso al volver a la
/// página de IA, que aparecía vacía.
///
/// Sacarla aquí resuelve dos cosas a la vez: sobrevive al cambio de página, y el panel lateral y
/// la página completa muestran **el mismo hilo** en lugar de dos conversaciones con memorias
/// distintas.
///
/// ─── Alcance de la permanencia ───────────────────────────────────────────────
///
/// Vive en memoria. Sobrevive la navegación, **no** una recarga del navegador. Guardarla en la
/// base sería el siguiente paso, y obliga a decidir antes quién puede leer conversaciones que
/// pueden contener datos de RH.
class AsistenteStore extends ChangeNotifier {
  AsistenteStore._() {
    // Se limpia sola al cerrar sesión. Hacerlo aquí y no en los tres lugares que llaman a
    // signOut() evita que al agregar un cuarto se quede la conversación del usuario anterior
    // colgando para quien entre después.
    try {
      _auth = Supabase.instance.client.auth.onAuthStateChange.listen((estado) {
        if (estado.event == AuthChangeEvent.signedOut) limpiar();
      });
    } catch (_) {
      // Supabase todavía no está inicializado. Pasa en las pruebas y si la app arranca sin
      // credenciales; en ese caso no hay sesión que vigilar. Se atrapa para que el almacén se
      // pueda construir igual, en lugar de tumbar al primero que lo toque.
    }
  }

  /// Instancia única. El asistente es uno por sesión, así que no hace falta inyectarlo: el
  /// proyecto no usa ninguna librería de estado y añadir una sólo para esto sería desproporcionado.
  static final AsistenteStore instancia = AsistenteStore._();

  static const _fnUrl =
      'https://zkmbebybyyefmqcxjqrg.supabase.co/functions/v1/ai-assistant';

  StreamSubscription<AuthState>? _auth;

  final List<ChatMsg> _mensajes = [];
  bool _cargando = false;
  ArchivoAdjunto? _adjunto;
  bool _panelAbierto = false;
  String? _nombreUsuario;

  /// Sólo lectura hacia fuera: las vistas pintan, el almacén decide.
  List<ChatMsg> get mensajes => List.unmodifiable(_mensajes);
  bool get cargando => _cargando;
  ArchivoAdjunto? get adjunto => _adjunto;
  bool get vacia => _mensajes.isEmpty;

  /// Si el panel lateral está desplegado. Vive aquí y no en el `State` de los shells porque hay
  /// dos —escritorio y móvil— y al cruzar el umbral de 800px se reemplaza uno por el otro; con la
  /// bandera en el shell, redimensionar la ventana cerraba el panel.
  bool get panelAbierto => _panelAbierto;

  void alternarPanel() {
    _panelAbierto = !_panelAbierto;
    notifyListeners();
  }

  void cerrarPanel() {
    if (!_panelAbierto) return;
    _panelAbierto = false;
    notifyListeners();
  }

  void adjuntar(ArchivoAdjunto? archivo) {
    _adjunto = archivo;
    notifyListeners();
  }

  /// Nombre de pila, para el saludo. Null mientras no se haya cargado.
  String? get nombreUsuario => _nombreUsuario;

  /// Se consulta una sola vez por sesión, aunque estén montadas las dos vistas: viven las dos del
  /// mismo almacén, así que la segunda encuentra el nombre ya cargado.
  Future<void> cargarNombreUsuario() async {
    if (_nombreUsuario != null) return;
    try {
      final id = Supabase.instance.client.auth.currentUser?.id;
      if (id == null) return;
      final fila = await Supabase.instance.client
          .from('profiles')
          .select('nombre')
          .eq('id', id)
          .maybeSingle();
      final crudo = (fila?['nombre'] as String?)?.trim();
      if (crudo == null || crudo.isEmpty) return;
      // Sólo el primer nombre: «MARIA GUADALUPE» saluda mejor como «Maria».
      final pila = crudo.split(RegExp(r'\s+')).first;
      _nombreUsuario =
          pila[0].toUpperCase() + pila.substring(1).toLowerCase();
      notifyListeners();
    } catch (_) {
      // Sin nombre el saludo cae a algo genérico; no vale tumbar la pantalla por esto.
    }
  }

  /// Empieza de cero sin cerrar el panel: es el botón de «Nueva conversación».
  void limpiarConversacion() {
    _mensajes.clear();
    _adjunto = null;
    _cargando = false;
    notifyListeners();
  }

  /// Reinicio total, incluido el panel y el nombre. Es lo que corre al cerrar sesión: si no se
  /// borrara el nombre, el siguiente en entrar vería el saludo del anterior.
  void limpiar() {
    limpiarConversacion();
    _panelAbierto = false;
    _nombreUsuario = null;
    notifyListeners();
  }

  /// Envía el mensaje y agrega la respuesta. Devuelve cuando el turno terminó, para que la vista
  /// pueda hacer scroll al final.
  Future<void> enviar(String texto) async {
    final limpio = texto.trim();
    if ((limpio.isEmpty && _adjunto == null) || _cargando) return;

    // El archivo se manda completo al modelo, pero en pantalla se muestra sólo la pregunta: la
    // burbuja del usuario no debe volcar 40 000 caracteres de un Excel.
    final archivo = _adjunto;
    String textoParaModelo = limpio;
    String textoEnPantalla = limpio;

    if (archivo != null) {
      final nota = archivo.truncado
          ? '\n\n⚠️ Archivo truncado a los primeros 40 000 caracteres.'
          : '';
      textoParaModelo = '📎 Archivo adjunto: ${archivo.nombre}\n\n'
          '```\n${archivo.contenido}\n```$nota'
          '${limpio.isNotEmpty ? '\n\n$limpio' : ''}';
      textoEnPantalla = limpio.isNotEmpty ? limpio : 'Analiza este archivo.';
    }

    _mensajes.add(ChatMsg(
      role: 'user',
      text: textoEnPantalla,
      attachedFileName: archivo?.nombre,
      attachedFileExt: archivo?.ext,
    ));
    _adjunto = null;
    _cargando = true;
    notifyListeners();

    try {
      final sesion = Supabase.instance.client.auth.currentSession;
      if (sesion == null) throw Exception('Sin sesión activa');

      final historia = _mensajes
          .where((m) => m.text.isNotEmpty)
          .map((m) => {'role': m.role, 'content': m.text})
          .toList();
      // El último turno se reemplaza por la versión con el archivo embebido.
      if (historia.isNotEmpty && historia.last['role'] == 'user') {
        historia[historia.length - 1] = {
          'role': 'user',
          'content': textoParaModelo,
        };
      }

      final resp = await http
          .post(
            Uri.parse(_fnUrl),
            headers: {
              'Authorization': 'Bearer ${sesion.accessToken}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'messages': historia}),
          )
          .timeout(const Duration(seconds: 60));

      final cuerpo = jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode != 200) {
        throw Exception(cuerpo['error']?.toString() ?? 'Error ${resp.statusCode}');
      }

      _cargando = false;
      _mensajes.add(ChatMsg(
        role: 'assistant',
        text: cuerpo['text'] as String? ?? '',
        structured: cuerpo['structured'] as Map<String, dynamic>?,
      ));
    } catch (e) {
      // Sin comprobar `mounted`: el almacén no está atado a ningún widget, que es justamente el
      // punto. Antes, cambiar de página a media respuesta la descartaba.
      _cargando = false;
      _mensajes.add(ChatMsg(
        role: 'assistant',
        text: 'Error: $e',
        isError: true,
      ));
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _auth?.cancel();
    super.dispose();
  }
}

// ── Modelos ──────────────────────────────────────────────────────────────────

class ChatMsg {
  final String role;
  final String text;
  final Map<String, dynamic>? structured;
  final bool isError;
  final String? attachedFileName;
  final String? attachedFileExt;

  const ChatMsg({
    required this.role,
    required this.text,
    this.structured,
    this.isError = false,
    this.attachedFileName,
    this.attachedFileExt,
  });
}

class ArchivoAdjunto {
  final String nombre;
  final String ext;
  final String contenido;
  final bool truncado;

  const ArchivoAdjunto({
    required this.nombre,
    required this.ext,
    required this.contenido,
    required this.truncado,
  });
}
