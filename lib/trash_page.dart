import 'package:flutter/material.dart';
import 'services/trash_service.dart';
import 'theme/si_theme.dart';

class TrashPage extends StatefulWidget {
  const TrashPage({super.key});

  @override
  State<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage> {
  List<Map<String, dynamic>> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final items = await TrashService.fetchAll();
      if (mounted) setState(() { _items = items; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _restore(String trashId, String label) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restaurar elemento'),
        content: Text('¿Restaurar "$label"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Restaurar')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await TrashService.restore(trashId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('"$label" restaurado')));
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al restaurar: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deletePermanently(String trashId, String label) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar permanentemente'),
        content: Text('¿Eliminar "$label"? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await TrashService.deletePermanently(trashId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('"$label" eliminado permanentemente')));
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _emptyTrash() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vaciar papelera'),
        content: const Text('¿Eliminar todos los elementos permanentemente? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Vaciar todo'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await TrashService.emptyTrash();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Papelera vaciada')));
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _typeLabel(String originTable) {
    switch (originTable) {
      case 'profiles': return 'Perfil';
      case 'issi_inventory': return 'Inventario';
      case 'external_contacts': return 'Contacto';
      default: return originTable;
    }
  }

  IconData _typeIcon(String originTable) {
    switch (originTable) {
      case 'profiles': return Icons.person_outline;
      case 'issi_inventory': return Icons.inventory_2_outlined;
      case 'external_contacts': return Icons.contact_phone_outlined;
      default: return Icons.delete_outline;
    }
  }

  String _timeAgo(String iso) {
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inDays >= 1) return 'hace ${diff.inDays} día${diff.inDays != 1 ? 's' : ''}';
    if (diff.inHours >= 1) return 'hace ${diff.inHours} hora${diff.inHours != 1 ? 's' : ''}';
    return 'hace ${diff.inMinutes} min';
  }

  int _daysLeft(String isoExpires) {
    final dt = DateTime.tryParse(isoExpires)?.toLocal();
    if (dt == null) return 0;
    return dt.difference(DateTime.now()).inDays;
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Row(
            children: [
              Icon(Icons.delete_outline, color: c.ink3, size: 20),
              const SizedBox(width: 8),
              Text('Papelera', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.ink)),
              const Spacer(),
              if (_items.isNotEmpty)
                TextButton.icon(
                  onPressed: _emptyTrash,
                  icon: Icon(Icons.delete_forever_outlined, size: 18, color: c.danger),
                  label: Text('Vaciar', style: TextStyle(color: c.danger, fontSize: 13)),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 12),
          child: Text(
            'Los elementos se eliminan automáticamente a los 30 días',
            style: TextStyle(fontSize: 12, color: c.ink4),
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.delete_outline, size: 56, color: c.ink4),
                          const SizedBox(height: 12),
                          Text('La papelera está vacía', style: TextStyle(color: c.ink4, fontSize: 15)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (ctx, i) {
                          final item = _items[i];
                          final id = item['id'] as String;
                          final label = (item['label'] as String?) ?? 'Sin nombre';
                          final originTable = item['origin_table'] as String;
                          final deletedAt = item['deleted_at'] as String? ?? '';
                          final expiresAt = item['expires_at'] as String? ?? '';
                          final daysLeft = _daysLeft(expiresAt);
                          return Container(
                            decoration: BoxDecoration(
                              color: c.panel,
                              borderRadius: SiRadius.rMd,
                              border: Border.all(color: c.line),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(color: c.bg, borderRadius: SiRadius.rSm),
                                  child: Icon(_typeIcon(originTable), color: c.ink3, size: 20),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(label,
                                          style: TextStyle(fontWeight: FontWeight.w600, color: c.ink, fontSize: 14)),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: c.brandTint,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              _typeLabel(originTable),
                                              style: TextStyle(fontSize: 10, color: c.brand, fontWeight: FontWeight.w700),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text('Eliminado ${_timeAgo(deletedAt)}',
                                              style: TextStyle(fontSize: 11, color: c.ink4)),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        daysLeft > 0
                                            ? 'Se elimina en $daysLeft día${daysLeft != 1 ? 's' : ''}'
                                            : 'Se elimina próximamente',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: daysLeft <= 3 ? c.danger : c.ink4,
                                          fontWeight: daysLeft <= 3 ? FontWeight.w600 : FontWeight.w400,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Tooltip(
                                      message: 'Restaurar',
                                      child: IconButton(
                                        onPressed: () => _restore(id, label),
                                        icon: Icon(Icons.restore, color: c.brand),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ),
                                    Tooltip(
                                      message: 'Eliminar permanentemente',
                                      child: IconButton(
                                        onPressed: () => _deletePermanently(id, label),
                                        icon: Icon(Icons.delete_forever_outlined, color: c.danger),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }
}
