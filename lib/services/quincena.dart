/// Una quincena: del 1 al 15, o del 16 al último día del mes.
///
/// ─── Por qué el segundo corte no es «del 16 al 30» ───────────────────────────
///
/// El segundo periodo llega al último día que tenga el mes: 16 días en enero, 15 en abril, y 13 o 14 en
/// febrero según el año. Escribirlo con un 30 fijo dejaría el día 31 fuera de toda quincena —y con él
/// sus faltas y sus retardos— **siete veces al año**, y en febrero contaría días que no existen.
///
/// Vive fuera del panel para poder probar esos bordes sin montar la pantalla: son la clase de fallo que
/// no se ve mirando, sólo el día 31 de un mes cualquiera.
class Quincena {
  final int anio;
  final int mes;

  /// 1 para la primera mitad, 2 para la segunda.
  final int mitad;
  const Quincena(this.anio, this.mes, this.mitad);

  /// La quincena a la que pertenece una fecha en texto `AAAA-MM-DD`, o `null` si no se puede leer.
  static Quincena? deIso(String? iso) {
    if (iso == null || iso.length < 10) return null;
    final anio = int.tryParse(iso.substring(0, 4));
    final mes = int.tryParse(iso.substring(5, 7));
    final dia = int.tryParse(iso.substring(8, 10));
    if (anio == null || mes == null || dia == null) return null;
    if (mes < 1 || mes > 12 || dia < 1 || dia > 31) return null;
    return Quincena(anio, mes, dia <= 15 ? 1 : 2);
  }

  /// El último día del mes.
  ///
  /// `DateTime(anio, mes + 1, 0)` es el día 0 del mes siguiente, o sea el último del actual. Resuelve
  /// los años bisiestos sin tabla y sin condicionales.
  int get ultimoDia => DateTime(anio, mes + 1, 0).day;

  int get diaInicial => mitad == 1 ? 1 : 16;
  int get diaFinal => mitad == 1 ? 15 : ultimoDia;

  String _iso(int dia) => '$anio-${mes.toString().padLeft(2, '0')}'
      '-${dia.toString().padLeft(2, '0')}';

  String get desdeIso => _iso(diaInicial);
  String get hastaIso => _iso(diaFinal);

  /// Si una fecha `AAAA-MM-DD` cae dentro.
  ///
  /// Se compara como TEXTO: en ese formato el orden alfabético es el cronológico, así que no hace falta
  /// construir un `DateTime` por cada renglón en cada repintado.
  bool contiene(String iso) =>
      iso.compareTo(desdeIso) >= 0 && iso.compareTo(hastaIso) <= 0;

  /// Ordena cronológicamente como texto, que es para lo que se usa.
  String get clave => '$anio-${mes.toString().padLeft(2, '0')}-$mitad';

  static const _meses = ['', 'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
    'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];

  /// «1 al 15 de julio 2026». Lleva el año porque en cuanto haya dos julios en la lista, sin él no se
  /// distinguen.
  String get etiqueta => '$diaInicial al $diaFinal de ${_meses[mes]} $anio';

  @override
  bool operator ==(Object otro) => otro is Quincena && otro.clave == clave;

  @override
  int get hashCode => clave.hashCode;

  @override
  String toString() => 'Quincena($clave: $desdeIso..$hastaIso)';
}
