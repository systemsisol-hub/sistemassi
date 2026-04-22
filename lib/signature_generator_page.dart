import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:screenshot/screenshot.dart';
import 'services/file_saver_util.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

extension StringTitleCase on String {
  String toTitleCase() {
    if (isEmpty) return '';
    
    // Smart Correction Dictionary: Words that frequently miss accents in legacy databases
    const Map<String, String> corrections = {
      'ANGEL': 'Ángel', 'JOSE': 'José', 'MARIA': 'María', 'RAMON': 'Ramón', 'JESUS': 'Jesús', 'JULIAN': 'Julián',
      'SANCHEZ': 'Sánchez', 'PEREZ': 'Pérez', 'LOPEZ': 'López', 'GARCIA': 'García', 'MARTINEZ': 'Martínez',
      'RODRIGUEZ': 'Rodríguez', 'GONZALEZ': 'González', 'JIMENEZ': 'Jiménez', 'MENDEZ': 'Méndez', 'NUÑEZ': 'Núñez',
      'HERNANDEZ': 'Hernández', 'GUTIERREZ': 'Gutiérrez', 'CORTES': 'Cortés', 'FERNANDEZ': 'Fernández', 
      'GOMEZ': 'Gómez', 'DIAZ': 'Díaz',
      'DIRECCION': 'Dirección', 'COORDINACION': 'Coordinación', 'SUBDIRECCION': 'Subdirección', 
      'TECNOLOGIAS': 'Tecnologías', 'INFORMACION': 'Información', 'ADMINISTRACION': 'Administración',
      'GESTION': 'Gestión', 'SUPERVISION': 'Supervisión', 'PRODUCCION': 'Producción', 'AREA': 'Área',
      'CAPACITACION': 'Capacitación', 'PUBLICOS': 'Públicos', 'CIENTIFICO': 'Científico', 'OPERACION': 'Operación'
    };

    return toLowerCase().split(' ').map((word) {
      if (word.isEmpty) return word;
      
      // Match against uppercase dictionary
      final upper = word.toUpperCase();
      if (corrections.containsKey(upper)) {
        return corrections[upper]!;
      }
      
      // Standard Title Case fallback
      return word[0].toUpperCase() + word.substring(1);
    }).join(' ');
  }
}

class BrandConfig {
  final String name;
  final String background;
  final String facebook;
  final String instagram;
  final String web;
  final double topMargin;

  BrandConfig({
    required this.name,
    required this.background,
    required this.facebook,
    required this.instagram,
    required this.web,
    required this.topMargin,
  });
}

class SignatureGeneratorPage extends StatefulWidget {
  const SignatureGeneratorPage({super.key});

  @override
  State<SignatureGeneratorPage> createState() => _SignatureGeneratorPageState();
}

class _SignatureGeneratorPageState extends State<SignatureGeneratorPage> {
  final ScreenshotController _screenshotController = ScreenshotController();
  
  final List<BrandConfig> _brands = [
    BrandConfig(name: 'Si Sol', background: 'assets/firmcred/sisol.png', facebook: 'sisolmx', instagram: 'sisolmx', web: 'sisol.com.mx', topMargin: 48.0),
    BrandConfig(name: 'AG 117', background: 'assets/firmcred/ag117.png', facebook: 'ag117cdmx', instagram: 'AG117.cdmx', web: 'sisol.com.mx', topMargin: 16.0),
    BrandConfig(name: 'Bonanza', background: 'assets/firmcred/bonanza.png', facebook: 'bonanzaprisma', instagram: 'bonanzaprisma', web: 'bonanzaprisma.com', topMargin: 48.0),
    BrandConfig(name: 'Olympia', background: 'assets/firmcred/olympia.png', facebook: 'olympiaresidencial', instagram: 'olympiaresidencial', web: 'olympiaresidencial.com', topMargin: 48.0),
    BrandConfig(name: 'Misiones', background: 'assets/firmcred/mse.png', facebook: 'misionestoluca', instagram: 'tolucamisiones', web: 'misionesstaesperanza.com', topMargin: 12.0),
    BrandConfig(name: 'Punta Pacífico', background: 'assets/firmcred/punta.png', facebook: 'puntapacifico.ensenada', instagram: 'puntapacifico.ensenada', web: 'puntapacifico.com.mx', topMargin: 48.0),
    BrandConfig(name: 'Selva Norte', background: 'assets/firmcred/selva.png', facebook: 'selvanortetulum', instagram: 'selvanortetulum', web: 'selvanorte.com', topMargin: 48.0),
    BrandConfig(name: 'VidaMar', background: 'assets/firmcred/vidamar.png', facebook: 'vidamarresidencial', instagram: 'vidamarresidencial', web: 'vidamarresidencial.com', topMargin: 20.0),
  ];

  late BrandConfig _selectedBrand;
  final _nameController = TextEditingController();
  final _positionController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedBrand = _brands[0];
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final data = await Supabase.instance.client
            .from('profiles')
            .select('*')
            .eq('id', user.id)
            .maybeSingle();

        if (mounted && data != null) {
          setState(() {
            final fullName = '${data['nombre'] ?? ''} ${data['paterno'] ?? ''} ${data['materno'] ?? ''}'.trim();
            _nameController.text = fullName.toTitleCase();
            
            final rawPosition = data['puesto'] ?? data['role'] ?? '';
            _positionController.text = rawPosition.toString().toTitleCase();
            
            _phoneController.text = data['celular'] ?? data['telefono'] ?? '';
            _emailController.text = user.email ?? '';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching profile: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSignature() async {
    // Remove focus to hide cursor in screenshot
    FocusScope.of(context).unfocus();
    // Wait for animation
    await Future.delayed(const Duration(milliseconds: 300));

    final image = await _screenshotController.capture(pixelRatio: 1.0);
    if (image == null) return;

    final fileName = 'firma_${DateTime.now().millisecondsSinceEpoch}.png';
    await FileSaverUtil.saveAndShare(image, fileName);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).copyWith(
      textTheme: GoogleFonts.interTextTheme(Theme.of(context).textTheme),
    );

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Theme(
      data: theme,
      child: Scaffold(
        body: LayoutBuilder(
          builder: (context, constraints) {
            double previewWidth = 787;
            double previewHeight = 220; // Corrected height from PHP
            final isDesktop = constraints.maxWidth > 800;

            if (isDesktop) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left Column: Configuration
                    Expanded(
                      flex: 4,
                      child: SingleChildScrollView(
                        child: _buildConfigurationForm(theme),
                      ),
                    ),
                    const SizedBox(width: 32),
                    // Right Column: Preview (Fixed width approx)
                    Expanded(
                      flex: 6,
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            _buildPreviewCard(theme),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              child: _buildDownloadButton(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            // Mobile Layout (Current)
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildPreviewCard(theme),
                  const SizedBox(height: 24),
                  _buildConfigurationForm(theme),
                  const SizedBox(height: 32),
                  _buildDownloadButton(),
                  const SizedBox(height: 40),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPreviewCard(ThemeData theme) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            color: Colors.grey[200],
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Screenshot(
                controller: _screenshotController,
                child: _buildSignaturePreview(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('VISTA PREVIA', 
              style: theme.textTheme.labelLarge?.copyWith(
                color: Colors.grey[700],
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              )),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigurationForm(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Brand Selector
        Text('Selecciona la Marca', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        SizedBox(
          height: 100,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _brands.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final brand = _brands[index];
              final isSelected = _selectedBrand == brand;
              return InkWell(
                onTap: () => setState(() => _selectedBrand = brand),
                child: Column(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isSelected ? theme.colorScheme.primary : Colors.grey[300]!, width: 2),
                        image: DecorationImage(
                          image: AssetImage(brand.background),
                          fit: BoxFit.cover,
                          alignment: Alignment.centerRight,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(brand.name, style: TextStyle(
                      fontSize: 10, 
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? theme.colorScheme.primary : Colors.black,
                    )),
                  ],
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 24),
        Text('Haz clic en la firma para editar tus datos directamente.', 
          style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic, color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildDownloadButton() {
    return ElevatedButton.icon(
      onPressed: _saveSignature,
      icon: const Icon(Icons.download),
      label: const Text('Descargar Firma'),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildSignaturePreview() {
    // Layout mimicking the provided image
    return SizedBox(
      width: 787,
      height: 220,
      child: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage(_selectedBrand.background),
            fit: BoxFit.fill,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 0), // pt-4 handled by spacers/vertical boxes
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24), // pt-4 equivalent
            // Name
            TextField(
              controller: _nameController,
              cursorColor: Colors.white,
              textCapitalization: TextCapitalization.words, // Allow mixed case and accents
              style: GoogleFonts.lexend(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 22,
                letterSpacing: 0.5,
                height: 1.0, // Reduced line height
              ),
              decoration: const InputDecoration(
                filled: false,
                isDense: true, // Make it more compact
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: 'Nombre Completo',
                hintStyle: TextStyle(color: Colors.white54, fontSize: 22),
              ),
              onChanged: (_) => setState(() {}),
            ),
            
            const SizedBox(height: 6), // Increased Gap
            
            // Position
            TextField(
              controller: _positionController,
              cursorColor: Colors.white,
              textCapitalization: TextCapitalization.sentences, // Allow natural typing
              style: GoogleFonts.lexend(
                color: Colors.white,
                fontWeight: FontWeight.w500,
                fontSize: 14,
                height: 1.0, // Reduced line height
              ),
              decoration: const InputDecoration(
                filled: false,
                isDense: true, // Make it more compact
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: 'Puesto',
                hintStyle: TextStyle(color: Colors.white54, fontSize: 14),
              ),
              onChanged: (_) => setState(() {}),
            ),
            
            // Push everything to bottom
            const Spacer(),
            
            // Unified Info Section (2 columns)
            _buildUnifiedInfoSection(),
            
            const SizedBox(height: 20), // Bottom Margin
          ],
        ),
      ),
    );
  }

  Widget _buildUnifiedInfoSection() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Left Column: Phone (Top) & Email (Bottom)
        Expanded(
          flex: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildEditableSignatureItem(Icons.phone_android_outlined, _phoneController, 'Teléfono'),
              const SizedBox(height: 4),
              _buildEditableSignatureItem(Icons.email_outlined, _emailController, 'Correo'),
            ],
          ),
        ),
        
        // Right Column: Web (Top) & Social (Bottom)
        Expanded(
          flex: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSignatureItem(Icons.public, _selectedBrand.web),
              const SizedBox(height: 4),
              _buildSocialItem(),
            ],
          ),
        ),
        
        const Expanded(flex: 3, child: SizedBox()),
      ],
    );
  }

  Widget _buildSignatureItem(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: const Color(0xFF0dcaf0), size: 14), // Cyan info color
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            style: GoogleFonts.lexend(
              color: Colors.white,
              fontSize: 12, // Increased size
              fontWeight: FontWeight.w300,
              height: 1.0, // Reduced line height
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildEditableSignatureItem(IconData icon, TextEditingController controller, String hint) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: const Color(0xFF0dcaf0), size: 14), // Cyan info color
        const SizedBox(width: 8),
        Flexible(
          child: TextField(
            controller: controller,
            cursorColor: Colors.white,
            style: GoogleFonts.lexend(
              color: Colors.white,
              fontSize: 12, // Increased size
              fontWeight: FontWeight.w300,
              height: 1.0, // Reduced line height
            ),
            decoration: InputDecoration(
              filled: false,
              isDense: true, // Make it more compact
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              hintText: hint,
              hintStyle: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
      ],
    );
  }

  Widget _buildSocialItem() {
    final bool sameHandle = _selectedBrand.facebook == _selectedBrand.instagram;
    const Color iconColor = Color(0xFF0dcaf0); // Cyan info color
    
    if (sameHandle) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const FaIcon(FontAwesomeIcons.facebook, color: iconColor, size: 14),
          const SizedBox(width: 6),
          const FaIcon(FontAwesomeIcons.instagram, color: iconColor, size: 14),
          const SizedBox(width: 8),
          Text(_selectedBrand.facebook, style: GoogleFonts.lexend(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w300, height: 1.0)),
        ],
      );
    } else {
      // Stack vertically if different
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const FaIcon(FontAwesomeIcons.facebook, color: iconColor, size: 14),
              const SizedBox(width: 6),
              Text(_selectedBrand.facebook, style: GoogleFonts.lexend(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w300, height: 1.0)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const FaIcon(FontAwesomeIcons.instagram, color: iconColor, size: 14),
              const SizedBox(width: 6),
              Text(_selectedBrand.instagram, style: GoogleFonts.lexend(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w300, height: 1.0)),
            ],
          ),
        ],
      );
    }
  }
}
