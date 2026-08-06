import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistemassi/asistente_store.dart';

/// Lo que se fija aquí es la razón de existir del almacén: que la conversación NO se pierda al
/// cambiar de página.
///
/// Antes vivía en el `State` de `AiPage`, y el shell pinta la página como
/// `Expanded(child: currentPage['widget'])`; al cambiar de página Flutter destruye ese subárbol y
/// se llevaba los mensajes. La prueba de abajo reproduce ese reemplazo de subárbol y comprueba que
/// ahora sobrevive.
void main() {
  final store = AsistenteStore.instancia;

  setUp(store.limpiar);

  test('empieza vacía y con el panel cerrado', () {
    expect(store.vacia, isTrue);
    expect(store.mensajes, isEmpty);
    expect(store.panelAbierto, isFalse);
    expect(store.cargando, isFalse);
  });

  test('la lista que expone no se puede mutar desde fuera', () {
    // Si una vista pudiera hacer store.mensajes.add(...), el almacén dejaría de ser la única
    // fuente y nadie se enteraría del cambio porque no habría notifyListeners.
    expect(() => store.mensajes.add(const ChatMsg(role: 'user', text: 'x')),
        throwsUnsupportedError);
  });

  test('el panel alterna y avisa a quien escuche', () {
    var avisos = 0;
    void escucha() => avisos++;
    store.addListener(escucha);

    store.alternarPanel();
    expect(store.panelAbierto, isTrue);
    store.alternarPanel();
    expect(store.panelAbierto, isFalse);

    // cerrarPanel estando cerrado no debe notificar: repintar de más es barato, pero avisar de un
    // cambio que no ocurrió esconde bugs.
    final antes = avisos;
    store.cerrarPanel();
    expect(avisos, antes);

    store.removeListener(escucha);
    expect(avisos, 2);
  });

  test('nueva conversación limpia los mensajes pero deja el panel abierto', () {
    store.alternarPanel();
    store.adjuntar(const ArchivoAdjunto(
        nombre: 'x.csv', ext: 'csv', contenido: 'a,b', truncado: false));

    store.limpiarConversacion();

    expect(store.vacia, isTrue);
    expect(store.adjunto, isNull);
    expect(store.panelAbierto, isTrue, reason: 'no debe cerrar el panel');
  });

  test('limpiar() sí cierra el panel: es el reinicio de cerrar sesión', () {
    store.alternarPanel();
    store.limpiar();
    expect(store.panelAbierto, isFalse);
  });

  testWidgets('la conversación sobrevive a que se reemplace el subárbol de la página',
      (tester) async {
    // Dos "páginas" que leen del almacén, como lo hacen el panel y la página de IA.
    Widget pagina(String clave) => MaterialApp(
          home: ListenableBuilder(
            listenable: store,
            builder: (context, _) => Text(
              '$clave:${store.mensajes.length}',
              key: const Key('conteo'),
              textDirection: TextDirection.ltr,
            ),
          ),
        );

    await tester.pumpWidget(pagina('A'));
    expect(find.text('A:0'), findsOneWidget);

    // Se manda un mensaje por el camino real. Sin sesión de Supabase falla, y ese fallo tiene que
    // acabar en un mensaje visible: quedan el turno del usuario y el del error, dos en total.
    await store.enviar('hola');
    await tester.pump();
    expect(find.text('A:2'), findsOneWidget);
    expect(store.mensajes.last.isError, isTrue,
        reason: 'un error debe verse en el chat, no perderse en silencio');
    expect(store.cargando, isFalse, reason: 'no debe quedarse cargando tras fallar');

    // Cambio de página: Flutter destruye el subárbol anterior y monta otro distinto.
    await tester.pumpWidget(pagina('B'));
    await tester.pump();

    // Antes esto habría dado B:0.
    expect(find.text('B:2'), findsOneWidget,
        reason: 'la conversación debe seguir ahí después de cambiar de página');
  });

  test('no manda nada si el texto está vacío y no hay adjunto', () {
    store.enviar('   ');
    expect(store.vacia, isTrue);
  });
}
