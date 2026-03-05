import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'widgets/page_header.dart';

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
          SnackBar(content: Text('Error al cargar contactos: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _filteredContacts {
    if (_searchQuery.isEmpty) return _contacts;
    return _contacts.where((c) {
      final nombre = (c['nombre'] ?? '').toString().toLowerCase();
      final empresa = (c['empresa'] ?? '').toString().toLowerCase();
      final query = _searchQuery.toLowerCase();
      return nombre.contains(query) || empresa.contains(query);
    }).toList();
  }

  Future<void> _deleteContact(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Contacto'),
        content: const Text('¿Estás seguro de que deseas eliminar este contacto?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCELAR')),
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
        await Supabase.instance.client.from('external_contacts').delete().eq('id', id);
        _fetchContacts();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Contacto eliminado')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
        }
      }
    }
  }

  void _showContactForm({Map<String, dynamic>? contact}) {
    final isEditing = contact != null;
    final nombreController = TextEditingController(text: contact?['nombre']);
    final empresaController = TextEditingController(text: contact?['empresa']);
    final correoController = TextEditingController(text: contact?['correo']);
    final telefonoController = TextEditingController(text: contact?['telefono']);
    final otroController = TextEditingController(text: contact?['otro']);

    showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: StatefulBuilder(
          builder: (context, setDialogState) {
            final isWeb = MediaQuery.of(context).size.width > 800;
            
            Widget buildFields() {
              final fields = [
                TextField(controller: nombreController, decoration: const InputDecoration(labelText: 'Nombre *', prefixIcon: Icon(Icons.person))),
                const SizedBox(height: 16),
                TextField(controller: empresaController, decoration: const InputDecoration(labelText: 'Empresa', prefixIcon: Icon(Icons.business))),
                const SizedBox(height: 16),
                TextField(controller: correoController, decoration: const InputDecoration(labelText: 'Correo', prefixIcon: Icon(Icons.email))),
                const SizedBox(height: 16),
                TextField(controller: telefonoController, decoration: const InputDecoration(labelText: 'Teléfono', prefixIcon: Icon(Icons.phone))),
                const SizedBox(height: 16),
                TextField(controller: otroController, decoration: const InputDecoration(labelText: 'Otro', prefixIcon: Icon(Icons.more_horiz))),
              ];

              if (isWeb) {
                return Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: fields.map((f) => SizedBox(width: (1200 - 64 - 32) / 3, child: f)).toList(),
                );
              }
              return Column(children: fields);
            }

            return Container(
              width: double.maxFinite,
              constraints: BoxConstraints(maxWidth: isWeb ? 1200 : 500),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(isEditing ? 'Editar Contacto' : 'Nuevo Contacto', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 24),
                  Flexible(child: SingleChildScrollView(child: buildFields())),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR')),
                      const SizedBox(width: 16),
                      ElevatedButton(
                        onPressed: () async {
                          if (nombreController.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('El nombre es obligatorio')));
                            return;
                          }
                          try {
                            final data = {
                              'nombre': nombreController.text.trim(),
                              'empresa': empresaController.text.trim(),
                              'correo': correoController.text.trim(),
                              'telefono': telefonoController.text.trim(),
                              'otro': otroController.text.trim(),
                              'created_by': Supabase.instance.client.auth.currentUser?.id,
                            };

                            if (isEditing) {
                              await Supabase.instance.client.from('external_contacts').update(data).eq('id', contact['id']);
                            } else {
                              await Supabase.instance.client.from('external_contacts').insert(data);
                            }

                            if (mounted) {
                              Navigator.pop(context);
                              _fetchContacts();
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isEditing ? 'Contacto actualizado' : 'Contacto creado')));
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                            }
                          }
                        },
                        child: Text(isEditing ? 'GUARDAR' : 'CREAR'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWeb = MediaQuery.of(context).size.width > 800;
    final filtered = _filteredContacts;

    return Scaffold(
      body: _isLoading
          ? Center(
              child: Image.asset(
                'assets/sisol_loader.gif',
                width: 150,
                errorBuilder: (context, error, stackTrace) => const CircularProgressIndicator(),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1400),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (isWeb) _buildWebHeader() else _buildMobileHeader(),
                            const SizedBox(height: 24),
                            if (isWeb) _buildWebTable(filtered) else _buildMobileList(filtered),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
      floatingActionButton: !isWeb ? FloatingActionButton(
        onPressed: () => _showContactForm(),
        backgroundColor: const Color(0xFF344092),
        child: const Icon(Icons.add, color: Colors.white),
      ) : null,
    );
  }

  Widget _buildWebHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'Contactos Externos',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF344092)),
        ),
        Row(
          children: [
            SizedBox(
              width: 300,
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Buscar contacto...',
                  prefixIcon: const Icon(Icons.search),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onChanged: (val) => setState(() => _searchQuery = val),
              ),
            ),
            const SizedBox(width: 16),
            ElevatedButton.icon(
              onPressed: () => _showContactForm(),
              icon: const Icon(Icons.add),
              label: const Text('NUEVO CONTACTO'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(200, 50),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMobileHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Contactos Externos',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF344092)),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Buscar contacto...',
            prefixIcon: const Icon(Icons.search),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onChanged: (val) => setState(() => _searchQuery = val),
        ),
      ],
    );
  }

  Widget _buildWebTable(List<Map<String, dynamic>> items) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xFF344092).withOpacity(0.05)),
          columns: const [
            DataColumn(label: Text('Nombre', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Empresa', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Correo', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Teléfono', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Otro', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Acciones', style: TextStyle(fontWeight: FontWeight.bold))),
          ],
          rows: items.map((c) => DataRow(cells: [
            DataCell(Text(c['nombre'] ?? '')),
            DataCell(Text(c['empresa'] ?? '')),
            DataCell(Text(c['correo'] ?? '')),
            DataCell(Text(c['telefono'] ?? '')),
            DataCell(Text(c['otro'] ?? '')),
            DataCell(Row(
              children: [
                IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: () => _showContactForm(contact: c)),
                IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _deleteContact(c['id'])),
              ],
            )),
          ])).toList(),
        ),
      ),
    );
  }

  Widget _buildMobileList(List<Map<String, dynamic>> items) {
    if (items.isEmpty) {
      return const Center(child: Padding(padding: EdgeInsets.all(40), child: Text('No hay contactos cubriendo los filtros')));
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final c = items[index];
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.grey[200]!),
          ),
          child: ListTile(
            title: Text(c['nombre'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (c['empresa'] != null && c['empresa'].toString().isNotEmpty)
                  Text('🏢 ${c['empresa']}'),
                if (c['telefono'] != null && c['telefono'].toString().isNotEmpty)
                  Text('📞 ${c['telefono']}'),
              ],
            ),
            trailing: PopupMenuButton(
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 20), SizedBox(width: 8), Text('Editar')])),
                const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 20, color: Colors.red), SizedBox(width: 8), Text('Eliminar', style: TextStyle(color: Colors.red))])),
              ],
              onSelected: (val) {
                if (val == 'edit') _showContactForm(contact: c);
                if (val == 'delete') _deleteContact(c['id']);
              },
            ),
          ),
        );
      },
    );
  }
}
