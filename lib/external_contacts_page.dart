import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';

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

  @override
  void initState() {
    super.initState();
    _fetchContacts();
  }

  Widget _buildGlassPill({required Widget child, EdgeInsetsGeometry? padding}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: padding ??
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.85),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.grey.withOpacity(0.2)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildControls(ThemeData theme) {
    return _buildGlassPill(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Buscar...',
                hintStyle: TextStyle(color: Colors.grey.shade400),
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey.shade100,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 14),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
          const VerticalDivider(
              width: 1, thickness: 1, indent: 8, endIndent: 8),
          GestureDetector(
            onTap: () => _showContactForm(),
            child: const Padding(
              padding: EdgeInsets.all(8.0),
              child: Icon(Icons.add, size: 22, color: Colors.black87),
            ),
          ),
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
          .order('nombre');

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
    if (_searchQuery.isEmpty) return _contacts;
    return _contacts.where((c) {
      final nombre = (c['nombre'] ?? '').toString().toLowerCase();
      final empresa = (c['empresa'] ?? '').toString().toLowerCase();
      final correo = (c['correo'] ?? '').toString().toLowerCase();
      final query = _searchQuery.toLowerCase();
      return nombre.contains(query) ||
          empresa.contains(query) ||
          correo.contains(query);
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
        await Supabase.instance.client
            .from('external_contacts')
            .delete()
            .eq('id', id);
        _fetchContacts();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Contacto eliminado')));
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filteredContacts;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _buildControls(theme),
                ],
              ),
            ),
          ),
          _isLoading
              ? SliverFillRemaining(
                  child: Center(
                    child: Image.asset(
                      'assets/sisol_loader.gif',
                      width: 150,
                      errorBuilder: (context, error, stackTrace) =>
                          const CircularProgressIndicator(),
                    ),
                  ),
                )
              : filtered.isEmpty
                  ? SliverFillRemaining(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.contact_phone_outlined,
                                size: 64, color: Colors.grey[300]),
                            const SizedBox(height: 16),
                            const Text('No hay contactos registrados',
                                style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      ),
                    )
                  : SliverFillRemaining(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final isDesktop = constraints.maxWidth > 800;
                          return isDesktop
                              ? _buildDesktopLayout(filtered, theme)
                              : _buildMobileLayout(filtered);
                        },
                      ),
                    ),
        ],
      ),
    );
  }

  Widget _buildDesktopLayout(
      List<Map<String, dynamic>> items, ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey[200]!)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  child: Row(
                    children: [
                      const Text('Lista de Contactos',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                const Divider(height: 1),
                PaginatedDataTable(
                  columns: const [
                    DataColumn(
                        label: Text('Nombre',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(
                        label: Text('Empresa',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(
                        label: Text('Correo',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(
                        label: Text('Teléfono',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(
                        label: Text('Otro',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(
                        label: Text('Acciones',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                  ],
                  source: _ContactsDataSource(
                    items: items,
                    onEdit: (c) => _showContactForm(contact: c),
                    onDelete: (id) => _deleteContact(id),
                  ),
                  rowsPerPage: items.isEmpty
                      ? 1
                      : (items.length > 10 ? 10 : items.length),
                  showCheckboxColumn: false,
                  horizontalMargin: 24,
                  columnSpacing: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileLayout(List<Map<String, dynamic>> items) {
    return RefreshIndicator(
      onRefresh: _fetchContacts,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final c = items[index];
          return Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey[200]!)),
            child: ListTile(
              title: Text(c['nombre'] ?? '',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (c['correo'] != null && c['correo'].toString().isNotEmpty)
                    Text('✉️ ${c['correo']}'),
                  if (c['telefono'] != null &&
                      c['telefono'].toString().isNotEmpty)
                    Text('📞 ${c['telefono']}'),
                ],
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') _showContactForm(contact: c);
                  if (value == 'delete') _deleteContact(c['id']);
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                      value: 'edit',
                      child: ListTile(
                          leading: Icon(Icons.edit),
                          title: Text('Editar'),
                          dense: true)),
                  const PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                          leading: Icon(Icons.delete, color: Colors.red),
                          title: Text('Eliminar',
                              style: TextStyle(color: Colors.red)),
                          dense: true)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ContactsDataSource extends DataTableSource {
  final List<Map<String, dynamic>> items;
  final Function(Map<String, dynamic>) onEdit;
  final Function(String) onDelete;

  _ContactsDataSource(
      {required this.items, required this.onEdit, required this.onDelete});

  @override
  DataRow? getRow(int index) {
    if (index >= items.length) return null;
    final c = items[index];
    return DataRow.byIndex(
      index: index,
      cells: [
        DataCell(Text(c['nombre'] ?? '')),
        DataCell(Text(c['empresa'] ?? '')),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(c['correo'] ?? ''),
              if (c['correo'] != null && c['correo'].toString().isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.copy, size: 16, color: Colors.grey),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(
                        text: (c['correo'] ?? '').toString().trim()));
                  },
                  tooltip: 'Copiar correo',
                ),
            ],
          ),
        ),
        DataCell(Text(c['telefono'] ?? '')),
        DataCell(Text(c['otro'] ?? '')),
        DataCell(
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'edit') onEdit(c);
              if (value == 'delete') onDelete(c['id']);
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                  value: 'edit',
                  child: ListTile(
                      leading: Icon(Icons.edit, color: Colors.blue),
                      title: Text('Editar'),
                      dense: true)),
              const PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                      leading: Icon(Icons.delete, color: Colors.red),
                      title:
                          Text('Eliminar', style: TextStyle(color: Colors.red)),
                      dense: true)),
            ],
          ),
        ),
      ],
    );
  }

  @override
  bool get isRowCountApproximate => false;
  @override
  int get rowCount => items.length;
  @override
  int get selectedRowCount => 0;
}
