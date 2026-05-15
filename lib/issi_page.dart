import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/si_theme.dart';

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

  Widget _buildGlassPill({required Widget child, EdgeInsetsGeometry? padding}) {
    final c = SiColors.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: padding ??
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: c.panel.withOpacity(0.85),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: c.line.withOpacity(0.4)),
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
    final c = SiColors.of(context);
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
                hintStyle: TextStyle(color: c.ink3),
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                            _currentPage = 0;
                          });
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: c.hover,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 14),
              onChanged: (v) => setState(() {
                _searchQuery = v;
                _currentPage = 0;
              }),
            ),
          ),
          const VerticalDivider(
              width: 1, thickness: 1, indent: 8, endIndent: 8),
          GestureDetector(
            onTap: () => _showItemForm(),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Icon(Icons.add, size: 22, color: c.ink),
            ),
          ),
        ],
      ),
    );
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
                  const Icon(Icons.warning_amber_rounded,
                      color: Colors.red, size: 32),
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
        await Supabase.instance.client
            .from('issi_inventory')
            .delete()
            .eq('id', id);
        _fetchItems();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Elemento eliminado correctamente')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Error al eliminar: $e'),
                backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  void _showItemForm({Map<String, dynamic>? item}) {
    final isEditing = item != null;
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 800;

    final ubicacionController = TextEditingController(text: item?['ubicacion']);
    final modeloController = TextEditingController(text: item?['modelo']);
    final nsController = TextEditingController(text: item?['n_s']);
    final imeiController = TextEditingController(text: item?['imei']);
    final cpuController = TextEditingController(text: item?['cpu']);
    final ssdController = TextEditingController(text: item?['ssd']);
    final ramController = TextEditingController(text: item?['ram']);
    final gpuController = TextEditingController(text: item?['gpu']);
    final fechaActController =
        TextEditingController(text: item?['fecha_actualizacion']);
    final valorController =
        TextEditingController(text: item?['valor']?.toString() ?? '');
    final observacionesController =
        TextEditingController(text: item?['observaciones']);

    String tipo = item?['tipo']?.toString().toUpperCase() ?? _tipos.first;
    String condicion =
        item?['condicion']?.toString().toUpperCase() ?? _condiciones.first;
    String marca = item?['marca']?.toString().toUpperCase() ?? _marcas.first;
    if (!_marcas.contains(marca)) marca = _marcas.first;

    String? selectedUsuarioId = item?['usuario_id'];
    String? selectedUsuarioNombre = item?['usuario_nombre'];

    Widget buildContent(StateSetter setDialogState) {
      Widget fieldColumn(Widget child) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [child, const SizedBox(height: 16)],
          );

      final fields = [
        fieldColumn(
          DropdownButtonFormField<String>(
            value: selectedUsuarioId,
            decoration: const InputDecoration(
                labelText: 'Usuario *', prefixIcon: Icon(Icons.person_outline)),
            isExpanded: true,
            items: _usuarios
                .map((u) => DropdownMenuItem(
                    value: u['id'] as String,
                    child: Text(u['full_name'] ?? 'Usuario')))
                .toList(),
            onChanged: (val) {
              final usuario = _usuarios.firstWhere((u) => u['id'] == val);
              setDialogState(() {
                selectedUsuarioId = val;
                selectedUsuarioNombre = usuario['full_name'];
              });
            },
          ),
        ),
        fieldColumn(
          TextField(
              controller: ubicacionController,
              decoration: const InputDecoration(
                  labelText: 'Ubicación *',
                  prefixIcon: Icon(Icons.location_on_outlined))),
        ),
        fieldColumn(
          DropdownButtonFormField<String>(
            value: tipo,
            decoration: const InputDecoration(
                labelText: 'Tipo *', prefixIcon: Icon(Icons.devices_outlined)),
            isExpanded: true,
            items: _tipos
                .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                .toList(),
            onChanged: (val) => setDialogState(() => tipo = val!),
          ),
        ),
        fieldColumn(
          DropdownButtonFormField<String>(
            value: marca,
            decoration: const InputDecoration(
                labelText: 'Marca *',
                prefixIcon: Icon(Icons.business_outlined)),
            isExpanded: true,
            items: _marcas
                .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                .toList(),
            onChanged: (val) => setDialogState(() => marca = val!),
          ),
        ),
        fieldColumn(
          TextField(
              controller: modeloController,
              decoration: const InputDecoration(
                  labelText: 'Modelo *',
                  prefixIcon: Icon(Icons.label_outlined))),
        ),
        fieldColumn(
          TextField(
              controller: nsController,
              decoration: const InputDecoration(
                  labelText: 'N/S', prefixIcon: Icon(Icons.numbers))),
        ),
        fieldColumn(
          TextField(
              controller: imeiController,
              decoration: const InputDecoration(
                  labelText: 'IMEI',
                  prefixIcon: Icon(Icons.sim_card_outlined))),
        ),
        fieldColumn(
          TextField(
              controller: cpuController,
              decoration: const InputDecoration(
                  labelText: 'CPU', prefixIcon: Icon(Icons.memory))),
        ),
        fieldColumn(
          TextField(
              controller: ssdController,
              decoration: const InputDecoration(
                  labelText: 'SSD', prefixIcon: Icon(Icons.storage))),
        ),
        fieldColumn(
          TextField(
              controller: ramController,
              decoration: const InputDecoration(
                  labelText: 'RAM', prefixIcon: Icon(Icons.sd_card))),
        ),
        fieldColumn(
          TextField(
              controller: gpuController,
              decoration: const InputDecoration(
                  labelText: 'GPU',
                  prefixIcon: Icon(Icons.videogame_asset_outlined))),
        ),
        fieldColumn(
          TextField(
              controller: valorController,
              decoration: const InputDecoration(
                  labelText: 'Valor', prefixIcon: Icon(Icons.attach_money)),
              keyboardType: TextInputType.number),
        ),
        fieldColumn(
          TextField(
            controller: fechaActController,
            decoration: const InputDecoration(
                labelText: 'Fecha Actualización',
                prefixIcon: Icon(Icons.calendar_today_outlined)),
            readOnly: true,
            onTap: () async {
              final d = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2101));
              if (d != null)
                setDialogState(() =>
                    fechaActController.text = d.toString().split(' ').first);
            },
          ),
        ),
        fieldColumn(
          DropdownButtonFormField<String>(
            value: condicion,
            decoration: const InputDecoration(
                labelText: 'Condición *',
                prefixIcon: Icon(Icons.health_and_safety_outlined)),
            isExpanded: true,
            items: _condiciones
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (val) => setDialogState(() => condicion = val!),
          ),
        ),
        fieldColumn(
          TextField(
              controller: observacionesController,
              decoration: const InputDecoration(
                  labelText: 'Observaciones',
                  prefixIcon: Icon(Icons.notes_outlined)),
              maxLines: 2),
        ),
      ];

      if (isDesktop) {
        final rows = <Widget>[];
        for (var i = 0; i < fields.length; i += 4) {
          final rowFields = fields.skip(i).take(4).toList();
          while (rowFields.length < 4) rowFields.add(const SizedBox());
          final rowChildren = <Widget>[];
          for (var j = 0; j < rowFields.length; j++) {
            if (j > 0) rowChildren.add(const SizedBox(width: 16));
            rowChildren.add(Expanded(child: rowFields[j]));
          }
          rows.add(Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: rowChildren));
        }
        return Column(mainAxisSize: MainAxisSize.min, children: rows);
      } else {
        return Column(mainAxisSize: MainAxisSize.min, children: fields);
      }
    }

    if (isDesktop) {
      showGeneralDialog(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Dismiss',
        barrierColor: Colors.black54,
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (dialogContext, animation, secondaryAnimation) {
          return Align(
            alignment: Alignment.bottomCenter,
            child: Material(
              color: Colors.transparent,
              child: SizedBox(
                width: screenWidth,
                child: StatefulBuilder(
                  builder: (context, setDialogState) {
                    final c = SiColors.of(context);
                    return Container(
                      decoration: BoxDecoration(
                          color: c.panel,
                          borderRadius:
                              const BorderRadius.vertical(top: Radius.circular(20))),
                      constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.9),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 12, horizontal: 16),
                          decoration: BoxDecoration(
                            color: c.panel,
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(20)),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2))
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              TextButton(
                                onPressed: () => Navigator.pop(dialogContext),
                                child: Text('Cancelar',
                                    style: TextStyle(
                                        fontSize: 16, color: c.ink3)),
                              ),
                              Text(
                                  isEditing
                                      ? 'Editar Elemento'
                                      : 'Nuevo Inventario',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: c.ink)),
                              TextButton(
                                onPressed: () async {
                                  if (ubicacionController.text.isEmpty ||
                                      marca.isEmpty ||
                                      modeloController.text.isEmpty ||
                                      selectedUsuarioId == null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                            content: Text(
                                                'Completa los campos obligatorios (*)')));
                                    return;
                                  }
                                  try {
                                    final data = {
                                      'ubicacion': ubicacionController.text
                                          .trim()
                                          .toUpperCase(),
                                      'tipo': tipo,
                                      'marca': marca,
                                      'modelo': modeloController.text
                                          .trim()
                                          .toUpperCase(),
                                      'n_s': nsController.text.trim().isEmpty
                                          ? null
                                          : nsController.text
                                              .trim()
                                              .toUpperCase(),
                                      'imei': imeiController.text.trim().isEmpty
                                          ? null
                                          : imeiController.text
                                              .trim()
                                              .toUpperCase(),
                                      'cpu': cpuController.text.trim().isEmpty
                                          ? null
                                          : cpuController.text
                                              .trim()
                                              .toUpperCase(),
                                      'ssd': ssdController.text.trim().isEmpty
                                          ? null
                                          : ssdController.text
                                              .trim()
                                              .toUpperCase(),
                                      'ram': ramController.text.trim().isEmpty
                                          ? null
                                          : ramController.text
                                              .trim()
                                              .toUpperCase(),
                                      'gpu': gpuController.text.trim().isEmpty
                                          ? null
                                          : gpuController.text
                                              .trim()
                                              .toUpperCase(),
                                      'fecha_actualizacion':
                                          fechaActController.text.isEmpty
                                              ? null
                                              : fechaActController.text,
                                      'valor':
                                          valorController.text.trim().isEmpty
                                              ? null
                                              : double.tryParse(
                                                  valorController.text.trim()),
                                      'condicion': condicion,
                                      'observaciones': observacionesController
                                              .text
                                              .trim()
                                              .isEmpty
                                          ? null
                                          : observacionesController.text
                                              .trim()
                                              .toUpperCase(),
                                      'usuario_id': selectedUsuarioId,
                                      'usuario_nombre': selectedUsuarioNombre,
                                    };
                                    if (isEditing) {
                                      await Supabase.instance.client
                                          .from('issi_inventory')
                                          .update(data)
                                          .eq('id', item['id']);
                                    } else {
                                      await Supabase.instance.client
                                          .from('issi_inventory')
                                          .insert(data);
                                    }
                                    if (mounted) {
                                      Navigator.pop(dialogContext);
                                      _fetchItems();
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(
                                              content: Text(isEditing
                                                  ? 'Elemento actualizado'
                                                  : 'Elemento creado con éxito'),
                                              backgroundColor:
                                                  const Color(0xFFB1CB34)));
                                    }
                                  } catch (e) {
                                    if (mounted)
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(
                                              content: Text('Error: $e'),
                                              backgroundColor: Colors.red));
                                  }
                                },
                                child: Text(isEditing ? 'Guardar' : 'Guardar',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: c.brand)),
                              ),
                            ],
                          ),
                        ),
                        Flexible(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(24),
                            child: buildContent(setDialogState),
                          ),
                        ),
                      ]),
                    );
                  },
                ),
              ),
            ),
          );
        },
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, setDialogState) {
            final c = SiColors.of(context);
            return Container(
              decoration: BoxDecoration(
                  color: c.panel,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(20))),
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.9),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: BoxDecoration(
                    color: c.panel,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(20)),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 2))
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        child: Text('Cancelar',
                            style: TextStyle(fontSize: 16, color: c.ink3)),
                      ),
                      Text(isEditing ? 'Editar Elemento' : 'Nuevo Inventario',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: c.ink)),
                      TextButton(
                        onPressed: () async {
                          if (ubicacionController.text.isEmpty ||
                              marca.isEmpty ||
                              modeloController.text.isEmpty ||
                              selectedUsuarioId == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Completa los campos obligatorios (*)')));
                            return;
                          }
                          try {
                            final data = {
                              'ubicacion':
                                  ubicacionController.text.trim().toUpperCase(),
                              'tipo': tipo,
                              'marca': marca,
                              'modelo':
                                  modeloController.text.trim().toUpperCase(),
                              'n_s': nsController.text.trim().isEmpty
                                  ? null
                                  : nsController.text.trim().toUpperCase(),
                              'imei': imeiController.text.trim().isEmpty
                                  ? null
                                  : imeiController.text.trim().toUpperCase(),
                              'cpu': cpuController.text.trim().isEmpty
                                  ? null
                                  : cpuController.text.trim().toUpperCase(),
                              'ssd': ssdController.text.trim().isEmpty
                                  ? null
                                  : ssdController.text.trim().toUpperCase(),
                              'ram': ramController.text.trim().isEmpty
                                  ? null
                                  : ramController.text.trim().toUpperCase(),
                              'gpu': gpuController.text.trim().isEmpty
                                  ? null
                                  : gpuController.text.trim().toUpperCase(),
                              'fecha_actualizacion':
                                  fechaActController.text.isEmpty
                                      ? null
                                      : fechaActController.text,
                              'valor': valorController.text.trim().isEmpty
                                  ? null
                                  : double.tryParse(
                                      valorController.text.trim()),
                              'condicion': condicion,
                              'observaciones':
                                  observacionesController.text.trim().isEmpty
                                      ? null
                                      : observacionesController.text
                                          .trim()
                                          .toUpperCase(),
                              'usuario_id': selectedUsuarioId,
                              'usuario_nombre': selectedUsuarioNombre,
                            };
                            if (isEditing) {
                              await Supabase.instance.client
                                  .from('issi_inventory')
                                  .update(data)
                                  .eq('id', item['id']);
                            } else {
                              await Supabase.instance.client
                                  .from('issi_inventory')
                                  .insert(data);
                            }
                            if (mounted) {
                              Navigator.pop(sheetContext);
                              _fetchItems();
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text(isEditing
                                          ? 'Elemento actualizado'
                                          : 'Elemento creado con éxito'),
                                      backgroundColor:
                                          const Color(0xFFB1CB34)));
                            }
                          } catch (e) {
                            if (mounted)
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text('Error: $e'),
                                      backgroundColor: Colors.red));
                          }
                        },
                        child: Text(isEditing ? 'Guardar' : 'Guardar',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: c.brand)),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: buildContent(setDialogState),
                  ),
                ),
              ]),
            );
          },
        ),
      );
    }
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
      result = result
          .where((item) => item['condicion'] == _filterCondicion)
          .toList();
    }
    return result;
  }

  Widget _buildShimmerLoading() {
    return Center(
      child: Image.asset(
        'assets/sisol_loader.gif',
        width: 150,
        errorBuilder: (context, error, stackTrace) =>
            const CircularProgressIndicator(),
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
            frame == null ? const CircularProgressIndicator() : child,
      ),
    );
  }

  Widget _buildMobileLayout(List<Map<String, dynamic>> items, ThemeData theme) {
    final c = SiColors.of(context);
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 64, color: c.line2),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isNotEmpty
                  ? 'Sin resultados para la búsqueda'
                  : 'No hay elementos en el inventario',
              style: TextStyle(color: c.ink3),
            ),
          ],
        ),
      );
    }
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
            side: BorderSide(color: c.line),
          ),
          child: ExpansionTile(
            tilePadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      item['usuario_nombre']?.toString().toUpperCase() ??
                          'SIN USUARIO',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: _getColorForCondition(
                              item['condicion']?.toString() ?? '')
                          .withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      (item['condicion'] ?? '').toString().toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: _getColorForCondition(
                            item['condicion']?.toString() ?? ''),
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
                          title: Text('Eliminar',
                              style: TextStyle(color: Colors.red)),
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
              if (item['fecha_actualizacion'] != null)
                _buildDetailRow(
                    'Fecha Actualización', item['fecha_actualizacion']),
              if (item['valor'] != null)
                _buildDetailRow('Valor', '\$${item['valor']}'),
              if (item['observaciones'] != null)
                _buildDetailRow('Observaciones', item['observaciones']),
              _buildDetailRow(
                  'Registrado por', item['usuario_nombre'] ?? 'Usuario'),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDesktopLayout(
      List<Map<String, dynamic>> filtered, ThemeData theme) {
    final c = SiColors.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          _buildDashboardCards(theme),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: c.line)),
              child: Theme(
                data: theme.copyWith(
                  cardColor: Colors.transparent,
                ),
                child: PaginatedDataTable(
                  dataRowMaxHeight: 54,
                  dataRowMinHeight: 54,
                  columnSpacing: 20,
                  horizontalMargin: 24,
                  header: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 350),
                    child: SizedBox(
                      height: 38,
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Buscar marca, modelo, ubicación, usuario...',
                          hintStyle: TextStyle(color: c.ink3, fontSize: 13),
                          prefixIcon: const Icon(Icons.search, size: 18),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 16),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                )
                              : null,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.line)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.line)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: theme.colorScheme.primary)),
                          filled: true,
                          fillColor: c.panel,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                        ),
                        style: const TextStyle(fontSize: 13),
                        onChanged: (value) => setState(() => _searchQuery = value),
                      ),
                    ),
                  ),
                  actions: [
                    if (_isAdmin)
                      SizedBox(
                        height: 38,
                        child: ElevatedButton.icon(
                          onPressed: () => _showItemForm(),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Inventario', style: TextStyle(fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.colorScheme.primary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                          ),
                        ),
                      ),
                  ],
                  columns: [
                    DataColumn(label: SizedBox(width: screenWidth * 0.2, child: Text('USUARIO / UBICACIÓN', style: TextStyle(color: c.ink3, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1)))),
                    DataColumn(label: SizedBox(width: screenWidth * 0.15, child: Text('EQUIPO', style: TextStyle(color: c.ink3, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1)))),
                    DataColumn(label: SizedBox(width: screenWidth * 0.1, child: Text('MARCA', style: TextStyle(color: c.ink3, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1)))),
                    DataColumn(label: SizedBox(width: screenWidth * 0.1, child: Text('SERIE', style: TextStyle(color: c.ink3, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1)))),
                    DataColumn(label: SizedBox(width: screenWidth * 0.1, child: Text('CONDICIÓN', style: TextStyle(color: c.ink3, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1)))),
                    const DataColumn(label: SizedBox()), // Acciones
                  ],
                  source: _IssiDataSource(
                    items: filtered,
                    theme: theme,
                    isAdmin: _isAdmin,
                    siColors: c,
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
                          style: TextStyle(
                              color: _getColorForCondition(c),
                              fontSize: 10,
                              fontWeight: FontWeight.bold),
                        ),
                      );
                    },
                    getIconForType: _getIconForType,
                    screenWidth: screenWidth,
                  ),
                  rowsPerPage: filtered.isEmpty
                      ? 1
                      : (filtered.length > 10 ? 10 : filtered.length),
                  showCheckboxColumn: false,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filteredItems;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth > 800) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _buildControls(theme),
                    ],
                  ),
                );
              },
            ),
          ),
          _isLoading
              ? SliverFillRemaining(
                  child: _buildShimmerLoading(),
                )
              : SliverFillRemaining(
                  child: LayoutBuilder(
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

  Widget _buildDashboardCards(ThemeData theme) {
    // Count by tipo
    final tipoCounts = <String, int>{};
    for (final item in _items) {
      final t = (item['tipo'] ?? 'OTRO').toString();
      tipoCounts[t] = (tipoCounts[t] ?? 0) + 1;
    }
    // Count by condicion
    final condCounts = <String, int>{};
    for (final item in _items) {
      final c = (item['condicion'] ?? 'OTRO').toString();
      condCounts[c] = (condCounts[c] ?? 0) + 1;
    }
    // Count by ubicacion
    final ubiCounts = <String, int>{};
    for (final item in _items) {
      final u = (item['ubicacion'] ?? 'SIN UBICACIÓN').toString();
      ubiCounts[u] = (ubiCounts[u] ?? 0) + 1;
    }
    final tipoSorted = tipoCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final condSorted = condCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final ubiSorted = ubiCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _buildTipoCard(tipoSorted, theme)),
        const SizedBox(width: 16),
        Expanded(child: _buildCondicionCard(condSorted, theme)),
        const SizedBox(width: 16),
        Expanded(child: _buildUbicacionCard(ubiSorted, theme)),
      ],
    );
  }

  Widget _cardShell(
      {required String title,
      required IconData icon,
      required Color accent,
      required Widget child}) {
    final c = SiColors.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: c.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 18, color: accent),
                ),
                const SizedBox(width: 10),
                Text(title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold)),
                const Spacer(),
                Text(
                  '${_items.length}',
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold, color: accent),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }

  // --- TIPO card: icon + name + progress bar ---
  Widget _buildTipoCard(List<MapEntry<String, int>> entries, ThemeData theme) {
    final c = SiColors.of(context);
    final maxVal = entries.isEmpty ? 1 : entries.first.value;
    final color = theme.colorScheme.primary;

    return _cardShell(
      title: 'Por Tipo',
      icon: Icons.devices,
      accent: color,
      child: Column(
        children: entries.map((e) {
          final fraction = e.value / maxVal;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(_getIconForType(e.key),
                    size: 18, color: color.withOpacity(0.7)),
                const SizedBox(width: 8),
                SizedBox(
                  width: 70,
                  child: Text(
                    e.key,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: fraction,
                      minHeight: 8,
                      backgroundColor: c.hover,
                      valueColor: AlwaysStoppedAnimation(
                          color.withOpacity(0.6 + 0.4 * fraction)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 24,
                  child: Text(
                    '${e.value}',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: color),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // --- CONDICIÓN card: horizontal colored bars ---
  Widget _buildCondicionCard(
      List<MapEntry<String, int>> entries, ThemeData theme) {
    final si = SiColors.of(context);
    final total = _items.length;
    final condColors = <String, Color>{
      'NUEVO': const Color(0xFF4CAF50),
      'USADO': const Color(0xFFF9A825),
      'DAÑADO': const Color(0xFFFF7043),
      'SIN REPARACION': const Color(0xFFE53935),
    };

    return _cardShell(
      title: 'Por Condición',
      icon: Icons.health_and_safety,
      accent: const Color(0xFFB1CB34),
      child: Column(
        children: [
          // Stacked bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 14,
              child: Row(
                children: entries.map((e) {
                  final c = condColors[e.key] ?? Colors.grey;
                  return Expanded(
                    flex: e.value,
                    child: Container(color: c),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Legend
          ...entries.map((e) {
            final c = condColors[e.key] ?? Colors.grey;
            final pct = total > 0 ? (e.value * 100 / total).round() : 0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                        color: c, borderRadius: BorderRadius.circular(3)),
                  ),
                  const SizedBox(width: 8),
                  Text(e.key,
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w500)),
                  const Spacer(),
                  Text('$pct%',
                      style: TextStyle(fontSize: 11, color: si.ink3)),
                  const SizedBox(width: 6),
                  Text('${e.value}',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.bold, color: c)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // --- UBICACIÓN card: compact chips ---
  Widget _buildUbicacionCard(
      List<MapEntry<String, int>> entries, ThemeData theme) {
    final color = Colors.orange;
    final top = entries.take(8).toList(); // Show top 8

    return _cardShell(
      title: 'Por Ubicación',
      icon: Icons.location_on,
      accent: color,
      child: Column(
        children: top.map((e) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Icon(Icons.place, size: 14, color: color.withOpacity(0.5)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    e.key,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${e.value}',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: color),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  void _showFilterDialog(String title, List<String> options,
      String? currentValue, Function(String?) onSelected) {
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
              child: const Text('Todos',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ...options.map((option) => SimpleDialogOption(
                onPressed: () {
                  Navigator.pop(context);
                  onSelected(option);
                },
                child: Row(
                  children: [
                    if (option == currentValue)
                      const Icon(Icons.check, size: 18, color: Colors.green),
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
    final c = SiColors.of(context);
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
                color: c.ink3,
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
      case 'LAPTOP':
        return Icons.laptop_mac;
      case 'PC':
        return Icons.desktop_mac;
      case 'IMPRESORA':
        return Icons.print;
      case 'CELULAR':
        return Icons.smartphone;
      case 'TELEFONO':
        return Icons.phone;
      case 'DISCO DURO':
        return Icons.storage;
      case 'MONITOR':
        return Icons.monitor;
      case 'MOUSE':
        return Icons.mouse;
      default:
        return Icons.devices_other;
    }
  }

  Color _getColorForCondition(String condicion) {
    switch (condicion.toUpperCase()) {
      case 'NUEVO':
        return Colors.green;
      case 'USADO':
        return Colors.orange;
      case 'DAÑADO':
        return Colors.red;
      case 'SIN REPARACION':
        return Colors.grey;
      default:
        return Colors.blueGrey;
    }
  }
}

class _IssiDataSource extends DataTableSource {
  final List<Map<String, dynamic>> items;
  final ThemeData theme;
  final bool isAdmin;
  final SiColors siColors;
  final Function(Map<String, dynamic>) onEdit;
  final Function(String) onDelete;
  final Widget Function(String) buildConditionChip;
  final IconData Function(String) getIconForType;

  final double screenWidth;

  _IssiDataSource({
    required this.items,
    required this.theme,
    required this.isAdmin,
    required this.siColors,
    required this.onEdit,
    required this.onDelete,
    required this.buildConditionChip,
    required this.getIconForType,
    required this.screenWidth,
  });

  @override
  DataRow? getRow(int index) {
    if (index >= items.length) return null;
    final item = items[index];

    return DataRow.byIndex(
      index: index,
      cells: [
        DataCell(
          SizedBox(
            width: screenWidth * 0.2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  item['usuario_nombre']?.toString().toUpperCase() ?? 'SIN USUARIO',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  item['ubicacion']?.toString() ?? '---',
                  style: TextStyle(color: siColors.ink3, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
        DataCell(
          SizedBox(
            width: screenWidth * 0.15,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Icon(getIconForType(item['tipo']?.toString() ?? ''),
                        size: 16, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      item['tipo']?.toString() ?? '---',
                      style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
                    ),
                  ],
                ),
                Text(
                  item['modelo']?.toString() ?? '---',
                  style: TextStyle(color: siColors.ink3, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
        DataCell(Text(item['marca']?.toString() ?? '---')),
        DataCell(Text(item['n_s']?.toString() ?? '---')),
        DataCell(buildConditionChip(item['condicion']?.toString() ?? '')),
        DataCell(
          Align(
            alignment: Alignment.centerRight,
            child: isAdmin
                ? PopupMenuButton<String>(
                    icon: Icon(Icons.more_horiz, color: siColors.ink3),
                    tooltip: 'Acciones',
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 4,
                    onSelected: (value) {
                      if (value == 'edit') onEdit(item);
                      if (value == 'delete') onDelete(item['id']);
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                          value: 'edit',
                          child: ListTile(
                              leading: Icon(Icons.edit_outlined, color: Colors.blue),
                              title: Text('Editar'),
                              dense: true)),
                      const PopupMenuItem(
                          value: 'delete',
                          child: ListTile(
                              leading: Icon(Icons.delete_outline, color: Colors.red),
                              title: Text('Eliminar', style: TextStyle(color: Colors.red)),
                              dense: true)),
                    ],
                  )
                : const SizedBox.shrink(),
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
