import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'theme/si_theme.dart';

/// Lo que comparten las páginas de la sección VENTAS.
///
/// Sisol es el agente de ventas PÚBLICO de sisol.com.mx: un Worker de Cloudflare en chat.sisol.red
/// (código en `workers/ventas/`) con Llama de Workers AI. Sus datos viven en las tablas `ventas_*`
/// de Supabase, y estas páginas las leen y escriben directo con la sesión del usuario (RLS con
/// `show_ventas` / `edit_ventas`). Al Worker sólo se le pide lo que la app no tiene: los textos
/// predeterminados del código y la llave de OpenWA para re-enviar un aviso.
///
/// No es SOL: SOL es el asistente INTERNO de los asesores, con sus propios desarrollos. Decidido el
/// 24/09/2026 que no comparten catálogo.
const urlSisol = 'https://chat.sisol.red';

String urlCotizacion(String folio) => '$urlSisol/api/cotizacion/$folio';

bool puedeEditarVentas(String role, Map<String, dynamic> permissions) =>
    role == 'admin' || permissions['edit_ventas'] == true;

class SisolApi {
  static Future<Map<String, dynamic>> _llamar(String metodo, String ruta) async {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    final uri = Uri.parse('$urlSisol$ruta');
    final headers = {'authorization': 'Bearer $token'};
    final res = metodo == 'POST'
        ? await http.post(uri, headers: headers)
        : await http.get(uri, headers: headers);
    if (res.statusCode == 401) throw Exception('Sin permiso para Ventas.');
    // Una respuesta que no es JSON es la página «Not found» de un Worker que no tiene esta ruta:
    // el de chat.sisol.red todavía es la versión anterior a la sección Ventas.
    final Object? cuerpo;
    try {
      cuerpo = res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body);
    } on FormatException {
      throw Exception('El Worker de $urlSisol no tiene esta función todavía; falta desplegar '
          'la versión de workers/ventas.');
    }
    if (res.statusCode >= 400) {
      throw Exception((cuerpo is Map ? cuerpo['error'] : null) ?? 'Error ${res.statusCode}');
    }
    return Map<String, dynamic>.from(cuerpo as Map);
  }

  /// Etiqueta, pista, tipo y valor predeterminado de cada clave de `ventas_config`.
  static Future<List<Map<String, dynamic>>> configMeta() async {
    final r = await _llamar('GET', '/api/ventas/config-meta');
    return [for (final c in r['config'] as List) Map<String, dynamic>.from(c as Map)];
  }

  /// Re-envía el WhatsApp al asesor. Devuelve el error, o null si salió.
  static Future<String?> notificar(String folio) async {
    final r = await _llamar('POST', '/api/ventas/leads/${Uri.encodeComponent(folio)}/notificar');
    return r['ok'] == true ? null : (r['error'] ?? 'No se pudo enviar.').toString();
  }
}

Future<void> abrirUrl(String url) async {
  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

void avisoVentas(BuildContext context, String texto, {bool error = false}) {
  final c = SiColors.of(context);
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(texto),
    backgroundColor: error ? c.danger : c.success,
  ));
}

/// La barra de arriba de cada página: búsqueda a la izquierda y acciones a la derecha.
class BarraVentas extends StatelessWidget {
  final String pista;
  final ValueChanged<String> onBuscar;
  final List<Widget> acciones;

  const BarraVentas({
    super.key,
    required this.pista,
    required this.onBuscar,
    this.acciones = const [],
  });

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: SiSpace.x5, vertical: SiSpace.x3),
      decoration: BoxDecoration(
        color: c.panel,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Wrap(
        spacing: SiSpace.x3,
        runSpacing: SiSpace.x2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 320,
            child: TextField(
              onChanged: onBuscar,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 18),
                hintText: pista,
                border: const OutlineInputBorder(borderRadius: SiRadius.rMd),
              ),
            ),
          ),
          ...acciones,
        ],
      ),
    );
  }
}

/// Un número con su etiqueta: «21 · Leads totales».
class CifraVentas extends StatelessWidget {
  final String etiqueta;
  final int valor;
  final IconData icono;
  final Color? color;

  const CifraVentas({
    super.key,
    required this.etiqueta,
    required this.valor,
    required this.icono,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final tono = color ?? c.brand;
    return Container(
      width: 190,
      padding: const EdgeInsets.all(SiSpace.x4),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: SiRadius.rLg,
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          Icon(icono, size: 20, color: tono),
          const SizedBox(width: SiSpace.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$valor',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.ink)),
                Text(etiqueta, style: TextStyle(fontSize: 11.5, color: c.ink3)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget etiquetaVentas(SiColors c, String texto, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: SiRadius.rPill,
    ),
    child: Text(texto,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
  );
}
