import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'theme/si_theme.dart';
import 'services/trash_service.dart';

class ExternalContactsPage extends StatefulWidget {
  const ExternalContactsPage({super.key});

  @override
  State<ExternalContactsPage> createState() => _ExternalContactsPageState();
}

class _ExternalContactsPageState extends State<ExternalContactsPage> {
  List<Map<String, dynamic>> _contacts = [];
  bool _isLoading = true;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String _empresa = 'todas';

  @override
  void initState() {
    super.initState();
    _fetchContacts();
  }


  Widget _buildEmptyState(SiColors c) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.contact_support_outlined, size: 64, color: c.line),
          SizedBox(height: SiSpace.x4),
          Text('No se encontraron contactos',
              style: TextStyle(color: c.ink3, fontSize: 15)),
        ],
      ),
    );
  }

  Future<void> _fetchContacts() async {
    setState(() => _isLoading = true);
    try {
      final data = await Supabase.instance.client
          .from('external_contacts')
          .select()
          .order('nombre', ascending: true);

      if (mounted) {
        setState(() {
          _contacts = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching contacts: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error al cargar contactos: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _filteredContacts {
    final query = _searchQuery.trim().toLowerCase();
    // Los dígitos se comparan sin espacios ni guiones, que es como los teclea la gente cuando
    // quiere saber de quién fue una llamada.
    final soloDigitos = query.replaceAll(RegExp(r'\D'), '');

    return _contacts.where((c) {
      String t(String k) => (c[k] ?? '').toString().trim();

      if (_empresa != 'todas' && t('empresa') != _empresa) return false;
      if (query.isEmpty) return true;

      final telefono = t('telefono').replaceAll(RegExp(r'\D'), '');
      return t('nombre').toLowerCase().contains(query) ||
          t('empresa').toLowerCase().contains(query) ||
          t('correo').toLowerCase().contains(query) ||
          t('otro').toLowerCase().contains(query) ||
          (soloDigitos.isNotEmpty && telefono.contains(soloDigitos));
    }).toList();
  }

  Future<void> _deleteContact(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Contacto'),
        content:
            const Text('¿Estás seguro de que deseas eliminar este contacto?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCELAR')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('ELIMINAR'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final contact = _contacts.firstWhere((c) => c['id'] == id, orElse: () => {});
        if (contact.isNotEmpty) {
          final label = (contact['nombre'] as String? ?? '').trim();
          await TrashService.moveToTrash(
            originTable: 'external_contacts',
            originId: id,
            data: Map<String, dynamic>.from(contact),
            label: label.isNotEmpty ? label : 'Contacto',
          );
        }
        await Supabase.instance.client
            .from('external_contacts')
            .delete()
            .eq('id', id);
        _fetchContacts();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Contacto movido a la papelera')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Error: $e'), backgroundColor: Colors.red));
        }
      }
    }
  }

  void _showContactForm({Map<String, dynamic>? contact}) {
    final isEditing = contact != null;

    final nombreController = TextEditingController(text: contact?['nombre']);
    final empresaController = TextEditingController(text: contact?['empresa']);
    final correoController = TextEditingController(text: contact?['correo']);
    final telefonoController =
        TextEditingController(text: contact?['telefono']);
    final otroController = TextEditingController(text: contact?['otro']);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          bool saving = false;
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: MediaQuery.of(context).viewInsets.bottom + 40,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancelar',
                            style: TextStyle(fontSize: 16, color: Colors.grey)),
                      ),
                      Text(
                        isEditing ? 'Editar Contacto' : 'Nuevo Contacto',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      TextButton(
                        onPressed: () async {
                          if (nombreController.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('El nombre es obligatorio')));
                            return;
                          }
                          setModalState(() => saving = true);
                          try {
                            final data = {
                              'nombre':
                                  nombreController.text.trim().toUpperCase(),
                              'empresa':
                                  empresaController.text.trim().toUpperCase(),
                              'correo': correoController.text.trim(),
                              'telefono': telefonoController.text.trim(),
                              'otro': otroController.text.trim(),
                              'created_by':
                                  Supabase.instance.client.auth.currentUser?.id,
                            };
                            if (isEditing) {
                              await Supabase.instance.client
                                  .from('external_contacts')
                                  .update(data)
                                  .eq('id', contact['id']);
                            } else {
                              await Supabase.instance.client
                                  .from('external_contacts')
                                  .insert(data);
                            }
                            if (mounted) {
                              Navigator.pop(context);
                              _fetchContacts();
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text(isEditing
                                          ? 'Contacto actualizado'
                                          : 'Contacto creado')));
                            }
                          } catch (e) {
                            setModalState(() => saving = false);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text('Error: $e'),
                                      backgroundColor: Colors.red));
                            }
                          }
                        },
                        child: saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Guardar',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  TextField(
                      controller: nombreController,
                      decoration: const InputDecoration(
                          labelText: 'Nombre *',
                          prefixIcon: Icon(Icons.person))),
                  const SizedBox(height: 16),
                  TextField(
                      controller: empresaController,
                      decoration: const InputDecoration(
                          labelText: 'Empresa',
                          prefixIcon: Icon(Icons.business))),
                  const SizedBox(height: 16),
                  TextField(
                      controller: correoController,
                      decoration: const InputDecoration(
                          labelText: 'Correo', prefixIcon: Icon(Icons.email))),
                  const SizedBox(height: 16),
                  TextField(
                      controller: telefonoController,
                      decoration: const InputDecoration(
                          labelText: 'Teléfono',
                          prefixIcon: Icon(Icons.phone))),
                  const SizedBox(height: 16),
                  TextField(
                      controller: otroController,
                      decoration: const InputDecoration(
                          labelText: 'Otro',
                          prefixIcon: Icon(Icons.more_horiz))),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Presentación ────────────────────────────────────────────────────────────
  //
  // Mismo diseño que la página de Directorio: buscador y filtro en un solo renglón a la misma
  // altura, y la lista en varias columnas para no dejar un hueco enorme entre el nombre y los
  // datos de contacto en pantallas anchas.

  List<String> get _empresas {
    final e = _contacts
        .map((c) => (c['empresa'] ?? '').toString().trim())
        .where((x) => x.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return e;
  }

  Future<void> _copiar(String valor, String que) async {
    await Clipboard.setData(ClipboardData(text: valor));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$que copiado'), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final isNarrow = MediaQuery.of(context).size.width < 600;
    final filtered = _filteredContacts;

    return Scaffold(
      backgroundColor: c.bg,
      floatingActionButton: isNarrow
          ? FloatingActionButton(
              onPressed: () => _showContactForm(),
              backgroundColor: c.brand,
              foregroundColor: Colors.white,
              elevation: 2,
              child: const Icon(Icons.person_add),
            )
          : null,
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: c.brand, strokeWidth: 2))
          : Column(
              children: [
                _barraBusqueda(c, isNarrow, filtered.length),
                Expanded(
                  child: filtered.isEmpty
                      ? _buildEmptyState(c)
                      : RefreshIndicator(
                          onRefresh: _fetchContacts,
                          color: c.brand,
                          child: _lista(c, filtered, isNarrow),
                        ),
                ),
              ],
            ),
    );
  }

  /// Buscador, filtro de empresa y el botón de alta, todos en el mismo renglón y a la misma altura:
  /// el relleno vertical se define una vez y lo comparten los controles para que no se desalineen.
  Widget _barraBusqueda(SiColors c, bool isNarrow, int visibles) {
    const relleno = EdgeInsets.symmetric(horizontal: 12, vertical: 11);
    final total = _contacts.length;

    final buscador = TextField(
      controller: _searchController,
      onChanged: (v) => setState(() => _searchQuery = v),
      style: const TextStyle(fontSize: 13.5),
      decoration: InputDecoration(
        hintText: 'Buscar por nombre, empresa, correo o teléfono…',
        hintStyle: TextStyle(fontSize: 13, color: c.ink4),
        prefixIcon: Icon(Icons.search, size: 18, color: c.ink3),
        prefixIconConstraints: const BoxConstraints(minWidth: 38, minHeight: 0),
        suffixIcon: _searchQuery.isEmpty
            ? null
            : InkWell(
                onTap: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
                child: Icon(Icons.close, size: 16, color: c.ink3),
              ),
        suffixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 0),
        isDense: true,
        contentPadding: relleno,
        border: OutlineInputBorder(borderRadius: SiRadius.rMd),
      ),
    );

    final empresas = _empresas;

    return Container(
      padding: EdgeInsets.fromLTRB(
          isNarrow ? SiSpace.x4 : SiSpace.x5, SiSpace.x3,
          isNarrow ? SiSpace.x4 : SiSpace.x5, SiSpace.x3),
      decoration: BoxDecoration(
        color: c.panel,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: buscador),
          // Con una sola empresa el filtro no filtra nada; sólo estorbaría.
          if (!isNarrow && empresas.length > 1) ...[
            const SizedBox(width: SiSpace.x3),
            SizedBox(
              width: 230,
              child: DropdownButtonFormField<String>(
                value: _empresa,
                isExpanded: true,
                isDense: true,
                style: TextStyle(fontSize: 13, color: c.ink),
                icon: Icon(Icons.expand_more, size: 18, color: c.ink3),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: relleno,
                  prefixIcon: Icon(Icons.business_outlined, size: 16, color: c.ink3),
                  prefixIconConstraints:
                      const BoxConstraints(minWidth: 34, minHeight: 0),
                  border: OutlineInputBorder(borderRadius: SiRadius.rMd),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'todas',
                    child: Text('Todas las empresas',
                        style: TextStyle(fontSize: 13, color: c.ink2)),
                  ),
                  for (final e in empresas)
                    DropdownMenuItem(
                      value: e,
                      child: Text(e,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: c.ink2)),
                    ),
                ],
                onChanged: (v) => setState(() => _empresa = v ?? 'todas'),
              ),
            ),
          ],
          const SizedBox(width: SiSpace.x3),
          Text(
            visibles == total ? '$total' : '$visibles de $total',
            style: TextStyle(
                fontSize: 12,
                color: c.ink3,
                fontFeatures: const [FontFeature.tabularFigures()]),
          ),
          if (!isNarrow) ...[
            const SizedBox(width: SiSpace.x3),
            SizedBox(
              height: 40,
              child: ElevatedButton.icon(
                onPressed: () => _showContactForm(),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Contacto',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.brand,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: const RoundedRectangleBorder(borderRadius: SiRadius.rMd),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _lista(SiColors c, List<Map<String, dynamic>> items, bool isNarrow) {
    return SelectionArea(
      child: LayoutBuilder(
        builder: (context, box) {
          final columnas = box.maxWidth >= 1500
              ? 3
              : box.maxWidth >= 1000
                  ? 2
                  : 1;

          // Se agrupa en renglones de N en lugar de armar columnas completas, para que ListView
          // siga construyendo sólo lo visible.
          final grupos = <List<Map<String, dynamic>>>[];
          for (var i = 0; i < items.length; i += columnas) {
            grupos.add(items.sublist(i, (i + columnas).clamp(0, items.length)));
          }

          return ListView.separated(
            padding: EdgeInsets.fromLTRB(
                isNarrow ? SiSpace.x4 : SiSpace.x5, SiSpace.x2,
                isNarrow ? SiSpace.x4 : SiSpace.x5, isNarrow ? 96 : SiSpace.x4),
            itemCount: grupos.length,
            separatorBuilder: (_, __) => Divider(height: 1, color: c.line2),
            itemBuilder: (ctx, i) {
              final grupo = grupos[i];
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var j = 0; j < columnas; j++) ...[
                    if (j > 0) const SizedBox(width: SiSpace.x5),
                    Expanded(
                      child: j < grupo.length
                          ? _fila(c, grupo[j])
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _fila(SiColors c, Map<String, dynamic> item) {
    String t(String k) => (item[k] ?? '').toString().trim();
    final nombre = t('nombre').isEmpty ? 'Sin nombre' : t('nombre');
    final empresa = t('empresa');
    final correo = t('correo');
    final telefono = t('telefono');
    final otro = t('otro');

    final identidad = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(color: c.brandTint, shape: BoxShape.circle),
          child: Center(
            child: Text(_iniciales(nombre),
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: c.brand)),
          ),
        ),
        const SizedBox(width: SiSpace.x2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(nombre,
                  style: TextStyle(
                      fontSize: 13,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                      color: c.ink)),
              if (empresa.isNotEmpty)
                Text(empresa,
                    style: TextStyle(fontSize: 11, height: 1.3, color: c.ink3),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        // El menú va aquí y no al final del renglón: en varias columnas el extremo derecho de la
        // celda queda lejos del nombre al que pertenece.
        SizedBox(
          width: 26,
          child: PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, size: 16, color: c.ink3),
            padding: EdgeInsets.zero,
            tooltip: 'Opciones',
            onSelected: (v) {
              if (v == 'editar') _showContactForm(contact: item);
              if (v == 'eliminar') _deleteContact(item['id']);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'editar', child: Text('Editar')),
              PopupMenuItem(value: 'eliminar', child: Text('Eliminar')),
            ],
          ),
        ),
      ],
    );

    final contacto = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (correo.isNotEmpty) _contacto(c, Icons.mail_outline, correo, 'Correo'),
        if (telefono.isNotEmpty)
          _contacto(c, Icons.phone_outlined, telefono, 'Teléfono'),
        if (otro.isNotEmpty)
          _contacto(c, Icons.info_outline, otro, 'Dato'),
        if (correo.isEmpty && telefono.isEmpty && otro.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 2),
            child: Text('Sin datos de contacto',
                style: TextStyle(fontSize: 11, color: c.ink4)),
          ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SiSpace.x2),
      child: LayoutBuilder(
        builder: (context, box) {
          // Igual que en el Directorio: multicolumna siempre apila, y sólo la columna única usa el
          // formato ancho. Con el corte en 640 el formato cambiaba a media franja.
          if (box.maxWidth < 700) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                identidad,
                const SizedBox(height: 3),
                Padding(
                  padding: const EdgeInsets.only(left: 36),
                  child: contacto,
                ),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: identidad),
              const SizedBox(width: SiSpace.x3),
              Expanded(flex: 4, child: contacto),
            ],
          );
        },
      ),
    );
  }

  Widget _contacto(SiColors c, IconData icono, String valor, String que) {
    return InkWell(
      onTap: () => _copiar(valor, que),
      borderRadius: BorderRadius.circular(5),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1.5, horizontal: 4),
        child: Row(children: [
          Icon(icono, size: 12, color: c.ink4),
          const SizedBox(width: 6),
          Flexible(
            child: Text(valor,
                style: TextStyle(fontSize: 11.5, color: c.ink2),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: 'Copiar ${que.toLowerCase()}',
            child: Icon(Icons.copy_rounded, size: 11, color: c.ink4),
          ),
        ]),
      ),
    );
  }

  static String _iniciales(String nombre) {
    final partes =
        nombre.split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
    if (partes.isEmpty) return '?';
    if (partes.length == 1) return partes.first[0].toUpperCase();
    return (partes[0][0] + partes[1][0]).toUpperCase();
  }
}
