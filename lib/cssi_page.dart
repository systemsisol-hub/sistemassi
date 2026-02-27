import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'widgets/page_header.dart';

class CssiPage extends StatefulWidget {
  final String role;
  const CssiPage({super.key, required this.role});

  @override
  State<CssiPage> createState() => _CssiPageState();
}

class _CssiPageState extends State<CssiPage> {
  List<Map<String, dynamic>> _items = [];
  bool _isLoading = true;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  int _currentPage = 0;
  static const int _itemsPerPage = 10;

  @override
  void initState() {
    super.initState();
    _fetchItems();
  }

  Future<void> _fetchItems() async {
    setState(() => _isLoading = true);
    try {
      final data = await Supabase.instance.client
          .from('profiles')
          .select()
          .or('nombre.not.is.null,full_name.not.is.null')
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _items = List<Map<String, dynamic>>.from(data);
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
        final name = '${item['nombre']} ${item['paterno']} ${item['materno'] ?? ''}'.toLowerCase();
        final curp = (item['curp'] ?? '').toString().toLowerCase();
        final rfc = (item['rfc'] ?? '').toString().toLowerCase();
        final area = (item['area'] ?? '').toString().toLowerCase();
        final puesto = (item['puesto'] ?? '').toString().toLowerCase();
        final numEmp = (item['numero_empleado'] ?? '').toString().toLowerCase();
        return name.contains(query) || curp.contains(query) || rfc.contains(query) || area.contains(query) || puesto.contains(query) || numEmp.contains(query);
      }).toList();
    }
    result.sort((a, b) {
      final numA = int.tryParse(a['numero_empleado']?.toString() ?? '0') ?? 0;
      final numB = int.tryParse(b['numero_empleado']?.toString() ?? '0') ?? 0;
      return numB.compareTo(numA); // descending
    });
    return result;
  }

  int get _totalPages => (_filteredItems.length / _itemsPerPage).ceil().clamp(1, 9999);

  void _deleteItem(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Colaborador'),
        content: const Text('¿Estás seguro de eliminar este registro?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCELAR')),
          TextButton(onPressed: () => Navigator.pop(context, true), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('ELIMINAR')),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await Supabase.instance.client.from('profiles').delete().eq('id', id);
        _fetchItems();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  void _showForm({Map<String, dynamic>? item}) {
    final isEditing = item != null;
    bool saving = false;
    
    final nombreCtrl = TextEditingController(text: item?['nombre']);
    final paternoCtrl = TextEditingController(text: item?['paterno']);
    final maternoCtrl = TextEditingController(text: item?['materno']);
    final curpCtrl = TextEditingController(text: item?['curp']);
    final rfcCtrl = TextEditingController(text: item?['rfc']);
    final imssCtrl = TextEditingController(text: item?['imss']);
    final numeroEmpleadoCtrl = TextEditingController(text: item?['numero_empleado']);
    
    final fechaNacCtrl = TextEditingController(text: item?['fecha_nacimiento']);
    final tallaCtrl = TextEditingController(text: item?['talla']);
    final detalleEscolCtrl = TextEditingController(text: item?['detalle_escolaridad']);
    
    final calleCtrl = TextEditingController(text: item?['calle']);
    final noCalleCtrl = TextEditingController(text: item?['no_calle']);
    final coloniaCtrl = TextEditingController(text: item?['colonia']);
    final municipioCtrl = TextEditingController(text: item?['municipio_alcaldia']);
    final estadoFedCtrl = TextEditingController(text: item?['estado_federal']);
    final cpCtrl = TextEditingController(text: item?['codigo_postal']);
    
    final telCtrl = TextEditingController(text: item?['telefono']);
    final celCtrl = TextEditingController(text: item?['celular']);
    final correoCtrl = TextEditingController(text: item?['correo_personal']);
    
    final bancoCtrl = TextEditingController(text: item?['banco']);
    final cuentaCtrl = TextEditingController(text: item?['cuenta']);
    final clabeCtrl = TextEditingController(text: item?['clabe']);
    
    final areaCtrl = TextEditingController(text: item?['area']);
    final puestoCtrl = TextEditingController(text: item?['puesto']);
    final ubicacionCtrl = TextEditingController(text: item?['ubicacion']);
    final empresaCtrl = TextEditingController(text: item?['empresa']);
    final jefeCtrl = TextEditingController(text: item?['jefe_inmediato']);
    final liderCtrl = TextEditingController(text: item?['lider']);
    final gerenteCtrl = TextEditingController(text: item?['gerente_regional']);
    final directorCtrl = TextEditingController(text: item?['director']);
    
    final reclutaCtrl = TextEditingController(text: item?['recluta']);
    final reclutadorCtrl = TextEditingController(text: item?['reclutador']);
    final fuenteCtrl = TextEditingController(text: item?['fuente_reclutamiento']);
    final fuenteEspecCtrl = TextEditingController(text: item?['fuente_reclutamiento_espec']);
    
    final fechaIngresoCtrl = TextEditingController(text: item?['fecha_ingreso']);
    final fechaReingresoCtrl = TextEditingController(text: item?['fecha_reingreso']);
    final fechaCambioCtrl = TextEditingController(text: item?['fecha_cambio']);
    
    final obsCtrl = TextEditingController(text: item?['observaciones']);
    
    final refNombreCtrl = TextEditingController(text: item?['referencia_nombre']);
    final refTelCtrl = TextEditingController(text: item?['referencia_telefono']);
    final refRelacionCtrl = TextEditingController(text: item?['referencia_relacion']);

    String? genero = item?['genero'];
    String? estadoCivil = item?['estado_civil'];
    String? escolaridad = item?['escolaridad'];
    String? credito = item?['credito'];
    String? statusSys = item?['status_sys'] ?? 'CAMBIO';
    String? statusRh = item?['status_rh'] ?? 'ACTIVO';
    XFile? pickedFile;
    String? currentFotoUrl = item?['foto_url'];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: StatefulBuilder(
          builder: (context, setDialogState) {
            final theme = Theme.of(context);
            final isDesktop = MediaQuery.of(context).size.width > 900;

            final Widget col1 = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sectionTitle('SI Colaborador'),
                Center(
                  child: GestureDetector(
                    onTap: () async {
                      final picker = ImagePicker();
                      final image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
                      if (image != null) setDialogState(() => pickedFile = image);
                    },
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 50,
                          backgroundColor: Colors.grey[200],
                          backgroundImage: pickedFile != null 
                            ? null 
                            : (currentFotoUrl != null ? NetworkImage(currentFotoUrl) : null),
                          child: pickedFile != null 
                            ? ClipOval(child: Image.file(File(pickedFile!.path), fit: BoxFit.cover, width: 100, height: 100))
                            : (currentFotoUrl == null ? const Icon(Icons.person, size: 50, color: Colors.grey) : null),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(color: theme.colorScheme.primary, shape: BoxShape.circle),
                            child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: statusSys,
                        decoration: const InputDecoration(labelText: 'Status Sys'),
                        items: ['ACTIVO', 'BAJA', 'CAMBIO', 'ELIMINAR'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                        onChanged: (v) => setDialogState(() => statusSys = v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: statusRh,
                        decoration: const InputDecoration(labelText: 'Status RH'),
                        items: ['ACTIVO', 'BAJA', 'CAMBIO', 'REINGRESO'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                        onChanged: (v) => setDialogState(() => statusRh = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: numeroEmpleadoCtrl,
                  decoration: const InputDecoration(labelText: 'Número de Empleado *', hintText: '4 dígitos'),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(controller: nombreCtrl, decoration: const InputDecoration(labelText: 'Nombre *')),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: TextField(controller: paternoCtrl, decoration: const InputDecoration(labelText: 'Paterno *'))),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: maternoCtrl, decoration: const InputDecoration(labelText: 'Materno'))),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: TextField(controller: curpCtrl, decoration: const InputDecoration(labelText: 'CURP'))),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: rfcCtrl, decoration: const InputDecoration(labelText: 'RFC'))),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(controller: imssCtrl, decoration: const InputDecoration(labelText: 'IMSS')),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: credito,
                  decoration: const InputDecoration(labelText: 'Crédito'),
                  items: ['FOVISTE', 'INFONAVIT', 'OTRO'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                  onChanged: (v) => setDialogState(() => credito = v),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: fechaNacCtrl,
                        decoration: const InputDecoration(labelText: 'Fecha Nacimiento', suffixIcon: Icon(Icons.calendar_today)),
                        readOnly: true,
                        onTap: () async {
                          final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(1950), lastDate: DateTime.now());
                          if (d != null) setDialogState(() => fechaNacCtrl.text = d.toString().split(' ').first);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: tallaCtrl, decoration: const InputDecoration(labelText: 'Talla'))),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: genero,
                        decoration: const InputDecoration(labelText: 'Género'),
                        items: ['HOMBRE', 'MUJER'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                        onChanged: (v) => setDialogState(() => genero = v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: estadoCivil,
                        decoration: const InputDecoration(labelText: 'Estado Civil'),
                        items: ['CASADO', 'SOLTERO', 'UNION LIBRE'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                        onChanged: (v) => setDialogState(() => estadoCivil = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: escolaridad,
                  decoration: const InputDecoration(labelText: 'Escolaridad'),
                  items: ['PRIMARIA', 'SECUNDARIA', 'BACHILLERATO', 'CARRERA TECNICA', 'TSU', 'LICENCIATURA TRUNCA', 'LICENCIATURA PASANTE', 'LICENCIATURA TITULADO', 'POSGRADO', 'OTROS']
                      .map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                  onChanged: (v) => setDialogState(() => escolaridad = v),
                ),
                const SizedBox(height: 12),
                TextField(controller: detalleEscolCtrl, decoration: const InputDecoration(labelText: 'Detalle Escolaridad'), maxLines: 2),
              ],
            );

            final Widget col2 = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sectionTitle('Domicilio'),
                Row(
                  children: [
                    Expanded(flex: 3, child: TextField(controller: calleCtrl, decoration: const InputDecoration(labelText: 'Calle'))),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: noCalleCtrl, decoration: const InputDecoration(labelText: 'No. Calle'))),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(controller: coloniaCtrl, decoration: const InputDecoration(labelText: 'Colonia')),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: TextField(controller: municipioCtrl, decoration: const InputDecoration(labelText: 'Municipio/Alcaldía'))),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: cpCtrl, decoration: const InputDecoration(labelText: 'C.P.'))),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(controller: estadoFedCtrl, decoration: const InputDecoration(labelText: 'Estado Federal')),

                const SizedBox(height: 24),
                _sectionTitle('Contacto Personal'),
                Row(
                  children: [
                    Expanded(child: TextField(controller: telCtrl, decoration: const InputDecoration(labelText: 'Teléfono'))),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: celCtrl, decoration: const InputDecoration(labelText: 'Celular'))),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(controller: correoCtrl, decoration: const InputDecoration(labelText: 'Correo Personal')),

                const SizedBox(height: 24),
                _sectionTitle('Datos Bancarios'),
                TextField(controller: bancoCtrl, decoration: const InputDecoration(labelText: 'Banco')),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: TextField(controller: cuentaCtrl, decoration: const InputDecoration(labelText: 'Cuenta'))),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: clabeCtrl, decoration: const InputDecoration(labelText: 'Clabe'))),
                  ],
                ),
              ],
            );

            final Widget col3 = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sectionTitle('Datos Empresa'),
                TextField(controller: empresaCtrl, decoration: const InputDecoration(labelText: 'Empresa')),
                const SizedBox(height: 12),
                TextField(controller: areaCtrl, decoration: const InputDecoration(labelText: 'Área')),
                const SizedBox(height: 12),
                TextField(controller: puestoCtrl, decoration: const InputDecoration(labelText: 'Puesto')),
                const SizedBox(height: 12),
                TextField(controller: ubicacionCtrl, decoration: const InputDecoration(labelText: 'Ubicación')),
                const SizedBox(height: 12),
                TextField(controller: jefeCtrl, decoration: const InputDecoration(labelText: 'Jefe Inmediato')),
                const SizedBox(height: 12),
                TextField(controller: liderCtrl, decoration: const InputDecoration(labelText: 'Líder')),
                const SizedBox(height: 12),
                TextField(controller: gerenteCtrl, decoration: const InputDecoration(labelText: 'Gerente Regional')),
                const SizedBox(height: 12),
                TextField(controller: directorCtrl, decoration: const InputDecoration(labelText: 'Director')),

                const SizedBox(height: 24),
                _sectionTitle('Area RH'),
                TextField(controller: reclutaCtrl, decoration: const InputDecoration(labelText: 'Recluta')),
                const SizedBox(height: 12),
                TextField(controller: reclutadorCtrl, decoration: const InputDecoration(labelText: 'Reclutador')),
                const SizedBox(height: 12),
                TextField(controller: fuenteCtrl, decoration: const InputDecoration(labelText: 'Fuente de reclutamiento')),
                const SizedBox(height: 12),
                TextField(controller: fuenteEspecCtrl, decoration: const InputDecoration(labelText: 'Fuente espec.')),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: fechaIngresoCtrl,
                        decoration: const InputDecoration(labelText: 'Fecha Ingreso', suffixIcon: Icon(Icons.calendar_today)),
                        readOnly: true,
                        onTap: () async {
                          final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2101));
                          if (d != null) setDialogState(() => fechaIngresoCtrl.text = d.toString().split(' ').first);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: fechaReingresoCtrl,
                        decoration: const InputDecoration(labelText: 'Fecha Reingreso', suffixIcon: Icon(Icons.calendar_today)),
                        readOnly: true,
                        onTap: () async {
                          final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2101));
                          if (d != null) setDialogState(() => fechaReingresoCtrl.text = d.toString().split(' ').first);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: fechaCambioCtrl,
                  decoration: const InputDecoration(labelText: 'Fecha Cambio', suffixIcon: Icon(Icons.calendar_today)),
                  readOnly: true,
                  onTap: () async {
                    final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2101));
                    if (d != null) setDialogState(() => fechaCambioCtrl.text = d.toString().split(' ').first);
                  },
                ),
                const SizedBox(height: 12),
                TextField(controller: obsCtrl, decoration: const InputDecoration(labelText: 'Observaciones'), maxLines: 2),

                const SizedBox(height: 24),
                _sectionTitle('Referencia'),
                TextField(controller: refNombreCtrl, decoration: const InputDecoration(labelText: 'Nombre Referencia')),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: TextField(controller: refTelCtrl, decoration: const InputDecoration(labelText: 'Teléfono Ref.'))),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: refRelacionCtrl, decoration: const InputDecoration(labelText: 'Relación'))),
                  ],
                ),
                const SizedBox(height: 40),
              ],
            );

            return Container(
              width: double.maxFinite,
              constraints: BoxConstraints(
                maxWidth: isDesktop ? 1200 : 500,
                maxHeight: MediaQuery.of(context).size.height * 0.9,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 24, top: 24, right: 24, bottom: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isEditing ? 'Editar Colaborador' : 'Nuevo Colaborador',
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: isDesktop
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: col1),
                                const SizedBox(width: 32),
                                Expanded(child: col2),
                                const SizedBox(width: 32),
                                Expanded(child: col3),
                              ],
                            )
                          : Column(
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
                              ],
                            ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Row(
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
                          onPressed: saving ? null : () async {
                            if (nombreCtrl.text.isEmpty || paternoCtrl.text.isEmpty || numeroEmpleadoCtrl.text.length != 4) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Nombre, Paterno y Num. Empleado (4 dígitos) son obligatorios'), 
                                  backgroundColor: Colors.red
                                )
                              );
                              return;
                            }
                            
                            setDialogState(() => saving = true);

                            String? toUpper(String val) => val.trim().isEmpty ? null : val.trim().toUpperCase();
                            
                            final data = {
                              'nombre': toUpper(nombreCtrl.text)!,
                              'paterno': toUpper(paternoCtrl.text)!,
                              'materno': toUpper(maternoCtrl.text),
                              'curp': toUpper(curpCtrl.text),
                              'rfc': toUpper(rfcCtrl.text),
                              'imss': toUpper(imssCtrl.text),
                              'credito': credito,
                              'fecha_nacimiento': fechaNacCtrl.text.isEmpty ? null : fechaNacCtrl.text,
                              'genero': genero,
                              'talla': toUpper(tallaCtrl.text),
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
                              'celular': toUpper(celCtrl.text), // Celular logic
                              'correo_personal': toUpper(correoCtrl.text),
                              'banco': toUpper(bancoCtrl.text),
                              'cuenta': toUpper(cuentaCtrl.text),
                              'clabe': toUpper(clabeCtrl.text),
                              'area': toUpper(areaCtrl.text),
                              'puesto': toUpper(puestoCtrl.text),
                              'ubicacion': toUpper(ubicacionCtrl.text),
                              'empresa': toUpper(empresaCtrl.text),
                              'jefe_inmediato': toUpper(jefeCtrl.text),
                              'lider': toUpper(liderCtrl.text),
                              'gerente_regional': toUpper(gerenteCtrl.text),
                              'director': toUpper(directorCtrl.text),
                              'recluta': toUpper(reclutaCtrl.text),
                              'reclutador': toUpper(reclutadorCtrl.text),
                              'fuente_reclutamiento': toUpper(fuenteCtrl.text),
                              'fuente_reclutamiento_espec': toUpper(fuenteEspecCtrl.text),
                              'fecha_ingreso': fechaIngresoCtrl.text.isEmpty ? null : fechaIngresoCtrl.text,
                              'fecha_reingreso': fechaReingresoCtrl.text.isEmpty ? null : fechaReingresoCtrl.text,
                              'fecha_cambio': fechaCambioCtrl.text.isEmpty ? null : fechaCambioCtrl.text,
                              'observaciones': toUpper(obsCtrl.text),
                              'referencia_nombre': toUpper(refNombreCtrl.text),
                              'referencia_telefono': toUpper(refTelCtrl.text),
                              'referencia_relacion': toUpper(refRelacionCtrl.text),
                              'numero_empleado': numeroEmpleadoCtrl.text.trim(),
                              'status_sys': statusSys,
                              'status_rh': statusRh,
                              'foto_url': currentFotoUrl,
                              // No longer need separate usuario_id as it is the same record
                            };

                            try {
                              if (pickedFile != null) {
                                final bytes = await pickedFile!.readAsBytes();
                                final fileExt = pickedFile!.path.split('.').last;
                                final fileName = '${DateTime.now().millisecondsSinceEpoch}.$fileExt';
                                final path = 'photos/$fileName';
                                
                                await Supabase.instance.client.storage.from('employee_photos').uploadBinary(path, bytes);
                                data['foto_url'] = Supabase.instance.client.storage.from('employee_photos').getPublicUrl(path);
                              }

                              if (isEditing) {
                                await Supabase.instance.client.from('profiles').update(data).eq('id', item['id']);
                              } else {
                                await Supabase.instance.client.from('profiles').insert(data);
                              }
                              if (mounted) {
                                Navigator.pop(context);
                                _fetchItems();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(isEditing ? 'Colaborador actualizado exitosamente' : 'Colaborador creado exitosamente (Estado: CAMBIO)'),
                                    backgroundColor: const Color(0xFFB1CB34),
                                  ),
                                );
                              }
                            } catch (e) {
                               setDialogState(() => saving = false);
                               if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                            }
                          },
                          child: saving
                              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : Text(isEditing ? 'GUARDAR' : 'CREAR'),
                        ),
                      ),
                    ],
                  ),
                ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatusChip(String status, String prefix) {
    Color color;
    switch (status) {
      case 'ACTIVO': color = Colors.green; break;
      case 'BAJA': color = Colors.red; break;
      case 'CAMBIO': color = Colors.orange; break;
      case 'ELIMINAR': color = Colors.purple; break;
      case 'REINGRESO': color = Colors.blue; break;
      default: color = Colors.grey;
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
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF344092), fontSize: 13, letterSpacing: 1)),
        const Divider(),
        const SizedBox(height: 8),
      ],
    );
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

  Widget _buildMobileLayout(List<Map<String, dynamic>> filtered) {
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey[200]!)),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              leading: CircleAvatar(
                backgroundColor: const Color(0xFF344092).withOpacity(0.1),
                backgroundImage: item['foto_url'] != null ? NetworkImage(item['foto_url']) : null,
                child: item['foto_url'] == null 
                  ? Text((item['nombre'] ?? '?')[0], style: const TextStyle(color: Color(0xFF344092), fontWeight: FontWeight.bold))
                  : null,
              ),
              title: Text('${item['numero_empleado'] ?? '---'} | ${item['nombre']} ${item['paterno']}', style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Row(
                children: [
                  _buildStatusChip(item['status_rh'] ?? 'ACTIVO', 'RH'),
                  const SizedBox(width: 8),
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
                          title: Text('Eliminar', style: TextStyle(color: Colors.red)),
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

  Widget _buildDesktopLayout(List<Map<String, dynamic>> filtered, ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: SizedBox(
        width: double.infinity,
        child: Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey[200]!)),
        child: Theme(
          data: theme.copyWith(
            cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
            cardColor: Colors.transparent,
          ),
          child: PaginatedDataTable(
            header: const Text('Directorio de Colaboradores', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            actions: [
              if (widget.role == 'admin')
                ElevatedButton.icon(
                  onPressed: () => _showForm(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.secondary,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('NUEVO'),
                ),
            ],
            columns: const [
              DataColumn(label: Text('Número', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Status RH', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Nombre', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Puesto', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Ubicación', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Correo', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Acciones', style: TextStyle(fontWeight: FontWeight.bold))),
            ],
            source: _CssiDataSource(
              items: filtered,
              theme: theme,
              isAdmin: widget.role == 'admin',
              onEdit: (item) => _showForm(item: item),
              onDelete: (id) => _deleteItem(id),
              buildStatusChip: _buildStatusChip,
            ),
            rowsPerPage: filtered.isEmpty ? 1 : (filtered.length > 10 ? 10 : filtered.length),
            showCheckboxColumn: false,
            horizontalMargin: 16,
            columnSpacing: 16,
            dataRowMinHeight: 40,
            dataRowMaxHeight: 56,
            headingRowHeight: 48,
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
      floatingActionButton: widget.role == 'admin' && !isDesktopWidth
        ? FloatingActionButton.extended(
            onPressed: () => _showForm(),
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
                title: 'Colaboradores SSI',
                subtitle: null,
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
                            Icon(Icons.badge_outlined, size: 64, color: Colors.grey[300]),
                            const SizedBox(height: 16),
                            Text('No se encontraron colaboradores', style: TextStyle(color: Colors.grey[500])),
                          ],
                        ),
                      )
                    : LayoutBuilder(
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
}

class _CssiDataSource extends DataTableSource {
  final List<Map<String, dynamic>> items;
  final ThemeData theme;
  final bool isAdmin;
  final Function(Map<String, dynamic>) onEdit;
  final Function(String) onDelete;
  final Widget Function(String, String) buildStatusChip;

  _CssiDataSource({
    required this.items,
    required this.theme,
    required this.isAdmin,
    required this.onEdit,
    required this.onDelete,
    required this.buildStatusChip,
  });

  @override
  DataRow? getRow(int index) {
    if (index >= items.length) return null;
    final item = items[index];

    return DataRow.byIndex(
      index: index,
      cells: [
        DataCell(Text(item['numero_empleado']?.toString() ?? '---')),
        DataCell(buildStatusChip(item['status_rh'] ?? 'ACTIVO', 'RH')),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: const Color(0xFF344092).withOpacity(0.1),
                backgroundImage: item['foto_url'] != null ? NetworkImage(item['foto_url']) : null,
                child: item['foto_url'] == null 
                  ? Text((item['nombre'] ?? '?')[0], style: const TextStyle(color: Color(0xFF344092), fontWeight: FontWeight.bold, fontSize: 12))
                  : null,
              ),
              const SizedBox(width: 8),
              Text('${item['nombre']} ${item['paterno']} ${item['materno'] ?? ''}'.trim()),
            ],
          ),
        ),
        DataCell(Text(item['puesto'] ?? '---')),
        DataCell(Text(item['ubicacion'] ?? '---')),
        DataCell(Text(item['correo_personal'] ?? '---')),
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
