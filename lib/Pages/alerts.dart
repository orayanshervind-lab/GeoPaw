import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';
import '../services/pet_provider.dart';
import '../widgets/select_pet.dart';

enum AlertType { geofence, anomaly }

class PetAlert {
  final String id;
  final AlertType type;
  final String title;
  final String description;
  final DateTime timestamp;
  final bool acknowledged;

  PetAlert({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.timestamp,
    required this.acknowledged,
  });

  factory PetAlert.fromMap(String id, Map<dynamic, dynamic> map) {
    return PetAlert(
      id: id,
      type: map['type'] == 'anomaly' ? AlertType.anomaly : AlertType.geofence,
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(
          (map['timestamp'] as num?)?.toInt() ?? 0),
      acknowledged: map['acknowledged'] == true,
    );
  }
}

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<PetAlert> _allAlerts = [];
  bool _isLoading = true;

 String get _petId =>
    context.read<PetProvider>().selectedPet?.id ?? 'demo';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAlerts();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _loadAlerts() {
    final ref = FirebaseDatabase.instance.ref('alerts/$_petId');
    ref.orderByChild('timestamp').onValue.listen((event) {
      final data = event.snapshot.value;
      final List<PetAlert> loaded = [];
      if (data != null && data is Map) {
        data.forEach((key, value) {
          if (value is Map) {
            loaded.add(PetAlert.fromMap(key.toString(), value));
          }
        });
        // Sort newest first
        loaded.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      }
      if (mounted) {
        setState(() {
          _allAlerts = loaded;
          _isLoading = false;
        });
      }
    });

    // Stop spinner after 3s if no data
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  Future<void> _acknowledge(PetAlert alert) async {
    await FirebaseDatabase.instance
        .ref('alerts/$_petId/${alert.id}/acknowledged')
        .set(true);
  }

  Future<void> _deleteAlert(PetAlert alert) async {
    await FirebaseDatabase.instance
        .ref('alerts/$_petId/${alert.id}')
        .remove();
  }

  Future<void> _clearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all alerts?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await FirebaseDatabase.instance.ref('alerts/$_petId').remove();
    }
  }

  // Add a dummy alert for testing purposes
  Future<void> _addDemoAlert(AlertType type) async {
    final ref = FirebaseDatabase.instance.ref('alerts/$_petId');
    await ref.push().set({
      'type': type == AlertType.geofence ? 'geofence' : 'anomaly',
      'title': type == AlertType.geofence
          ? 'Geofence breach!'
          : 'Unusual behaviour detected',
      'description': type == AlertType.geofence
          ? 'Your pet has left the safe zone.'
          : 'Your pet\'s activity pattern is outside its normal baseline.',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'acknowledged': false,
    });
  }

  List<PetAlert> _filtered(AlertType? type) {
    if (type == null) return _allAlerts;
    return _allAlerts.where((a) => a.type == type).toList();
  }

  @override
  Widget build(BuildContext context) {
    final unread = _allAlerts.where((a) => !a.acknowledged).length;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Alerts'),
            if (unread > 0) ...[
              const SizedBox(width: 8),
              Badge(label: Text('$unread')),
            ],
          ],
        ),
        actions: [
          if (context.watch<PetProvider>().pets.length > 1)
             _PetSwitcherButton(
                 onChanged: _loadAlerts,
              ),

          if (_allAlerts.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Clear all',
              onPressed: _clearAll,
            ),
          // Demo button to test alerts without real GPS hardware
          PopupMenuButton(
            icon: const Icon(Icons.add_alert_outlined),
            tooltip: 'Add test alert',
            itemBuilder: (_) => [
              const PopupMenuItem(
                  value: 'geofence',
                  child: ListTile(
                      leading: Icon(Icons.fence, color: Colors.orange),
                      title: Text('Test geofence alert'))),
              const PopupMenuItem(
                  value: 'anomaly',
                  child: ListTile(
                      leading: Icon(Icons.psychology, color: Colors.purple),
                      title: Text('Test anomaly alert'))),
            ],
            onSelected: (val) {
              if (val == 'geofence') _addDemoAlert(AlertType.geofence);
              if (val == 'anomaly') _addDemoAlert(AlertType.anomaly);
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Geofence'),
            Tab(text: 'Behaviour'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _AlertList(alerts: _filtered(null),
                    onAck: _acknowledge, onDelete: _deleteAlert),
                _AlertList(alerts: _filtered(AlertType.geofence),
                    onAck: _acknowledge, onDelete: _deleteAlert),
                _AlertList(alerts: _filtered(AlertType.anomaly),
                    onAck: _acknowledge, onDelete: _deleteAlert),
              ],
            ),
    );
  }
}

class _PetSwitcherButton extends StatelessWidget {
  final VoidCallback onChanged;
  const _PetSwitcherButton({required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PetProvider>();
    final selected = provider.selectedPet;

    return PopupMenuButton<String>(
      icon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            selected == null
                ? '🐾'
                : selected.species == 'Dog'
                    ? '🐶'
                    : selected.species == 'Cat'
                        ? '🐱'
                        : '🐾',
            style: const TextStyle(fontSize: 18),
          ),
          const Icon(Icons.arrow_drop_down, size: 18),
        ],
      ),
      onSelected: (petId) {
        final pet = provider.pets.firstWhere((p) => p.id == petId);
        provider.selectPet(pet);
        onChanged();
      },
      itemBuilder: (_) => provider.pets
          .map(
            (pet) => PopupMenuItem(
              value: pet.id,
              child: Row(
                children: [
                  Text(
                    pet.species == 'Dog'
                        ? '🐶'
                        : pet.species == 'Cat'
                            ? '🐱'
                            : '🐾',
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(width: 8),
                  Text(pet.name),
                  if (provider.selectedPet?.id == pet.id) ...[
                    const Spacer(),
                    Icon(Icons.check,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary),
                  ],
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}


class _AlertList extends StatelessWidget {
  final List<PetAlert> alerts;
  final Future<void> Function(PetAlert) onAck;
  final Future<void> Function(PetAlert) onDelete;

  const _AlertList({
    required this.alerts,
    required this.onAck,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (alerts.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_none, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No alerts yet', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: alerts.length,
      itemBuilder: (context, index) {
        final alert = alerts[index];
        final isGeofence = alert.type == AlertType.geofence;

        return Dismissible(
          key: Key(alert.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          onDismissed: (_) => onDelete(alert),
          child: Card(
            margin: const EdgeInsets.only(bottom: 10),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            color: alert.acknowledged
                ? null
                : (isGeofence
                    ? Colors.orange.withOpacity(0.08)
                    : Colors.purple.withOpacity(0.08)),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              leading: CircleAvatar(
                backgroundColor: isGeofence
                    ? Colors.orange.withOpacity(0.15)
                    : Colors.purple.withOpacity(0.15),
                child: Icon(
                  isGeofence ? Icons.fence : Icons.psychology,
                  color: isGeofence ? Colors.orange : Colors.purple,
                ),
              ),
              title: Text(
                alert.title,
                style: TextStyle(
                  fontWeight: alert.acknowledged
                      ? FontWeight.normal
                      : FontWeight.bold,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text(alert.description),
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(alert.timestamp),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              trailing: alert.acknowledged
                  ? const Icon(Icons.check_circle,
                      color: Colors.green, size: 20)
                  : IconButton(
                      icon: const Icon(Icons.check_circle_outline),
                      tooltip: 'Mark as read',
                      onPressed: () => onAck(alert),
                    ),
            ),
          ),
        );
      },
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}