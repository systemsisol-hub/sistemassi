import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'theme/si_theme.dart';

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

  Widget _buildControls(SiColors c) {
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
  }  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final filtered = _filteredContacts;

    return Scaffold(
      backgroundColor: c.bg,
      body: Column(
        children: [
          // Header: Search + Count
          Padding(
            padding: EdgeInsets.all(SiSpace.x6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _buildControls(c),
              ],
            ),
          ),

          // Content
          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(
                        color: c.brand, strokeWidth: 2),
                  )
                : filtered.isEmpty
                    ? _buildEmptyState(c)
                    : _buildGrid(c, filtered),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(SiColors c, List<Map<String, dynamic>> items) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(SiSpace.x6),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: SiRadius.rLg,
              side: BorderSide(color: c.line),
            ),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.all(SiSpace.x2),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 450,
                mainAxisExtent: 180,
                crossAxisSpacing: 0,
                mainAxisSpacing: 0,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return _ContactGridTile(
                  item: item,
                  onEdit: () => _showContactForm(contact: item),
                  onDelete: () => _deleteContact(item['id']),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _ContactGridTile extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ContactGridTile({
    required this.item,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final name = item['nombre'] ?? 'Sin Nombre';
    final company = item['empresa'] ?? '';
    final email = item['correo'] ?? '';
    final phone = item['telefono'] ?? '';
    final category = item['otro'] ?? '';
    final initials = name.split(' ').take(2).map((e) => e.isNotEmpty ? e[0] : '').join('').toUpperCase();

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: c.line.withOpacity(0.5), width: 0.5),
      ),
      padding: EdgeInsets.all(SiSpace.x5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: c.brandTint,
                  borderRadius: SiRadius.rMd,
                ),
                alignment: Alignment.center,
                child: Text(
                  initials,
                  style: TextStyle(
                    color: c.brand,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
              SizedBox(width: SiSpace.x4),
              // Name & Company
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: c.ink,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (company.isNotEmpty)
                      Text(
                        company,
                        style: TextStyle(
                          fontSize: 13,
                          color: c.ink3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              // Actions
              _buildPopupMenu(c),
            ],
          ),
          const Spacer(),
          // Details
          if (phone.isNotEmpty)
            _buildDetailRow(Icons.phone_outlined, phone, c),
          if (email.isNotEmpty)
            _buildDetailRow(Icons.mail_outline, email, c),
          
          SizedBox(height: SiSpace.x3),
          // Tag
          if (category.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: c.bg,
                borderRadius: SiRadius.rPill,
                border: Border.all(color: c.line),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(color: c.ink4, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    category,
                    style: TextStyle(fontSize: 11, color: c.ink3, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String text, SiColors c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: c.ink4),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, color: c.ink2),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPopupMenu(SiColors c) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, size: 18, color: c.ink4),
      onSelected: (v) {
        if (v == 'edit') onEdit();
        if (v == 'delete') onDelete();
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 16, color: c.ink2),
              const SizedBox(width: 12),
              const Text('Editar'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 16, color: c.danger),
              const SizedBox(width: 12),
              Text('Eliminar', style: TextStyle(color: c.danger)),
            ],
          ),
        ),
      ],
    );
  }
}
