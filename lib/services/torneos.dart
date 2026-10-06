// Datos de Torneos (la SiSol Mario Kart Cup). Ver supabase/migrations/20261006200000_torneos.sql.
//
// Aqui solo se LEE y se ordena. Todo lo que cambia algo va por las funciones de la base
// (`torneo_capturar`, `garage_crear`…): ahi se decide quien puede hacer que.

/// Puntos de Kart Garage por posicion. Los mismos que pone `torneo_capturar` en la base.
const puntosGarage = [10, 7, 5, 3, 2, 1, 0, 0];

/// Avatares para elegir al inscribirse.
const avataresTorneo = ['🏎️', '🍄', '⭐', '🐢', '🍌', '👑', '🔥', '⚡', '🦖', '👻', '🐸', '🚀'];

class Jugador {
  final String userId;
  final String apodo;
  final String avatar;
  final String nombre;

  const Jugador({
    required this.userId,
    required this.apodo,
    required this.avatar,
    required this.nombre,
  });

  factory Jugador.fromMap(Map<String, dynamic> m) {
    final perfil = m['profiles'] as Map<String, dynamic>?;
    return Jugador(
      userId: m['user_id'] as String,
      apodo: m['apodo'] as String? ?? '',
      avatar: m['avatar'] as String? ?? '🏎️',
      nombre: perfil?['full_name'] as String? ?? '',
    );
  }
}

class Participante {
  final String userId;
  final int? posicion;
  final int? puntos;

  const Participante({required this.userId, this.posicion, this.puntos});

  factory Participante.fromMap(Map<String, dynamic> m) => Participante(
        userId: m['user_id'] as String,
        posicion: m['posicion'] as int?,
        puntos: m['puntos'] as int?,
      );
}

class Carrera {
  final String id;
  final String? torneoId;
  final String tipo; // grupo | final | libre
  final String? grupo;
  final int ronda;
  final int? numero;
  final DateTime? fechaHora;
  final bool abierta;
  final int cupo;
  final String estado; // programada | por_confirmar | completada | cancelada
  final String? creadaPor;
  final String? capturadaPor;
  final DateTime? createdAt;
  final List<Participante> participantes;

  const Carrera({
    required this.id,
    required this.tipo,
    required this.ronda,
    required this.estado,
    required this.participantes,
    this.torneoId,
    this.grupo,
    this.numero,
    this.fechaHora,
    this.abierta = false,
    this.cupo = 4,
    this.creadaPor,
    this.capturadaPor,
    this.createdAt,
  });

  factory Carrera.fromMap(Map<String, dynamic> m) {
    DateTime? fecha(String k) =>
        m[k] == null ? null : DateTime.tryParse(m[k] as String)?.toLocal();
    final ps = (m['torneo_carrera_jugadores'] as List? ?? [])
        .map((e) => Participante.fromMap(e as Map<String, dynamic>))
        .toList();
    return Carrera(
      id: m['id'] as String,
      torneoId: m['torneo_id'] as String?,
      tipo: m['tipo'] as String,
      grupo: m['grupo'] as String?,
      ronda: m['ronda'] as int? ?? 1,
      numero: m['numero'] as int?,
      fechaHora: fecha('fecha_hora'),
      abierta: m['abierta'] as bool? ?? false,
      cupo: m['cupo'] as int? ?? 4,
      estado: m['estado'] as String? ?? 'programada',
      creadaPor: m['creada_por'] as String?,
      capturadaPor: m['capturada_por'] as String?,
      createdAt: fecha('created_at'),
      participantes: ps,
    );
  }

  bool get esLibre => tipo == 'libre';
  bool get completada => estado == 'completada';
  bool get cancelada => estado == 'cancelada';
  bool get pendiente => estado == 'programada' || estado == 'por_confirmar';
  bool corre(String userId) => participantes.any((p) => p.userId == userId);

  /// Los participantes del 1.º al último; los que aún no tienen lugar, al final.
  List<Participante> get enOrden {
    final l = [...participantes];
    l.sort((a, b) => (a.posicion ?? 99).compareTo(b.posicion ?? 99));
    return l;
  }
}

/// Una fila de `torneo_tabla`: un jugador en un grupo (o en una carrera de finales).
class FilaTabla {
  final String userId;
  final String tipo;
  final String grupo;
  final int ronda;
  final int puntos;
  final int carreras;
  final int carrerasTotal;
  final int victorias;
  final double? posicionMedia;

  const FilaTabla({
    required this.userId,
    required this.tipo,
    required this.grupo,
    required this.ronda,
    required this.puntos,
    required this.carreras,
    required this.carrerasTotal,
    required this.victorias,
    this.posicionMedia,
  });

  factory FilaTabla.fromMap(Map<String, dynamic> m) => FilaTabla(
        userId: m['user_id'] as String,
        tipo: m['tipo'] as String,
        grupo: m['grupo'] as String? ?? '',
        ronda: m['ronda'] as int? ?? 1,
        puntos: m['puntos'] as int? ?? 0,
        carreras: m['carreras'] as int? ?? 0,
        carrerasTotal: m['carreras_total'] as int? ?? 0,
        victorias: m['victorias'] as int? ?? 0,
        posicionMedia: (m['posicion_media'] as num?)?.toDouble(),
      );
}

/// El mismo orden que usa `torneo_avanzar` para decidir quien pasa: puntos, victorias, mejor
/// posicion promedio (sin carreras va al final) y, por ultimo, el id, para que no baile.
int compararFilas(FilaTabla a, FilaTabla b) {
  var r = b.puntos.compareTo(a.puntos);
  if (r != 0) return r;
  r = b.victorias.compareTo(a.victorias);
  if (r != 0) return r;
  final pa = a.posicionMedia, pb = b.posicionMedia;
  if (pa != pb) {
    if (pa == null) return 1;
    if (pb == null) return -1;
    r = pa.compareTo(pb);
    if (r != 0) return r;
  }
  return a.userId.compareTo(b.userId);
}

/// Las tablas de la fase de grupos, una por grupo y ya ordenadas.
Map<String, List<FilaTabla>> tablasDeGrupos(List<FilaTabla> filas) {
  final out = <String, List<FilaTabla>>{};
  for (final f in filas.where((f) => f.tipo == 'grupo')) {
    out.putIfAbsent(f.grupo, () => []).add(f);
  }
  for (final l in out.values) {
    l.sort(compararFilas);
  }
  return Map.fromEntries(out.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
}

/// Nombre de una carrera para mostrar. `carrerasEnRonda` decide si una de finales es la Gran Final.
String nombreCarrera(Carrera c, {int carrerasEnRonda = 1}) {
  switch (c.tipo) {
    case 'grupo':
      return 'Carrera ${c.numero ?? '?'} · Grupo ${c.grupo ?? '?'}';
    case 'final':
      if (carrerasEnRonda == 1) return 'Gran Final';
      final j = (c.grupo ?? '').split('-').last;
      return 'Ronda ${c.ronda} · Carrera $j';
    default:
      return 'Kart Garage';
  }
}

String etiquetaFase(String fase) => switch (fase) {
      'inscripcion' => 'Inscripción',
      'grupos' => 'Fase de grupos',
      'finales' => 'Finales',
      'terminado' => 'Terminado',
      _ => fase,
    };

String etiquetaEstado(String estado) => switch (estado) {
      'programada' => 'Por jugar',
      'por_confirmar' => 'Por confirmar',
      'completada' => 'Completada',
      'cancelada' => 'Cancelada',
      _ => estado,
    };

/// Ranking de Kart Garage a partir de las carreras libres completadas. Lo mismo que la vista
/// `garage_ranking`, pero sin pedirla aparte: las carreras ya estan cargadas.
List<({String userId, int puntos, int carreras, int victorias})> rankingGarage(
    List<Carrera> carreras) {
  final acc = <String, ({int puntos, int carreras, int victorias})>{};
  for (final c in carreras.where((c) => c.esLibre && c.completada)) {
    for (final p in c.participantes) {
      final a = acc[p.userId] ?? (puntos: 0, carreras: 0, victorias: 0);
      acc[p.userId] = (
        puntos: a.puntos + (p.puntos ?? 0),
        carreras: a.carreras + 1,
        victorias: a.victorias + (p.posicion == 1 ? 1 : 0),
      );
    }
  }
  final l = acc.entries
      .map((e) => (
            userId: e.key,
            puntos: e.value.puntos,
            carreras: e.value.carreras,
            victorias: e.value.victorias,
          ))
      .toList();
  l.sort((a, b) {
    var r = b.puntos.compareTo(a.puntos);
    if (r != 0) return r;
    r = b.victorias.compareTo(a.victorias);
    if (r != 0) return r;
    r = a.carreras.compareTo(b.carreras);
    if (r != 0) return r;
    return a.userId.compareTo(b.userId);
  });
  return l;
}
