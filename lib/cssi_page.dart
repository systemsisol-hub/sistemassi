import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'colaborador_detail_page.dart';
import 'theme/si_theme.dart';

class CssiPage extends StatefulWidget {
  final String role;
  const CssiPage({super.key, required this.role});

  @override
  State<CssiPage> createState() => _CssiPageState();
}

class _CssiPageState extends State<CssiPage> {
  List<Map<String, dynamic>> _items = [];
  Map<String, List<String>> _userDevices = {};
  bool _isLoading = true;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  int _currentPage = 0;
  static const int _itemsPerPage = 10;

  void _onViewCollaborator(Map<String, dynamic> item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CollaboratorDetailPage(colab: item),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _fetchItems();
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
            onTap: () => _showForm(),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Icon(Icons.add, size: 22, color: c.ink),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _fetchItems() async {
    setState(() => _isLoading = true);
    try {
      List<Map<String, dynamic>> allData = [];
      int offset = 0;
      const int limit = 1000;

      while (true) {
        final data = await Supabase.instance.client
            .from('profiles')
            .select()
            .or('nombre.not.is.null,full_name.not.is.null')
            .order('created_at', ascending: false)
            .range(offset, offset + limit - 1);

        allData.addAll(List<Map<String, dynamic>>.from(data));

        if (data.length < limit) break;
        offset += limit;
      }

      if (mounted) {
        setState(() {
          _items = allData;
        });
      }

      // Fetch assigned devices from issi_inventory
      final inventoryData = await Supabase.instance.client
          .from('issi_inventory')
          .select('usuario_id, tipo')
          .not('usuario_id', 'is', null);

      final deviceMap = <String, List<String>>{};
      for (final inv in inventoryData) {
        final uid = inv['usuario_id'] as String;
        final tipo = inv['tipo'] as String?;
        if (tipo != null) {
          deviceMap.putIfAbsent(uid, () => []).add(tipo);
        }
      }

      if (mounted) {
        setState(() {
          _userDevices = deviceMap;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching CSSI: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar colaboradores: $e')),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _filteredItems {
    var result = List<Map<String, dynamic>>.from(_items);
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      result = result.where((item) {
        final name =
            '${item['nombre']} ${item['paterno']} ${item['materno'] ?? ''}'
                .toLowerCase();
        final curp = (item['curp'] ?? '').toString().toLowerCase();
        final rfc = (item['rfc'] ?? '').toString().toLowerCase();
        final area = (item['area'] ?? '').toString().toLowerCase();
        final puesto = (item['puesto'] ?? '').toString().toLowerCase();
        final numEmp = (item['numero_empleado'] ?? '').toString().toLowerCase();
        final emailPers = (item['correo_personal'] ?? '').toString().toLowerCase();
        final emailUser = (item['mail_user'] ?? '').toString().toLowerCase();
        return name.contains(query) ||
            curp.contains(query) ||
            rfc.contains(query) ||
            area.contains(query) ||
            puesto.contains(query) ||
            numEmp.contains(query) ||
            emailPers.contains(query) ||
            emailUser.contains(query);
      }).toList();
    }
    result.sort((a, b) {
      final numA = int.tryParse(a['numero_empleado']?.toString() ?? '0') ?? 0;
      final numB = int.tryParse(b['numero_empleado']?.toString() ?? '0') ?? 0;
      return numB.compareTo(numA); // descending
    });
    return result;
  }

  int get _totalPages =>
      (_filteredItems.length / _itemsPerPage).ceil().clamp(1, 9999);

  void _deleteItem(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Colaborador'),
        content: const Text('¿Estás seguro de eliminar este registro?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCELAR')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('ELIMINAR')),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await Supabase.instance.client.from('profiles').delete().eq('id', id);
        _fetchItems();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  void _showForm({Map<String, dynamic>? item}) {
    final isEditing = item != null;
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 800;
    final c = SiColors.of(context);

    final nombreCtrl = TextEditingController(text: item?['nombre']);
    final paternoCtrl = TextEditingController(text: item?['paterno']);
    final maternoCtrl = TextEditingController(text: item?['materno']);
    final curpCtrl = TextEditingController(text: item?['curp']);
    final rfcCtrl = TextEditingController(text: item?['rfc']);
    final imssCtrl = TextEditingController(text: item?['imss']);
    final numeroEmpleadoCtrl =
        TextEditingController(text: item?['numero_empleado']);
    final fechaNacCtrl = TextEditingController(text: item?['fecha_nacimiento']);
    final detalleEscolCtrl =
        TextEditingController(text: item?['detalle_escolaridad']);
    final calleCtrl = TextEditingController(text: item?['calle']);
    final noCalleCtrl = TextEditingController(text: item?['no_calle']);
    final coloniaCtrl = TextEditingController(text: item?['colonia']);
    final municipioCtrl =
        TextEditingController(text: item?['municipio_alcaldia']);
    final estadoFedCtrl = TextEditingController(text: item?['estado_federal']);
    final cpCtrl = TextEditingController(text: item?['codigo_postal']);
    final telCtrl = TextEditingController(text: item?['telefono']);
    final celCtrl = TextEditingController(text: item?['celular']);
    final correoCtrl = TextEditingController(text: item?['correo_personal']);
    final bancoCtrl = TextEditingController(text: item?['banco']);
    final cuentaCtrl = TextEditingController(text: item?['cuenta']);
    final clabeCtrl = TextEditingController(text: item?['clabe']);
    final empresaCtrl = TextEditingController(text: item?['empresa']);
    final reclutadorCtrl = TextEditingController(text: item?['reclutador']);
    final fuenteEspecCtrl =
        TextEditingController(text: item?['fuente_reclutamiento_espec']);
    final fechaIngresoCtrl =
        TextEditingController(text: item?['fecha_ingreso']);
    final fechaReingresoCtrl =
        TextEditingController(text: item?['fecha_reingreso']);
    final fechaCambioCtrl = TextEditingController(text: item?['fecha_cambio']);
    final obsCtrl = TextEditingController(text: item?['observaciones']);
    final refNombreCtrl =
        TextEditingController(text: item?['referencia_nombre']);
    final refTelCtrl =
        TextEditingController(text: item?['referencia_telefono']);
    final refRelacionCtrl =
        TextEditingController(text: item?['referencia_relacion']);

    String? genero = item?['genero'];
    String? estadoCivil = item?['estado_civil'];
    String? escolaridad = item?['escolaridad'];
    String? credito = item?['credito'];
    String? lugarNacimiento = item?['lugar_nacimiento'];
    String? talla = item?['talla'];
    String? tipoColaborador = item?['empresa_tipo'];
    String? reclutaOption = item?['recluta'];
    String? fuenteOption = item?['fuente_reclutamiento'];
    String? statusSys = item?['status_sys'] ?? 'CAMBIO';
    String? statusRh = item?['status_rh'] ?? 'ACTIVO';
    String? horario = item?['horario'];
    String? area = item?['area'];
    String? puesto = item?['puesto'];
    String? ubicacion = item?['ubicacion'];
    String? jefeInmediato = item?['jefe_inmediato'];
    String? liderValue = item?['lider'];
    String? gerenteRegional = item?['gerente_regional'];
    String? directorValue = item?['director'];
    XFile? pickedFile;
    String? currentFotoUrl = item?['foto_url'];

    Widget buildContent(StateSetter setDialogState) {
      Widget fieldColumn(Widget child) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [child, const SizedBox(height: 16)],
          );

      // Use FutureBuilder for schedules
      Widget scheduleDropdown = FutureBuilder<List<Map<String, dynamic>>>(
        future: Supabase.instance.client
            .from('schedules')
            .select('id, name')
            .order('name')
            .then((data) => List<Map<String, dynamic>>.from(data)),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final schedules = snapshot.data ?? [];
          return DropdownButtonFormField<String>(
            value: horario,
            decoration: const InputDecoration(
              labelText: 'Horario',
              prefixIcon: Icon(Icons.schedule),
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('Sin horario')),
              ...schedules.map((s) => DropdownMenuItem(
                    value: s['id'].toString(),
                    child: Text(s['name'] ?? 'Sin nombre'),
                  )),
            ],
            onChanged: (v) => setDialogState(() => horario = v),
          );
        },
      );

      // FutureBuilder for active collaborators
      Widget supervisorDropdowns(StateSetter setDialogState) {
        return FutureBuilder<List<String>>(
          future: Supabase.instance.client
              .from('profiles')
              .select('nombre, paterno, materno')
              .eq('status_rh', 'ACTIVO')
              .order('nombre')
              .then((data) => (data as List).map((e) {
                    final n = e['nombre'] ?? '';
                    final p = e['paterno'] ?? '';
                    final m = e['materno'] ?? '';
                    return '$n $p $m'.trim().toUpperCase();
                  }).toList()),
          builder: (context, snapshot) {
            final list = snapshot.data ?? [];
            final items = [
              const DropdownMenuItem<String>(value: null, child: Text('Ninguno')),
              ...list.map((e) => DropdownMenuItem(value: e, child: Text(e)))
            ];

            return Column(
              children: [
                fieldColumn(DropdownButtonFormField<String>(
                  value: list.contains(jefeInmediato) ? jefeInmediato : null,
                  decoration: const InputDecoration(labelText: 'Jefe Inmediato'),
                  items: items,
                  onChanged: (v) => setDialogState(() => jefeInmediato = v),
                )),
                fieldColumn(DropdownButtonFormField<String>(
                  value: list.contains(liderValue) ? liderValue : null,
                  decoration: const InputDecoration(labelText: 'Líder'),
                  items: items,
                  onChanged: (v) => setDialogState(() => liderValue = v),
                )),
                fieldColumn(DropdownButtonFormField<String>(
                  value: list.contains(gerenteRegional) ? gerenteRegional : null,
                  decoration: const InputDecoration(labelText: 'Gerente Regional'),
                  items: items,
                  onChanged: (v) => setDialogState(() => gerenteRegional = v),
                )),
                fieldColumn(DropdownButtonFormField<String>(
                  value: list.contains(directorValue) ? directorValue : null,
                  decoration: const InputDecoration(labelText: 'Director'),
                  items: items,
                  onChanged: (v) => setDialogState(() => directorValue = v),
                )),
              ],
            );
          },
        );
      }

      final col1 = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.grey[200],
                  backgroundImage: pickedFile != null
                      ? null
                      : (currentFotoUrl != null
                          ? NetworkImage(currentFotoUrl)
                          : null),
                  child: pickedFile != null
                      ? ClipOval(
                          child: Image.file(File(pickedFile!.path),
                              fit: BoxFit.cover, width: 100, height: 100))
                      : (currentFotoUrl == null
                          ? const Icon(Icons.person,
                              size: 50, color: Colors.grey)
                          : null),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle),
                    child: const Icon(Icons.camera_alt,
                        color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          fieldColumn(DropdownButtonFormField<String>(
            value: statusSys,
            decoration: const InputDecoration(labelText: 'Status Sys'),
            items: ['ACTIVO', 'BAJA', 'CAMBIO', 'ELIMINAR', 'NO APLICA']
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (v) => setDialogState(() => statusSys = v),
          )),
          fieldColumn(DropdownButtonFormField<String>(
            value: statusRh,
            decoration: const InputDecoration(labelText: 'Status RH'),
            items: ['ACTIVO', 'BAJA', 'CAMBIO', 'REINGRESO']
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (v) => setDialogState(() => statusRh = v),
          )),
          fieldColumn(TextField(
              controller: numeroEmpleadoCtrl,
              decoration: const InputDecoration(
                  labelText: 'Número de Empleado *', hintText: '4 dígitos'),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4)
              ])),
          fieldColumn(TextField(
              controller: nombreCtrl,
              decoration: const InputDecoration(labelText: 'Nombre *'))),
          fieldColumn(Row(children: [
            Expanded(
                child: TextField(
                    controller: paternoCtrl,
                    decoration: const InputDecoration(labelText: 'Paterno *'))),
            const SizedBox(width: 8),
            Expanded(
                child: TextField(
                    controller: maternoCtrl,
                    decoration: const InputDecoration(labelText: 'Materno'))),
          ])),
          fieldColumn(Row(children: [
            Expanded(
                child: TextField(
                    controller: curpCtrl,
                    decoration: const InputDecoration(labelText: 'CURP'))),
            const SizedBox(width: 8),
            Expanded(
                child: TextField(
                    controller: rfcCtrl,
                    decoration: const InputDecoration(labelText: 'RFC'))),
          ])),
          fieldColumn(TextField(
              controller: imssCtrl,
              decoration: const InputDecoration(labelText: 'IMSS'))),
          fieldColumn(DropdownButtonFormField<String>(
              value: credito,
              decoration: const InputDecoration(labelText: 'Crédito'),
              items: ['FOVISTE', 'INFONAVIT', 'OTRO']
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: (v) => setDialogState(() => credito = v))),
          fieldColumn(Row(children: [
            Expanded(
                child: DropdownButtonFormField<String>(
                    value: lugarNacimiento,
                    decoration:
                        const InputDecoration(labelText: 'Lugar de Nacimiento'),
                    items: [
                      'AGUASCALIENTES',
                      'BAJA CALIFORNIA',
                      'BAJA CALIFORNIA SUR',
                      'CAMPECHE',
                      'CHIAPAS',
                      'CHIHUAHUA',
                      'COAHUILA',
                      'COLIMA',
                      'CIUDAD DE MÉXICO',
                      'DURANGO',
                      'GUANAJUATO',
                      'GUERRERO',
                      'HIDALGO',
                      'JALISCO',
                      'MÉXICO',
                      'MICHOACÁN',
                      'MORELOS',
                      'NAYARIT',
                      'NUEVO LEÓN',
                      'OAXACA',
                      'PUEBLA',
                      'QUERÉTARO',
                      'QUINTANA ROO',
                      'SAN LUIS POTOSÍ',
                      'SINALOA',
                      'SONORA',
                      'TABASCO',
                      'TAMAULIPAS',
                      'TLAXCALA',
                      'VERACRUZ',
                      'YUCATÁN',
                      'ZACATECAS',
                      'EXTRANJERO'
                    ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (v) => setDialogState(() => lugarNacimiento = v))),
          ])),
          fieldColumn(Row(children: [
            Expanded(
                child: TextField(
                    controller: fechaNacCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Fecha Nacimiento',
                        suffixIcon: Icon(Icons.calendar_today)),
                    readOnly: true,
                    onTap: () async {
                      final d = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(1950),
                          lastDate: DateTime.now());
                      if (d != null)
                        setDialogState(() =>
                            fechaNacCtrl.text = d.toString().split(' ').first);
                    })),
            const SizedBox(width: 8),
            Expanded(
                child: DropdownButtonFormField<String>(
                    value: talla,
                    decoration: const InputDecoration(labelText: 'Talla'),
                    items: ['XS', 'S', 'M', 'L', 'XL', '2XL', '3XL', '4XL']
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (v) => setDialogState(() => talla = v))),
          ])),
          fieldColumn(Row(children: [
            Expanded(
                child: DropdownButtonFormField<String>(
                    value: genero,
                    decoration: const InputDecoration(labelText: 'Género'),
                    items: ['HOMBRE', 'MUJER']
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (v) => setDialogState(() => genero = v))),
            const SizedBox(width: 8),
            Expanded(
                child: DropdownButtonFormField<String>(
                    value: estadoCivil,
                    decoration:
                        const InputDecoration(labelText: 'Estado Civil'),
                    items: ['CASADO', 'SOLTERO', 'UNION LIBRE']
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (v) => setDialogState(() => estadoCivil = v))),
          ])),
          fieldColumn(DropdownButtonFormField<String>(
              value: escolaridad,
              decoration: const InputDecoration(labelText: 'Escolaridad'),
              items: [
                'PRIMARIA',
                'SECUNDARIA',
                'BACHILLERATO',
                'CARRERA TECNICA',
                'TSU',
                'LICENCIATURA TRUNCA',
                'LICENCIATURA PASANTE',
                'LICENCIATURA TITULADO',
                'POSGRADO',
                'OTROS'
              ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: (v) => setDialogState(() => escolaridad = v))),
          fieldColumn(TextField(
              controller: detalleEscolCtrl,
              decoration:
                  const InputDecoration(labelText: 'Detalle Escolaridad'),
              maxLines: 2)),
        ],
      );

      final col2 = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle('Domicilio'),
          fieldColumn(Row(children: [
            Expanded(
                flex: 3,
                child: TextField(
                    controller: calleCtrl,
                    decoration: const InputDecoration(labelText: 'Calle'))),
            const SizedBox(width: 8),
            Expanded(
                child: TextField(
                    controller: noCalleCtrl,
                    decoration: const InputDecoration(labelText: 'No. Calle'))),
          ])),
          fieldColumn(TextField(
              controller: coloniaCtrl,
              decoration: const InputDecoration(labelText: 'Colonia'))),
          fieldColumn(Row(children: [
            Expanded(
                child: TextField(
                    controller: municipioCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Municipio/Alcaldía'))),
            const SizedBox(width: 8),
            Expanded(
                child: TextField(
                    controller: cpCtrl,
                    decoration: const InputDecoration(labelText: 'C.P.'))),
          ])),
          fieldColumn(TextField(
              controller: estadoFedCtrl,
              decoration: const InputDecoration(labelText: 'Estado Federal'))),
          const SizedBox(height: 24),
          _sectionTitle('Contacto Personal'),
          fieldColumn(Row(children: [
            Expanded(
                child: TextField(
                    controller: telCtrl,
                    decoration: const InputDecoration(labelText: 'Teléfono'))),
            const SizedBox(width: 8),
            Expanded(
                child: TextField(
                    controller: celCtrl,
                    decoration: const InputDecoration(labelText: 'Celular'))),
          ])),
          fieldColumn(TextField(
              controller: correoCtrl,
              decoration: const InputDecoration(labelText: 'Email'))),
          const SizedBox(height: 24),
          _sectionTitle('Datos Bancarios'),
          fieldColumn(TextField(
              controller: bancoCtrl,
              decoration: const InputDecoration(labelText: 'Banco'))),
          fieldColumn(Row(children: [
            Expanded(
                child: TextField(
                    controller: cuentaCtrl,
                    decoration: const InputDecoration(labelText: 'Cuenta'))),
            const SizedBox(width: 8),
            Expanded(
                child: TextField(
                    controller: clabeCtrl,
                    decoration: const InputDecoration(labelText: 'Clabe'))),
          ])),
          const SizedBox(height: 24),
          _sectionTitle('Datos Empresa'),
          fieldColumn(DropdownButtonFormField<String>(
              value: tipoColaborador,
              decoration: const InputDecoration(labelText: 'Tipo'),
              items: [
                'ASIMILADOS',
                'BACK OFFICE',
                'MANTENIMIENTO',
                'MERCADO SECUNDARIO',
                'SI SOL'
              ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: (v) => setDialogState(() => tipoColaborador = v))),
          fieldColumn(DropdownButtonFormField<String>(
              value: area,
              decoration: const InputDecoration(labelText: 'Área'),
              items: [
                'ADMINISTRACION DE VENTAS',
                'ANALISTA DE TI',
                'ATN. CLIENTES',
                'AUXILIAR DE RESTAURANTE',
                'COMERCIAL',
                'CONSTRUCCION',
                'CONTADOR GENERAL',
                'CONTROL PRESUPUESTAL',
                'COORDINADOR OAP',
                'DESARROLLO HUMANO',
                'DIRECCION GENERAL',
                'DIRECTOR DE PROYECTOS',
                'DIRECTOR GENERAL',
                'FINANZAS',
                'GERENTE DE OBRA',
                'JURIDICO',
                'LIMPIEZA',
                'MANTENIMIENTO',
                'MARKETING',
                'MERCADOTECNIA',
                'MERCADO_SECUNDARIO',
                'OLYMPIA',
                'POSTVENTA',
                'POSVENTA',
                'PROYECTO OBRA',
                'RESIDENTE DE URBANIZACIÓN',
                'RESTAURANTE',
                'SISTEMAS',
                'TITULACION',
                'TITULACION MS'
              ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: (v) => setDialogState(() => area = v))),
          fieldColumn(DropdownButtonFormField<String>(
              value: puesto,
              decoration: const InputDecoration(labelText: 'Puesto'),
              items: [
                'ABOGADO',
                'ABOGADO FREELANCE',
                'ADMINISTRACIÓN DE VENTAS',
                'ADMINISTRADOR DE CREDITOS Y AVALUOS',
                'ADMINISTRADOR DE OBRA',
                'ADMINISTRADOR DE REDES SOCIALES',
                'ADMINISTRADOR DE VENTAS',
                'ADMINISTRADORA',
                'AGENTE INMOBILIARIO',
                'ALMACEN',
                'ANALISTA ADMINISTRATIVO',
                'ANALISTA CONTABLE',
                'ANALISTA DE BASES DE DATOS',
                'ANALISTA DE CONTROL PRESUPUESTAL',
                'ANALISTA DE DESARROLLO HUMANO',
                'ANALISTA DE DISEÑO Y MARKETING',
                'ANALISTA DE GESTIONES Y TRAMITES',
                'ANALISTA DE OBRA SOLIDA',
                'ANALISTA DE SISTEMAS',
                'ANALISTA DE TI',
                'ANALISTA DE TITULACION',
                'ANALISTA MERCADO SECUNDARIO',
                'ASESOR DE CALL CENTER',
                'ASESOR LEGAL',
                'ASISTENTE DE DIRECCION',
                'ATENCION A CLIENTES',
                'AUXILIAR ADMINISTRATIVO',
                'AUXILIAR ADMINISTRATIVO CONTABLE',
                'AUXILIAR CONTABLE',
                'AUXILIAR DE ALMACEN',
                'AUXILIAR DE CONTROL DE OBRA',
                'AUXILIAR DE CONTROL PRESUPUESTAL',
                'AUXILIAR DE MANTENIMIENTO',
                'AUXILIAR DE NOMINA',
                'AUXILIAR DE OBRA',
                'AUXILIAR DE SUPERVISION',
                'AUXILIAR DE TITULACION',
                'AUXILIAR DE TOPOGRAFO',
                'AUXILIAR GENERAL',
                'AUXILIAR OAP',
                'AUXILIAR RH',
                'AUXILIAR TECNICO',
                'BECARIA DE MERCADOTECNIA',
                'BECARIO ADMINISTRACION',
                'BECARIO DE FINANZAS',
                'BECARIO DESARROLLO HUMANO',
                'BECARIO MKT',
                'BECARIO RH',
                'CADENERO',
                'COMERCIALIZADOR EXTERNO',
                'COMISIONISTA EXTERNO',
                'COMISIONISTA INTERNO',
                'COMMUNITY MANAGER',
                'COMPRAS',
                'CONTADOR',
                'CONTADOR GENERAL',
                'CONTADOR JR.',
                'CONTADORA',
                'CONTRALOR',
                'CONTRALORA',
                'CONTROL DE ALMACEN',
                'CONTROL DE AVANCES FISCALES FINANCIEROS',
                'CONTROL PRESUPUESTAL',
                'COORDINACIÓN DE PROYECTOS',
                'COORDINADOR ADMINISTRATIVO',
                'COORDINADOR DE ACABADOS',
                'COORDINADOR DE ESTRUCTURA ALTAMAR',
                'COORDINADOR DE ESTRUCTURA SOLIDA',
                'COORDINADOR DE MERCADOTECNIA',
                'COORDINADOR DE OFICINA DE ADMINISTRACION DE PROYECTOS',
                'COORDINADOR DE PROYECTO',
                'COORDINADOR DE TESORERIA',
                'COORDINADOR DE TITULACION',
                'COORDINADOR DE URBANIZACION',
                'COORDINADOR DE VENTAS',
                'COORDINADOR DESARROLLO HUMANO',
                'COORDINADOR JURIDICO MS',
                'COORDINADOR MERCADO SECUNDARIO',
                'COORDINADOR OAP',
                'COORDINADORA DE INFORMACION',
                'COORDINADORA DE OBRA',
                'CUANTIFICADOR',
                'CUBRE TURNOS',
                'DESALOJADOR EXTERNO',
                'DESARROLLO HUMANO',
                'DETALLISTA DE POSVENTA',
                'DIRECTOR COMERCIAL',
                'DIRECTOR DE ADMINISTRACION Y FINANZAS',
                'DIRECTOR DE ÁREA TECNICA',
                'DIRECTOR DE OPERACIONES',
                'DIRECTOR DE PROYECTOS',
                'DIRECTOR GENERAL',
                'DIRECTOR JURIDICO',
                'DIRECTORA DE PROYECTO',
                'DISEÑADOR GRAFICO',
                'EJECUTIVA DE POSVENTA',
                'ENCARGADA DE OBRA',
                'ENCARGADA DE POSTVENTA',
                'ENCARGADO DE COCINA',
                'ENCARGADO DE COMISIONES',
                'ENCARGADO DE GESTIONES',
                'ENCARGADO DE TURNO',
                'ENTREGA DE OBRA',
                'ENTREGA DE VIVIENDA Y VICIOS OCULTOS',
                'FACTURACION',
                'FRANQUICIA EXTERNA',
                'FREELANCE MK',
                'GERENTE COMERCIAL',
                'GERENTE CONTROL PRESUPUESTAL',
                'GERENTE DE ADMINISTRACION DE VENTAS',
                'GERENTE DE ADMINISTRACION Y FINANZAS',
                'GERENTE DE CONSTRUCCION',
                'GERENTE DE DESARROLLO HUMANO',
                'GERENTE DE IMPLEMENTACION Y SOPORTE',
                'GERENTE DE MERCADO SECUNDARIO',
                'GERENTE DE OBRA',
                'GERENTE DE OPERACIONES',
                'GERENTE DE POSVENTA',
                'GERENTE DE PROMOTORIAS',
                'GERENTE DE PROYECTO',
                'GERENTE DE SISTEMAS Y MANTENIMIENTO',
                'GERENTE DE TIENDA',
                'GERENTE DE TITULACION',
                'GERENTE REGIONAL DE VENTAS',
                'GERENTE T.I.',
                'GERENTE TECNICO',
                'GERENTE TECNICO DE OBRA',
                'GESTOR',
                'GESTOR ADMINISTRATIVO',
                'INTENDENTE',
                'INTENDENTE DE ESTRUCTURA',
                'INTENDENTE DE OBRA',
                'INTENDENTE DE OBRA SOLIDA',
                'JEFE DE ALMACEN',
                'JEFE DE MANTENIMIENTO',
                'JEFE DE OBRA',
                'JEFE DE TITULACION',
                'JEFE DE TRADE MARKETING',
                'JEFE DE VENTAS',
                'LIDER DE VENTAS',
                'LIMPIEZA',
                'LOCALIZADOR DE VIVIENDA',
                'MANTENIMIENTO GENERAL',
                'MARKETING',
                'MERCADO SECUNDARIO',
                'OFICIAL DE ACABADOS',
                'OPERACIONES',
                'PLOMERO',
                'POSVENTA',
                'RECEPCIONISTA',
                'RESIDENTE DE ACABADOS',
                'RESIDENTE DE ALBAÑILERIAS Y ACABADOS',
                'RESIDENTE DE CALIDAD',
                'RESIDENTE DE OBRA',
                'RESIDENTE DE POSTVENTA',
                'RESIDENTE DE URBANIZACION',
                'RESPONSABLE DE ADMINISTRACION DE VENTAS Y TITULACION',
                'RESPONSABLE DE OBRA SOLIDA',
                'RESPONSABLE OPERATIVO DE RESTAURANTE',
                'SALVAVIDAS',
                'SUP. DE REHABILITACION Y ENTREGAS',
                'SUPERINTENDENTE DE ACABADOS',
                'SUPERINTENDENTE DE OBRA',
                'SUPERINTENDENTE DE URBANIZACIÓN',
                'SUPERVISORA DE OBRA',
                'TESORERIA',
                'TITULACION',
                'TITULACION MS',
                'TOPOGRAFO',
                'TRAMITES Y PERMISOS',
                'VELADOR',
                'VIGILANTE'
              ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: (v) => setDialogState(() => puesto = v))),
          fieldColumn(DropdownButtonFormField<String>(
              value: ubicacion,
              decoration: const InputDecoration(labelText: 'Ubicación'),
              items: [
                'AG117_ABRAHAM_GONZALEZ',
                'ALTAMAR',
                'AZCAPOTZALCO',
                'BONANZA_PRISMA',
                'COMVIVE MORELOS',
                'COMVIVE_ZUMPANGO_I',
                'COMVIVE_ZUMPANGO_II',
                'CONSTITUYENTES',
                'CUAUTITLAN',
                'CUENTAS_ESPECIALES',
                'CUMBRES_DE_SAYAVEDRA',
                'DISTRITO_LA_PLAZA',
                'DISTRITO_LA_SELVA',
                'ENSENADA',
                'GUADALAJARA',
                'GUERRERO',
                'KOOX',
                'LA RAZA',
                'LA_ESTANCIA',
                'MERCADO_SECUNDARIO',
                'MISIONES STA ESPERANZA',
                'MONTERREY',
                'MORELOS',
                'MORELOS_RESIDENCIAL',
                'OLYMPIA',
                'PROMOTORA_AEROPUERTO',
                'PROMOTORA_CDMX',
                'PROMOTORA_ECATEPEC',
                'PROMOTORA_ECATEPEC_II',
                'PROMOTORA_GUADALAJARA',
                'PROMOTORA_INDIOS_VERDES',
                'PROMOTORA_MORELOS',
                'PROMOTORA_NORTE',
                'PROMOTORA_NOURIAN',
                'PROMOTORA_PACHUCA',
                'PROMOTORA_PUEBLA',
                'PROMOTORA_SAYAVEDRA',
                'PROMOTORA_TEPEJI',
                'PROMOTORA_TEPOTZOTLAN',
                'PROMOTORA_TLALNEPANTLA',
                'PROMOTORA_TOLUCA',
                'PROMOTORA_ZUMPANGO',
                'PROYECTO_VIDAMAR',
                'PUEBLA',
                'QUERETARO',
                'QUINTANA_ROO',
                'SALTO_DEL_AGUA',
                'SALTO_DEL_AGUA_I',
                'SALTO_DEL_AGUA_II',
                'SELVA_NORTE',
                'SISOL_DIAMANTE',
                'TEPEJI',
                'TEPEJI_I',
                'TEPEJI_II',
                'TLALNEPANTLA',
                'TLALNEPANTLA_I',
                'TLALNEPANTLA_II',
                'TLALNEPANTLA_III',
                'TLAXCALA',
                'TOLUCA',
                'TORRE_II',
                'TORRE_III',
                'TORRE_LATINO',
                'TULUM',
                'VIDAMAR',
                'VILLAS_BONANZA',
                'VOLANTEO',
                'ZENESIS',
                'ZUMPANGO'
              ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: (v) => setDialogState(() => ubicacion = v))),
          fieldColumn(TextField(
              controller: empresaCtrl,
              decoration: const InputDecoration(labelText: 'Empresa'))),
          supervisorDropdowns(setDialogState),
          fieldColumn(scheduleDropdown),
        ],
      );

      final col3 = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle('Area RH'),
          fieldColumn(DropdownButtonFormField<String>(
              value: reclutaOption,
              decoration: const InputDecoration(labelText: 'Recluta'),
              items: [
                'ASESOR INMOBILIARIO',
                'BACK OFFICE',
                'DESARROLLO HUMANO',
                'OTRO'
              ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: (v) => setDialogState(() => reclutaOption = v))),
          fieldColumn(TextField(
              controller: reclutadorCtrl,
              decoration: const InputDecoration(labelText: 'Reclutador'))),
          fieldColumn(DropdownButtonFormField<String>(
              value: fuenteOption,
              decoration:
                  const InputDecoration(labelText: 'Fuente de reclutamiento'),
              items: [
                'ANUNCIO DE PERIODICO',
                'BANNER',
                'BANNER EN CESI',
                'BOLSA DE TRABAJO ESCUELA',
                'COMPUTRABAJO',
                'FACEBOOK',
                'FERIA DEL EMPLEO',
                'INDEED',
                'JOB AND JOB',
                'OCC',
                'OTRO',
                'OUTSOURCING',
                'RECOMENDACIÓN',
                'TALENTECA',
                'TWITER',
                'VOLANTEO'
              ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: (v) => setDialogState(() => fuenteOption = v))),
          fieldColumn(TextField(
              controller: fuenteEspecCtrl,
              decoration: const InputDecoration(labelText: 'Fuente espec.'))),
          fieldColumn(Row(children: [
            Expanded(
                child: TextField(
                    controller: fechaIngresoCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Fecha Ingreso',
                        suffixIcon: Icon(Icons.calendar_today)),
                    readOnly: true,
                    onTap: () async {
                      final d = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2101));
                      if (d != null)
                        setDialogState(() => fechaIngresoCtrl.text =
                            d.toString().split(' ').first);
                    })),
            const SizedBox(width: 8),
            Expanded(
                child: TextField(
                    controller: fechaReingresoCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Fecha Reingreso',
                        suffixIcon: Icon(Icons.calendar_today)),
                    readOnly: true,
                    onTap: () async {
                      final d = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2101));
                      if (d != null)
                        setDialogState(() => fechaReingresoCtrl.text =
                            d.toString().split(' ').first);
                    })),
          ])),
          fieldColumn(TextField(
              controller: fechaCambioCtrl,
              decoration: const InputDecoration(
                  labelText: 'Fecha Cambio',
                  suffixIcon: Icon(Icons.calendar_today)),
              readOnly: true,
              onTap: () async {
                final d = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2101));
                if (d != null)
                  setDialogState(() =>
                      fechaCambioCtrl.text = d.toString().split(' ').first);
              })),
          fieldColumn(TextField(
              controller: obsCtrl,
              decoration: const InputDecoration(labelText: 'Observaciones'),
              maxLines: 5,
              minLines: 5,
              keyboardType: TextInputType.multiline)),
          const SizedBox(height: 24),
          _sectionTitle('Referencia'),
          fieldColumn(TextField(
              controller: refNombreCtrl,
              decoration:
                  const InputDecoration(labelText: 'Nombre Referencia'))),
          fieldColumn(Row(children: [
            Expanded(
                child: TextField(
                    controller: refTelCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Teléfono Ref.'))),
            const SizedBox(width: 8),
            Expanded(
                child: TextField(
                    controller: refRelacionCtrl,
                    decoration: const InputDecoration(labelText: 'Relación'))),
          ])),
          const SizedBox(height: 40),
        ],
      );

      if (isDesktop) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: col1),
          const SizedBox(width: 32),
          Expanded(child: col2),
          const SizedBox(width: 32),
          Expanded(child: col3),
        ]);
      } else {
        return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              col1,
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 24),
              col2,
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 24),
              col3,
            ]);
      }
    }

    Future<void> saveData(StateSetter setDialogState, bool saving) async {
      if (nombreCtrl.text.isEmpty ||
          paternoCtrl.text.isEmpty ||
          numeroEmpleadoCtrl.text.length != 4) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Nombre, Paterno y Num. Empleado (4 dígitos) son obligatorios'),
            backgroundColor: Colors.red));
        return;
      }
      setDialogState(() => saving = true);
      String? toUpper(String val) =>
          val.trim().isEmpty ? null : val.trim().toUpperCase();
      final data = {
        'nombre': toUpper(nombreCtrl.text)!,
        'paterno': toUpper(paternoCtrl.text)!,
        'materno': toUpper(maternoCtrl.text),
        'curp': toUpper(curpCtrl.text),
        'rfc': toUpper(rfcCtrl.text),
        'imss': toUpper(imssCtrl.text),
        'credito': credito,
        'fecha_nacimiento':
            fechaNacCtrl.text.isEmpty ? null : fechaNacCtrl.text,
        'genero': genero,
        'talla': talla,
        'estado_civil': estadoCivil,
        'escolaridad': escolaridad,
        'detalle_escolaridad': toUpper(detalleEscolCtrl.text),
        'calle': toUpper(calleCtrl.text),
        'no_calle': toUpper(noCalleCtrl.text),
        'colonia': toUpper(coloniaCtrl.text),
        'municipio_alcaldia': toUpper(municipioCtrl.text),
        'estado_federal': toUpper(estadoFedCtrl.text),
        'codigo_postal': toUpper(cpCtrl.text),
        'telefono': toUpper(telCtrl.text),
        'celular': toUpper(celCtrl.text),
        'correo_personal': correoCtrl.text.trim().isEmpty
            ? null
            : correoCtrl.text.trim().toLowerCase(),
        'banco': toUpper(bancoCtrl.text),
        'cuenta': toUpper(cuentaCtrl.text),
        'clabe': toUpper(clabeCtrl.text),
        'area': area,
        'puesto': puesto,
        'ubicacion': ubicacion,
        'empresa': toUpper(empresaCtrl.text),
        'jefe_inmediato': jefeInmediato,
        'lider': liderValue,
        'gerente_regional': gerenteRegional,
        'director': directorValue,
        'lugar_nacimiento': lugarNacimiento,
        'empresa_tipo': tipoColaborador,
        'recluta': reclutaOption,
        'reclutador': toUpper(reclutadorCtrl.text),
        'fuente_reclutamiento': fuenteOption,
        'fuente_reclutamiento_espec': toUpper(fuenteEspecCtrl.text),
        'fecha_ingreso':
            fechaIngresoCtrl.text.isEmpty ? null : fechaIngresoCtrl.text,
        'fecha_reingreso':
            fechaReingresoCtrl.text.isEmpty ? null : fechaReingresoCtrl.text,
        'fecha_cambio':
            fechaCambioCtrl.text.isEmpty ? null : fechaCambioCtrl.text,
        'observaciones': toUpper(obsCtrl.text),
        'referencia_nombre': toUpper(refNombreCtrl.text),
        'referencia_telefono': toUpper(refTelCtrl.text),
        'referencia_relacion': toUpper(refRelacionCtrl.text),
        'numero_empleado': numeroEmpleadoCtrl.text.trim(),
        'status_sys': statusSys,
        'status_rh': statusRh,
        'horario': horario,
        'foto_url': currentFotoUrl,
      };
      try {
        if (pickedFile != null) {
          final bytes = await pickedFile!.readAsBytes();
          final fileExt = pickedFile!.path.split('.').last;
          final fileName = '${DateTime.now().millisecondsSinceEpoch}.$fileExt';
          final path = 'photos/$fileName';
          await Supabase.instance.client.storage
              .from('employee_photos')
              .uploadBinary(path, bytes);
          data['foto_url'] = Supabase.instance.client.storage
              .from('employee_photos')
              .getPublicUrl(path);
        }
        if (isEditing) {
          await Supabase.instance.client
              .from('profiles')
              .update(data)
              .eq('id', item['id']);
        } else {
          await Supabase.instance.client.from('profiles').insert(data);
        }
        if (mounted) {
          Navigator.pop(context);
          _fetchItems();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(isEditing
                  ? 'Colaborador actualizado exitosamente'
                  : 'Colaborador creado exitosamente (Estado: CAMBIO)'),
              backgroundColor: const Color(0xFFB1CB34)));
        }
      } catch (e) {
        setDialogState(() => saving = false);
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }

    Widget buildHeader(
        StateSetter setDialogState, bool saving, VoidCallback onCancel) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: c.panel,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
              onPressed: onCancel,
              child: Text('Cancelar',
                  style: TextStyle(fontSize: 16, color: c.ink3)),
            ),
            Text(isEditing ? 'Editar Colaborador' : 'Nuevo Colaborador',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            TextButton(
              onPressed: () => saveData(setDialogState, saving),
              child: saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text('Guardar',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: c.brand)),
            ),
          ],
        ),
      );
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
                    bool saving = false;
                    return Container(
                      decoration: BoxDecoration(
                          color: c.panel,
                          borderRadius:
                              const BorderRadius.vertical(top: Radius.circular(20))),
                      constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.9),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        buildHeader(setDialogState, saving,
                            () => Navigator.pop(dialogContext)),
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
            bool saving = false;
            return Container(
              decoration: BoxDecoration(
                  color: c.panel,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(20))),
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.9),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                buildHeader(
                    setDialogState, saving, () => Navigator.pop(sheetContext)),
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

  Widget _buildStatusChip(String status, String prefix) {
    Color color;
    switch (status) {
      case 'ACTIVO':
        color = Colors.green;
        break;
      case 'BAJA':
        color = Colors.red;
        break;
      case 'CAMBIO':
        color = Colors.orange;
        break;
      case 'ELIMINAR':
        color = Colors.purple;
        break;
      case 'REINGRESO':
        color = Colors.blue;
        break;
      default:
        color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        '$prefix: $status',
        style:
            TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    final c = SiColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title.toUpperCase(),
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: c.brand,
                fontSize: 13,
                letterSpacing: 1)),
        const Divider(),
        const SizedBox(height: 8),
      ],
    );
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

  Widget _buildMobileLayout(List<Map<String, dynamic>> filtered) {
    final c = SiColors.of(context);
    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.badge_outlined, size: 64, color: c.line2),
            const SizedBox(height: 16),
            Text('No se encontraron colaboradores', style: TextStyle(color: c.ink3)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _fetchItems,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: filtered.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final item = filtered[index];
          return Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: c.line)),
            child: ListTile(
              onTap: () => _onViewCollaborator(item),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              leading: CircleAvatar(
                backgroundColor: const Color(0xFF344092).withOpacity(0.1),
                backgroundImage: item['foto_url'] != null
                    ? NetworkImage(item['foto_url'])
                    : null,
                child: item['foto_url'] == null
                    ? Text((item['nombre'] ?? '?')[0],
                        style: const TextStyle(
                            color: Color(0xFF344092),
                            fontWeight: FontWeight.bold))
                    : null,
              ),
              title: Text(
                  '${item['numero_empleado'] ?? '---'} | ${item['nombre']} ${item['paterno']}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _buildStatusChip(item['status_rh'] ?? 'ACTIVO', 'RH'),
                      if (_userDevices.containsKey(item['id'])) ...[
                        const SizedBox(width: 8),
                        ..._userDevices[item['id']]!.take(3).map(
                            (tipo) => _buildMiniIcon(_getIconForType(tipo))),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  _buildStatusChip(item['status_sys'] ?? 'ACTIVO', 'SYS'),
                ],
              ),
              trailing: widget.role == 'admin'
                  ? PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'edit') {
                          _showForm(item: item);
                        } else if (value == 'delete') {
                          _deleteItem(item['id']);
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: ListTile(
                            leading: Icon(Icons.edit),
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
            ),
          );
        },
      ),
    );
  }

  Widget _buildDesktopLayout(
      List<Map<String, dynamic>> filtered, ThemeData theme) {
    final screenWidth = MediaQuery.of(context).size.width;
    final c = SiColors.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: c.line)),
        child: SizedBox(
          width: double.infinity,
          child: PaginatedDataTable(
            dataRowMaxHeight: 54,
            dataRowMinHeight: 54,
            columnSpacing: 40,
            horizontalMargin: 24,
            header: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 350),
              child: SizedBox(
                height: 38,
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Buscar por nombre, correo, ID...',
                    hintStyle: TextStyle(color: c.ink3, fontSize: 13),
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                                _currentPage = 0;
                              });
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
                  onChanged: (value) => setState(() {
                    _searchQuery = value;
                    _currentPage = 0;
                  }),
                ),
              ),
            ),
            actions: [
              if (widget.role == 'admin')
                SizedBox(
                  height: 38,
                  child: ElevatedButton.icon(
                    onPressed: () => _showForm(),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Colaborador', style: TextStyle(fontWeight: FontWeight.bold)),
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
              DataColumn(label: SizedBox(width: screenWidth * 0.25, child: Text('COLABORADOR', style: TextStyle(color: c.ink3, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1)))),
              DataColumn(label: SizedBox(width: screenWidth * 0.08, child: Text('ID', style: TextStyle(color: c.ink3, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1)))),
              DataColumn(label: SizedBox(width: screenWidth * 0.15, child: Text('PUESTO', style: TextStyle(color: c.ink3, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1)))),
              DataColumn(label: SizedBox(width: screenWidth * 0.15, child: Text('UBICACIÓN', style: TextStyle(color: c.ink3, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1)))),
              DataColumn(label: SizedBox(width: screenWidth * 0.12, child: Text('ESTADO', style: TextStyle(color: c.ink3, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1)))),
              const DataColumn(label: SizedBox()),
            ],
            source: _CssiDataSource(
              items: filtered,
              theme: theme,
              siColors: c,
              isAdmin: widget.role == 'admin',
              onEdit: (item) => _showForm(item: item),
              onDelete: (id) => _deleteItem(id),
              buildStatusChip: _buildStatusChip,
              userDevices: _userDevices,
              screenWidth: screenWidth,
              onView: _onViewCollaborator,
            ),
            rowsPerPage: filtered.isEmpty
                ? 1
                : (filtered.length > 10 ? 10 : filtered.length),
            showCheckboxColumn: false,
          ),
        ),
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
          if (MediaQuery.of(context).size.width <= 800)
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
                  child: _buildShimmerLoading(),
                )
              : SliverFillRemaining(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth > 800) {
                        return _buildDesktopLayout(filtered, theme);
                      } else {
                        return _buildMobileLayout(filtered);
                      }
                    },
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildMiniIcon(IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Icon(
        icon,
        size: 14,
        color: const Color(0xFF344092),
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
}

class _CssiDataSource extends DataTableSource {
  final List<Map<String, dynamic>> items;
  final ThemeData theme;
  final SiColors siColors;
  final bool isAdmin;
  final Function(Map<String, dynamic>) onEdit;
  final Function(String) onDelete;
  final Widget Function(String, String) buildStatusChip;
  final Map<String, List<String>> userDevices;
  final double screenWidth;

  _CssiDataSource({
    required this.items,
    required this.theme,
    required this.siColors,
    required this.isAdmin,
    required this.onEdit,
    required this.onDelete,
    required this.buildStatusChip,
    required this.userDevices,
    required this.screenWidth,
    required this.onView,
  });

  final Function(Map<String, dynamic>) onView;

  @override
  DataRow? getRow(int index) {
    if (index >= items.length) return null;
    final item = items[index];

    final nombre = '${item['nombre'] ?? ''} ${item['paterno'] ?? ''} ${item['materno'] ?? ''}'.trim();
    final parts = nombre.split(' ').where((e) => e.isNotEmpty).toList();
    final initials = parts.length > 1 ? '${parts[0][0]}${parts[1][0]}'.toUpperCase() : (parts.isNotEmpty ? parts[0][0].toUpperCase() : '?');

    final statusRh = item['status_rh'] ?? 'ACTIVO';
    final statusSys = item['status_sys'] ?? 'CAMBIO';

    return DataRow.byIndex(
      index: index,
      onSelectChanged: (_) => onView(item),
      cells: [
        DataCell(
          SizedBox(
            width: screenWidth * 0.25,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(0xFF344092).withOpacity(0.15),
                  backgroundImage: item['foto_url'] != null ? NetworkImage(item['foto_url']) : null,
                  child: item['foto_url'] == null ? Text(initials, style: const TextStyle(color: Color(0xFF344092), fontSize: 12, fontWeight: FontWeight.bold)) : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(nombre.isEmpty ? 'Sin Nombre' : nombre, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(item['mail_user'] ?? item['correo_personal'] ?? '', style: TextStyle(color: siColors.ink3, fontSize: 11), overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        DataCell(SizedBox(width: screenWidth * 0.08, child: Text(item['numero_empleado']?.toString() ?? '----', style: TextStyle(fontSize: 13, color: siColors.ink)))),
        DataCell(SizedBox(width: screenWidth * 0.15, child: Text(item['puesto'] ?? '---', style: TextStyle(fontSize: 13, color: siColors.ink), overflow: TextOverflow.ellipsis))),
        DataCell(SizedBox(width: screenWidth * 0.15, child: Text(item['ubicacion'] ?? '---', style: TextStyle(fontSize: 13, color: siColors.ink), overflow: TextOverflow.ellipsis))),
        DataCell(
          SizedBox(
            width: screenWidth * 0.12,
            child: Align(
              alignment: Alignment.centerLeft,
              child: buildStatusChip(statusRh, 'RH'),
            ),
          ),
        ),
        DataCell(
          Align(
            alignment: Alignment.centerRight,
            child: isAdmin ? PopupMenuButton<String>(
              icon: Icon(Icons.more_horiz, color: siColors.ink3),
              onSelected: (v) {
                if (v == 'edit') onEdit(item);
                if (v == 'delete') onDelete(item['id']);
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit, size: 20), title: Text('Editar'), dense: true, contentPadding: EdgeInsets.zero)),
                const PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete, color: Colors.red, size: 20), title: Text('Eliminar', style: TextStyle(color: Colors.red)), dense: true, contentPadding: EdgeInsets.zero)),
              ],
            ) : const SizedBox(),
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

  Widget _buildMiniIcon(IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Icon(
        icon,
        size: 14,
        color: const Color(0xFF344092),
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
}
