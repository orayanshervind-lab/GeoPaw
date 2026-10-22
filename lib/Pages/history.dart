import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';
import '../services/pet_provider.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final MapController _mapController = MapController();
  List<LatLng> _path = [];
  List<Map<String, dynamic>> _logEntries = [];
  bool _isLoading = true;
  DateTime _selectedDate = DateTime.now();
  bool _showList = false;
  String? _resolvedDeviceId;

  String get _petId =>
      context.read<PetProvider>().selectedPet?.id ??
      FirebaseAuth.instance.currentUser?.uid ??
      'demo';

  @override
  void initState() {
    super.initState();
    _resolveDeviceAndLoad(_selectedDate);
  }

  String _dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  // Resolve petId → deviceId from devices/ node
  Future<String> _resolveDeviceId(String petId) async {
    if (_resolvedDeviceId != null) return _resolvedDeviceId!;

    final snapshot = await FirebaseDatabase.instance.ref('devices').get();
    if (snapshot.exists && snapshot.value is Map) {
      final devices = Map<String, dynamic>.from(snapshot.value as Map);
      for (final entry in devices.entries) {
        final value = entry.value;
        final linkedPetId = value is Map
            ? value['petId']?.toString()
            : value?.toString();
        if (linkedPetId == petId) {
          _resolvedDeviceId = entry.key;
          return _resolvedDeviceId!;
        }
      }
    }
    // Fallback to petId if no device found
    return petId;
  }

  void _resolveDeviceAndLoad(DateTime date) async {
    setState(() {
      _isLoading = true;
      _path = [];
      _logEntries = [];
    });

    final deviceId = await _resolveDeviceId(_petId);
    _loadHistory(date, deviceId);
  }

  void _loadHistory(DateTime date, String deviceId) {
    final ref = FirebaseDatabase.instance
        .ref('gps_logs/$deviceId/${_dateKey(date)}');

    ref.orderByKey().once().then((event) {
      final data = event.snapshot.value;
      final List<LatLng> path = [];
      final List<Map<String, dynamic>> entries = [];

      if (data != null && data is Map) {
        // Sort by key (timestamp string) to ensure correct order
        final sorted = Map.fromEntries(
          data.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
        );

        sorted.forEach((key, value) {
          if (value is Map) {
            // Support both lat/lng (hardware) and latitude/longitude (simulator)
            final lat = (value['lat'] as num?)?.toDouble()
                     ?? (value['latitude'] as num?)?.toDouble();
            final lng = (value['lng'] as num?)?.toDouble()
                     ?? (value['longitude'] as num?)?.toDouble();
            final ts = (value['updatedAt'] as num?)?.toInt()
                    ?? (value['timestamp'] as num?)?.toInt()
                    ?? 0;

            if (lat != null && lng != null) {
              path.add(LatLng(lat, lng));
              entries.add({
                'lat': lat,
                'lng': lng,
                'timestamp': ts,
                'speed': (value['speed'] as num?)?.toDouble() ?? 0.0,
              });
            }
          }
        });
      }

      if (mounted) {
        setState(() {
          _path = path;
          _logEntries = entries;
          _isLoading = false;
        });

        if (_path.isNotEmpty) {
          Future.delayed(const Duration(milliseconds: 300), () {
            if (_path.length == 1) {
              _mapController.move(_path.first, 16);
            } else {
              final bounds = LatLngBounds.fromPoints(_path);
              _mapController.fitCamera(
                CameraFit.bounds(
                  bounds: bounds,
                  padding: const EdgeInsets.all(40),
                ),
              );
            }
          });
        }
      }
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _resolvedDeviceId = null; // re-resolve on pet change
      });
      _resolveDeviceAndLoad(picked);
    }
  }

  String _formatTime(int ms) {
    if (ms == 0) return '--:--';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  double get _totalDistanceKm {
    if (_path.length < 2) return 0;
    const dist = Distance();
    double total = 0;
    for (int i = 0; i < _path.length - 1; i++) {
      total += dist(_path[i], _path[i + 1]);
    }
    return total / 1000;
  }

  double get _avgSpeed {
    if (_logEntries.isEmpty) return 0;
    final speeds = _logEntries
        .map((e) => (e['speed'] as double))
        .where((s) => s > 0);
    if (speeds.isEmpty) return 0;
    return speeds.reduce((a, b) => a + b) / speeds.length;
  }

  @override
  Widget build(BuildContext context) {
    final selectedPet = context.watch<PetProvider>().selectedPet;
    final pets = context.watch<PetProvider>().pets;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          selectedPet != null
              ? '${selectedPet.name}\'s History'
              : 'Location History',
        ),
        actions: [
          if (pets.length > 1)
            _PetSwitcherButton(
              onChanged: () {
                _resolvedDeviceId = null;
                _resolveDeviceAndLoad(_selectedDate);
              },
            ),
          IconButton(
            icon: Icon(_showList ? Icons.map_outlined : Icons.list),
            tooltip: _showList ? 'Map view' : 'List view',
            onPressed: () => setState(() => _showList = !_showList),
          ),
          TextButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today, size: 16),
            label: Text(
              '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _StatChip(
                        icon: Icons.route,
                        label: '${_totalDistanceKm.toStringAsFixed(2)} km',
                        tooltip: 'Total distance',
                      ),
                      _StatChip(
                        icon: Icons.location_on,
                        label: '${_path.length} points',
                        tooltip: 'GPS points recorded',
                      ),
                      _StatChip(
                        icon: Icons.speed,
                        label: '${_avgSpeed.toStringAsFixed(1)} m/s avg',
                        tooltip: 'Average speed',
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _path.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.location_off,
                                  size: 48, color: Colors.grey),
                              SizedBox(height: 12),
                              Text('No GPS data for this date',
                                  style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        )
                      : _showList
                          ? _buildList()
                          : _buildMap(),
                ),
              ],
            ),
    );
  }

  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _path.isNotEmpty ? _path.first : const LatLng(6.9271, 79.8612),
        initialZoom: 15,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.geopaw_app',
        ),
        if (_path.length > 1)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _path,
                color: Theme.of(context).colorScheme.primary,
                strokeWidth: 4,
              ),
            ],
          ),
        if (_path.isNotEmpty)
          MarkerLayer(
            markers: [
              Marker(
                point: _path.first,
                width: 36,
                height: 36,
                child: const _PathMarker(
                    color: Colors.green, icon: Icons.play_arrow),
              ),
              Marker(
                point: _path.last,
                width: 36,
                height: 36,
                child: const _PathMarker(
                    color: Colors.red, icon: Icons.stop),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildList() {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _logEntries.length,
      itemBuilder: (context, index) {
        final entry = _logEntries[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor:
                  Theme.of(context).colorScheme.primaryContainer,
              child: Text('${index + 1}',
                  style: const TextStyle(fontSize: 12)),
            ),
            title: Text(
              'Lat: ${(entry['lat'] as double).toStringAsFixed(5)}  '
              'Lng: ${(entry['lng'] as double).toStringAsFixed(5)}',
              style: const TextStyle(fontSize: 13),
            ),
            subtitle: Text(
              '${_formatTime(entry['timestamp'] as int)}  ·  '
              'Speed: ${(entry['speed'] as double).toStringAsFixed(1)} m/s',
            ),
            trailing: const Icon(Icons.location_on,
                color: Color(0xFFE08A34), size: 18),
          ),
        );
      },
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

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String tooltip;
  const _StatChip(
      {required this.icon, required this.label, required this.tooltip});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 16, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}

class _PathMarker extends StatelessWidget {
  final Color color;
  final IconData icon;
  const _PathMarker({required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(
              color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))
        ],
      ),
      child: Icon(icon, color: Colors.white, size: 20),
    );
  }
}