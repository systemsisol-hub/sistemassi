import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'widgets/page_header.dart';

class IssiPage extends StatefulWidget {
  const IssiPage({super.key});

  @override
  State<IssiPage> createState() => _IssiPageState();
}

class _IssiPageState extends State<IssiPage> {
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _usuarios = [];
  bool _isLoading = true;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String? _filterTipo;
  String? _filterCondicion;
  int _currentPage = 0;
  static const int _itemsPerPage = 10;
  bool _isAdmin = false;

  static const List<String> _tipos = [
    'LAPTOP',
    'PC',
    'IMPRESORA',
    'CELULAR',
    'TELEFONO',
    'DISCO DURO',
    'MONITOR',
    'MOUSE',
  ];

  static const List<String> _condiciones = [
    'NUEVO',
    'USADO',
    'DAÑADO',
    'SIN REPARACION',
  ];

  static const List<String> _marcas = [
    'AASTRA',
    'ACER',
    'ADATA',
    'ASUS',
    'DELL',
    'EDI SECURE',
    'HP',
    'HUAWEI',
    'KINGGSTON',
    'KIOCERA',
    'LENOVO',
    'MAC',
    'OTROS',
    'RICOH',
    'SAMSUNG',
    'VIEW SONIC',
    'XIAOMI',
    'ZTE',
  ];

  @override
  void initState() {
    super.initState();
    _checkAdminRole();
    _fetchItems();
    _fetchUsuarios();
  }

  Future<void> _checkAdminRole() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final role = user.userMetadata?['role'] ?? 'usuario';
        setState(() => _isAdmin = role == 'admin');
      }
    } catch (e) {
      debugPrint('Error checking admin role: $e');
    }
  }

  Future<void> _fetchUsuarios() async {
    try {
      List<Map<String, dynamic>> allUsuarios = [];
      int offset = 0;
      const int limit = 1000;
      
      while (true) {
        final data = await Supabase.instance.client
            .from('profiles')
            .select('id, full_name')
            .eq('status_sys', 'ACTIVO')
            .order('full_name')
            .range(offset, offset + limit - 1);
            
        allUsuarios.addAll(List<Map<String, dynamic>>.from(data));
        
        if (data.length < limit) break;
        offset += limit;
      }
      if (mounted) {
        setState(() {
          _usuarios = allUsuarios;
        });
      }
    } catch (e) {
      debugPrint('Error fetching usuarios: $e');
    }
  }

  Future<void> _fetchItems() async {
    setState(() => _isLoading = true);
    try {
      List<Map<String, dynamic>> allData = [];
      int offset = 0;
      const int limit = 1000;
      
      while (true) {
        final data = await Supabase.instance.client
            .from('issi_inventory')
            .select()
            .order('created_at', ascending: false)
            .range(offset, offset + limit - 1);
            
        allData.addAll(List<Map<String, dynamic>>.from(data));
        
        if (data.length < limit) break;
        offset += limit;
      }
      
      if (mounted) {
        setState(() {
          _items = allData;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching items: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar inventario: $e')),
        );
      }
    }
  }

  Future<void> _deleteItem(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Container(
          width: double.maxFinite,
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 32),
                  const SizedBox(width: 12),
                  Text(
                    'Eliminar Elemento',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                '¿Estás seguro de que deseas eliminar este elemento? Esta acción no se puede deshacer.',
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('CANCELAR'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('ELIMINAR'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed == true) {
      try {
        await Supabase.instance.client.from('issi_inventory').delete().eq('id', id);
        _fetchItems();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Elemento eliminado correctamente')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al eliminar: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  void _showItemForm({Map<String, dynamic>? item}) {
    final isEditing = item != null;
    final ubicacionController = TextEditingController(text: item?['ubicacion']);
    final marcaController = TextEditingController(text: item?['marca']);
    final modeloController = TextEditingController(text: item?['modelo']);
    final nsController = TextEditingController(text: item?['n_s']);
    final imeiController = TextEditingController(text: item?['imei']);
    final cpuController = TextEditingController(text: item?['cpu']);
    final ssdController = TextEditingController(text: item?['ssd']);
    final ramController = TextEditingController(text: item?['ram']);
    final gpuController = TextEditingController(text: item?['gpu']);
    final fechaActController = TextEditingController(text: item?['fecha_actualizacion']);
    final valorController = TextEditingController(
      text: item?['valor']?.toString() ?? '',
    );
    final observacionesController = TextEditingController(text: item?['observaciones']);
    
    String tipo = item?['tipo']?.toString().toUpperCase() ?? _tipos.first;
    String condicion = item?['condicion']?.toString().toUpperCase() ?? _condiciones.first;
    String marca = item?['marca']?.toString().toUpperCase() ?? _marcas.first;
    // If saved marca doesn't match list, fall back to first
    if (!_marcas.contains(marca)) marca = _marcas.first;

    String? selectedUsuarioId = item?['usuario_id'];
    String? selectedUsuarioNombre = item?['usuario_nombre'];

    showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: StatefulBuilder(
          builder: (context, setDialogState) => Container(
            width: double.maxFinite,
            constraints: const BoxConstraints(maxWidth: 500),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isEditing ? 'Editar Elemento' : 'Nuevo Elemento',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    DropdownButtonFormField<String>(
                      value: selectedUsuarioId,
                      decoration: const InputDecoration(
                        labelText: 'Usuario *',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      isExpanded: true,
                      items: _usuarios.map((u) => DropdownMenuItem(
                        value: u['id'] as String,
                        child: Text(u['full_name'] ?? 'Usuario'),
                      )).toList(),
                      onChanged: (val) {
                        final usuario = _usuarios.firstWhere((u) => u['id'] == val);
                        setDialogState(() {
                          selectedUsuarioId = val;
                          selectedUsuarioNombre = usuario['full_name'];
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: ubicacionController,
                      decoration: const InputDecoration(
                        labelText: 'Ubicación *',
                        prefixIcon: Icon(Icons.location_on_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: tipo,
                      decoration: const InputDecoration(
                        labelText: 'Tipo *',
                        prefixIcon: Icon(Icons.devices_outlined),
                      ),
                      isExpanded: true,
                      items: _tipos.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                      onChanged: (val) => setDialogState(() => tipo = val!),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: marca,
                      decoration: const InputDecoration(
                        labelText: 'Marca *',
                        prefixIcon: Icon(Icons.business_outlined),
                      ),
                      isExpanded: true,
                      items: _marcas.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                      onChanged: (val) => setDialogState(() => marca = val!),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: modeloController,
                      decoration: const InputDecoration(
                        labelText: 'Modelo *',
                        prefixIcon: Icon(Icons.label_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nsController,
                      decoration: const InputDecoration(
                        labelText: 'N/S',
                        prefixIcon: Icon(Icons.numbers),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: imeiController,
                      decoration: const InputDecoration(
                        labelText: 'IMEI',
                        prefixIcon: Icon(Icons.sim_card_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: cpuController,
                            decoration: const InputDecoration(
                              labelText: 'CPU',
                              prefixIcon: Icon(Icons.memory),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: ssdController,
                            decoration: const InputDecoration(
                              labelText: 'SSD',
                              prefixIcon: Icon(Icons.storage),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: ramController,
                            decoration: const InputDecoration(
                              labelText: 'RAM',
                              prefixIcon: Icon(Icons.sd_card),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: valorController,
                            decoration: const InputDecoration(
                              labelText: 'Valor',
                              prefixIcon: Icon(Icons.attach_money),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: gpuController,
                      decoration: const InputDecoration(
                        labelText: 'GPU',
                        prefixIcon: Icon(Icons.videogame_asset_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: fechaActController,
                      decoration: const InputDecoration(
                        labelText: 'Fecha de Actualización',
                        prefixIcon: Icon(Icons.calendar_today_outlined),
                      ),
                      readOnly: true,
                      onTap: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2101),
                        );
                        if (d != null) {
                          setDialogState(() => fechaActController.text = d.toString().split(' ').first);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: condicion,
                      decoration: const InputDecoration(
                        labelText: 'Condición *',
                        prefixIcon: Icon(Icons.health_and_safety_outlined),
                      ),
                      isExpanded: true,
                      items: _condiciones.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                      onChanged: (val) => setDialogState(() => condicion = val!),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: observacionesController,
                      decoration: const InputDecoration(
                        labelText: 'Observaciones',
                        prefixIcon: Icon(Icons.notes_outlined),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('CANCELAR'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              if (ubicacionController.text.isEmpty || marca.isEmpty ||
                                  modeloController.text.isEmpty || selectedUsuarioId == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Completa los campos obligatorios (*)')),
                                );
                                return;
                              }

                              try {
                                final data = {
                                  'ubicacion': ubicacionController.text.trim().toUpperCase(),
                                  'tipo': tipo,
                                  'marca': marca,
                                  'modelo': modeloController.text.trim().toUpperCase(),
                                  'n_s': nsController.text.trim().isEmpty ? null : nsController.text.trim().toUpperCase(),
                                  'imei': imeiController.text.trim().isEmpty ? null : imeiController.text.trim().toUpperCase(),
                                  'cpu': cpuController.text.trim().isEmpty ? null : cpuController.text.trim().toUpperCase(),
                                  'ssd': ssdController.text.trim().isEmpty ? null : ssdController.text.trim().toUpperCase(),
                                  'ram': ramController.text.trim().isEmpty ? null : ramController.text.trim().toUpperCase(),
                                  'gpu': gpuController.text.trim().isEmpty ? null : gpuController.text.trim().toUpperCase(),
                                  'fecha_actualizacion': fechaActController.text.isEmpty ? null : fechaActController.text,
                                  'valor': valorController.text.trim().isEmpty ? null : double.tryParse(valorController.text.trim()),
                                  'condicion': condicion,
                                  'observaciones': observacionesController.text.trim().isEmpty ? null : observacionesController.text.trim().toUpperCase(),
                                  'usuario_id': selectedUsuarioId,
                                  'usuario_nombre': selectedUsuarioNombre,
                                };

                                if (isEditing) {
                                  await Supabase.instance.client.from('issi_inventory').update(data).eq('id', item['id']);
                                } else {
                                  await Supabase.instance.client.from('issi_inventory').insert(data);
                                }

                                if (mounted) {
                                  Navigator.pop(context);
                                  _fetchItems();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(isEditing ? 'Elemento actualizado' : 'Elemento creado con éxito'),
                                      backgroundColor: const Color(0xFFB1CB34),
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                                  );
                                }
                              }
                            },
                            child: Text(isEditing ? 'GUARDAR' : 'CREAR'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> get _filteredItems {
    var result = _items;
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      result = result.where((item) {
        final marca = (item['marca'] ?? '').toString().toLowerCase();
        final modelo = (item['modelo'] ?? '').toString().toLowerCase();
        final ubicacion = (item['ubicacion'] ?? '').toString().toLowerCase();
        final usuario = (item['usuario_nombre'] ?? '').toString().toLowerCase();
        final ns = (item['n_s'] ?? '').toString().toLowerCase();
        final imei = (item['imei'] ?? '').toString().toLowerCase();
        return marca.contains(query) || 
               modelo.contains(query) || 
               ubicacion.contains(query) || 
               usuario.contains(query) || 
               ns.contains(query) ||
               imei.contains(query);
      }).toList();
    }
    if (_filterTipo != null) {
      result = result.where((item) => item['tipo'] == _filterTipo).toList();
    }
    if (_filterCondicion != null) {
      result = result.where((item) => item['condicion'] == _filterCondicion).toList();
    }
    return result;
  }

  Widget _buildShimmerLoading() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 8,
      itemBuilder: (context, index) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey[200]!)),
        child: Container(
          height: 80,
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(backgroundColor: Colors.grey[100]),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(height: 12, width: 150, color: Colors.grey[100]),
                    const SizedBox(height: 8),
                    Container(height: 10, width: 100, color: Colors.grey[100]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileLayout(List<Map<String, dynamic>> items, ThemeData theme) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = items[index];
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.grey[200]!),
          ),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            leading: CircleAvatar(
              backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
              child: Icon(
                _getIconForType(item['tipo']?.toString() ?? ''),
                color: theme.colorScheme.primary,
              ),
            ),
            title: Text(
              '${item['marca']} ${item['modelo']}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      item['usuario_nombre']?.toString().toUpperCase() ?? 'SIN USUARIO',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: _getColorForCondition(item['condicion']?.toString() ?? '').withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      (item['condicion'] ?? '').toString().toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: _getColorForCondition(item['condicion']?.toString() ?? ''),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            trailing: _isAdmin 
              ? PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'edit') {
                      _showItemForm(item: item);
                    } else if (value == 'delete') {
                      _deleteItem(item['id']);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: ListTile(
                        leading: Icon(Icons.edit, color: Colors.blue),
                        title: Text('Editar'),
                        dense: true,
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        leading: Icon(Icons.delete, color: Colors.red),
                        title: Text('Eliminar', style: TextStyle(color: Colors.red)),
                        dense: true,
                      ),
                    ),
                  ],
                )
              : null,
            children: [
              _buildDetailRow('Ubicación', item['ubicacion'] ?? '---'),
              if (item['n_s'] != null) _buildDetailRow('N/S', item['n_s']),
              if (item['imei'] != null) _buildDetailRow('IMEI', item['imei']),
              if (item['cpu'] != null) _buildDetailRow('CPU', item['cpu']),
              if (item['ssd'] != null) _buildDetailRow('SSD', item['ssd']),
              if (item['ram'] != null) _buildDetailRow('RAM', item['ram']),
              if (item['gpu'] != null) _buildDetailRow('GPU', item['gpu']),
              if (item['fecha_actualizacion'] != null) _buildDetailRow('Fecha Actualización', item['fecha_actualizacion']),
              if (item['valor'] != null) _buildDetailRow('Valor', '\$${item['valor']}'),
              if (item['observaciones'] != null) _buildDetailRow('Observaciones', item['observaciones']),
              _buildDetailRow('Registrado por', item['usuario_nombre'] ?? 'Usuario'),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDesktopLayout(List<Map<String, dynamic>> filtered, ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: SizedBox(
        width: double.infinity,
        child: Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey[200]!)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('ISSI - Inventario', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    if (_isAdmin)
                      ElevatedButton.icon(
                        onPressed: () => _showItemForm(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.secondary,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(120, 48),
                        ),
                        icon: const Icon(Icons.add),
                        label: const Text('NUEVO'),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Theme(
                data: theme.copyWith(
                  cardColor: Colors.transparent,
                ),
                child: PaginatedDataTable(
                  columns: const [
                    DataColumn(label: Text('Tipo', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Marca/Modelo', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Ubicación', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('N/S', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Usuario', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Condición', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Acciones', style: TextStyle(fontWeight: FontWeight.bold))),
                  ],
                  source: _IssiDataSource(
                    items: filtered,
                    theme: theme,
                    isAdmin: _isAdmin,
                    onEdit: (item) => _showItemForm(item: item),
                    onDelete: (id) => _deleteItem(id),
                    buildConditionChip: (condicion) {
                      final c = condicion ?? '';
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _getColorForCondition(c).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _getColorForCondition(c).withOpacity(0.5)),
                        ),
                        child: Text(
                          c.toUpperCase(),
                          style: TextStyle(color: _getColorForCondition(c), fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      );
                    },
                    getIconForType: _getIconForType,
                  ),
                  rowsPerPage: filtered.isEmpty ? 1 : (filtered.length > 10 ? 10 : filtered.length),
                  showCheckboxColumn: false,
                  horizontalMargin: 16,
                  columnSpacing: 16,
                  dataRowMinHeight: 40,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filteredItems;
    final isDesktopWidth = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      floatingActionButton: _isAdmin && !isDesktopWidth
        ? FloatingActionButton.extended(
            onPressed: () => _showItemForm(),
            backgroundColor: theme.colorScheme.secondary,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add),
            label: const Text('NUEVO'),
          )
        : null,
      body: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth > 800;
              
              final searchWidget = SizedBox(
                width: isDesktop ? 250 : double.infinity,
                height: 40,
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Buscar...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 20),
                            onPressed: () {
                              _searchController.clear();
                              setState(() { _searchQuery = ''; _currentPage = 0; });
                            },
                          )
                        : null,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                  ),
                  onChanged: (v) => setState(() { _searchQuery = v; _currentPage = 0; }),
                ),
              );

              return PageHeader(
                title: 'ISSI - Inventario',
                trailing: isDesktop ? searchWidget : null,
                bottom: isDesktop ? null : [searchWidget],
              );
            },
          ),
          Expanded(
            child: _isLoading
                ? _buildShimmerLoading()
                : filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[300]),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isNotEmpty
                                  ? 'Sin resultados para la búsqueda'
                                  : 'No hay elementos en el inventario',
                              style: TextStyle(color: Colors.grey[500]),
                            ),
                          ],
                        ),
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          if (constraints.maxWidth > 800) {
                            return _buildDesktopLayout(filtered, theme);
                          } else {
                            return _buildMobileLayout(filtered, theme);
                          }
                        },
                      ),
          ),
        ],
      ),
    );
  }

  void _showFilterDialog(String title, List<String> options, String? currentValue, Function(String?) onSelected) {
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Filtrar por $title'),
        children: [
          if (currentValue != null)
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(context);
                onSelected(null);
              },
              child: const Text('Todos', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ...options.map((option) => SimpleDialogOption(
            onPressed: () {
              Navigator.pop(context);
              onSelected(option);
            },
            child: Row(
              children: [
                if (option == currentValue) const Icon(Icons.check, size: 18, color: Colors.green),
                if (option == currentValue) const SizedBox(width: 8),
                Text(option),
              ],
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getIconForType(String tipo) {
    switch (tipo.toUpperCase()) {
      case 'LAPTOP': return Icons.laptop_mac;
      case 'PC': return Icons.desktop_mac;
      case 'IMPRESORA': return Icons.print;
      case 'CELULAR': return Icons.smartphone;
      case 'TELEFONO': return Icons.phone;
      case 'DISCO DURO': return Icons.storage;
      case 'MONITOR': return Icons.monitor;
      case 'MOUSE': return Icons.mouse;
      default: return Icons.devices_other;
    }
  }

  Color _getColorForCondition(String condicion) {
    switch (condicion.toUpperCase()) {
      case 'NUEVO': return Colors.green;
      case 'USADO': return Colors.orange;
      case 'DAÑADO': return Colors.red;
      case 'SIN REPARACION': return Colors.grey;
      default: return Colors.blueGrey;
    }
  }
}

class _IssiDataSource extends DataTableSource {
  final List<Map<String, dynamic>> items;
  final ThemeData theme;
  final bool isAdmin;
  final Function(Map<String, dynamic>) onEdit;
  final Function(String) onDelete;
  final Widget Function(String) buildConditionChip;
  final IconData Function(String) getIconForType;

  _IssiDataSource({
    required this.items,
    required this.theme,
    required this.isAdmin,
    required this.onEdit,
    required this.onDelete,
    required this.buildConditionChip,
    required this.getIconForType,
  });

  @override
  DataRow? getRow(int index) {
    if (index >= items.length) return null;
    final item = items[index];

    return DataRow.byIndex(
      index: index,
      cells: [
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(getIconForType(item['tipo']?.toString() ?? ''), size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(item['tipo']?.toString() ?? '---'),
            ],
          ),
        ),
        DataCell(Text('${item['marca'] ?? ''} ${item['modelo'] ?? ''}'.trim())),
        DataCell(Text(item['ubicacion']?.toString() ?? '---')),
        DataCell(Text(item['n_s']?.toString() ?? '---')),
        DataCell(Text(item['usuario_nombre']?.toString() ?? '---')),
        DataCell(buildConditionChip(item['condicion']?.toString() ?? '')),
        DataCell(
          isAdmin
              ? PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'edit') onEdit(item);
                    if (value == 'delete') onDelete(item['id']);
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit, color: Colors.blue), title: Text('Editar'), dense: true)),
                    const PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete, color: Colors.red), title: Text('Eliminar', style: TextStyle(color: Colors.red)), dense: true)),
                  ],
                )
              : const SizedBox.shrink(),
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
