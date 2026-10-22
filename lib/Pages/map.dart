import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../services/pet_provider.dart';
import '../models/pet.dart';

// Mirrors the zone shape saved by the geofence screen: geofences/$petId
// holds a MAP of zone IDs, each with its own lat/lng/radius/active/color/type —
// not a single flat geofence object.
class _Zone {
  final String id;
  final LatLng center;
  final double radius;
  final bool active;
  final String color;
  final String type; // 'safe' or 'danger'

  _Zone({
    required this.id,
    required this.center,
    required this.radius,
    required this.active,
    required this.color,
    required this.type,
  });

  bool get isDanger => type == 'danger';

  factory _Zone.fromMap(String id, Map<dynamic, dynamic> map) {
    return _Zone(
      id: id,
      center: LatLng(
        (map['latitude'] as num).toDouble(),
        (map['longitude'] as num).toDouble(),
      ),
      radius: (map['radiusM'] as num?)?.toDouble() ??
          (map['radius'] as num?)?.toDouble() ??
          200,
      active: map['active'] == true,
      color: map['color']?.toString() ?? 'teal',
      type: map['type']?.toString() ?? 'safe',
    );
  }
}

const Map<String, Color> _zoneColorMap = {
  'teal': Colors.teal,
  'orange': Colors.orange,
  'purple': Colors.purple,
  'red': Colors.red,
  'blue': Colors.blue,
  'green': Colors.green,
};

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();

  Map<String, LatLng> _petPositions = {};
  LatLng get _defaultPosition =>
      _petPositions.values.firstOrNull ?? const LatLng(6.9271, 79.8612);

  // Per-pet list of geofence zones, keyed by petId, so each pet keeps its
  // own zones and nothing gets lost when switching pets or tracking many.
  final Map<String, List<_Zone>> _geofencesByPet = {};
  final Map<String, StreamSubscription> _geofenceSubs = {};
  bool _showGeofences = true;

  Map<String, StreamSubscription> _subscriptions = {};
  Map<String, String> _petDeviceIds = {};

  bool _isLoading = true;
  bool _trackingAll = false;
  String? _trackingPetId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pet = context.read<PetProvider>().selectedPet;
      if (pet != null) {
        _trackAll(false);
        _startTrackingOne(pet);
      }
    });
  }

  void _trackAll(bool val) => _trackingAll = val;

 // ── Device resolver ──────────────────────────────────────
Future<String> _resolveDeviceId(String petId) async {
  // Return cached result immediately
  if (_petDeviceIds.containsKey(petId)) return _petDeviceIds[petId]!;

  final snapshot = await FirebaseDatabase.instance.ref('devices').get();

  if (snapshot.exists && snapshot.value is Map) {
    final devices = Map<String, dynamic>.from(snapshot.value as Map);
    devices.forEach((deviceId, value) {
      // Handle both {petId: "..."} and direct string value
      final linkedPetId = value is Map
          ? value['petId']?.toString()
          : value?.toString();
      if (linkedPetId != null) {
        _petDeviceIds[linkedPetId] = deviceId;
      }
    });
  }

  return _petDeviceIds[petId] ?? petId;
}

  // ── Tracking ──────────────────────────────────────────────
  void _startTrackingOne(Pet pet) async {
    if (_trackingPetId == pet.id && !_trackingAll) return;
    _cancelAll();
    _trackingPetId = pet.id;
    _trackingAll = false;
    setState(() => _isLoading = true);
    await _subscribe(pet);
    _loadGeofence(pet.id);
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  void _startTrackingAll() async {
    _cancelAll();
    _trackingAll = true;
    _trackingPetId = null;
    setState(() => _isLoading = true);
    final pets = context.read<PetProvider>().pets;
    for (final p in pets) {
      await _subscribe(p);
      _loadGeofence(p.id); // was missing — this is why geofences never showed in "All pets" mode
    }
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  Future<void> _subscribe(Pet pet) async {
    final deviceId = await _resolveDeviceId(pet.id);
    final ref = FirebaseDatabase.instance.ref('gps_logs/$deviceId/latest');
    ref.keepSynced(true);

    _subscriptions[pet.id] = ref.onValue.listen((event) {
      final data = event.snapshot.value;
      if (data != null && data is Map) {
        // Support both lat/lng (hardware) and latitude/longitude (simulator)
        final lat = (data['lat'] as num?)?.toDouble()
                 ?? (data['latitude'] as num?)?.toDouble();
        final lng = (data['lng'] as num?)?.toDouble()
                 ?? (data['longitude'] as num?)?.toDouble();

        if (lat != null && lng != null && mounted) {
          setState(() => _petPositions[pet.id] = LatLng(lat, lng));
          // Auto-centre on first real fix
           if (!_petPositions.containsKey(pet.id)) {
           _mapController.move(LatLng(lat, lng), 16);
          }
        }

        // Handle SOS
        if (data['sos'] == true) {
          _handleSOS(pet);
        }
      }
      if (mounted) setState(() => _isLoading = false);
    }, onError: (_) {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  void _handleSOS(Pet pet) async {
    await FirebaseDatabase.instance
        .ref('alerts/${pet.id}')
        .push()
        .set({
      'type': 'geofence',
      'title': '🆘 SOS — ${pet.name}',
      'description':
          'SOS button pressed. Location: '
          '${_petPositions[pet.id]?.latitude.toStringAsFixed(5)}, '
          '${_petPositions[pet.id]?.longitude.toStringAsFixed(5)}',
      'acknowledged': false,
      'timestamp': ServerValue.timestamp,
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🆘 SOS from ${pet.name}!'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  void _cancelAll() {
    for (final sub in _subscriptions.values) sub.cancel();
    _subscriptions.clear();
    for (final sub in _geofenceSubs.values) sub.cancel();
    _geofenceSubs.clear();
  }

  // Listens for this pet's geofence zones. geofences/$petId is a MAP of zone
  // IDs (one entry per zone the pet has, e.g. a safe zone and a danger zone),
  // each holding its own lat/lng/radius/active/color/type — matching exactly
  // what the geofence screen writes. Uses onValue (not once) so edits made in
  // the geofence screen show up here live.
  void _loadGeofence(String petId) {
    _geofenceSubs[petId]?.cancel();
    final ref = FirebaseDatabase.instance.ref('geofences/$petId');
    _geofenceSubs[petId] = ref.onValue.listen((event) {
      final data = event.snapshot.value;
      final zones = <_Zone>[];
      if (data != null && data is Map) {
        data.forEach((key, value) {
          if (value is Map) {
            try {
              zones.add(_Zone.fromMap(key.toString(), value));
            } catch (_) {
              // Skip a malformed zone entry rather than crash the map.
            }
          }
        });
      }
      if (mounted) {
        setState(() => _geofencesByPet[petId] = zones);
      }
    });
  }

  void _centreOnPets() {
    if (_petPositions.isEmpty) return;
    if (_petPositions.length == 1) {
      _mapController.move(_petPositions.values.first, 16);
    } else {
      final bounds = LatLngBounds.fromPoints(_petPositions.values.toList());
      _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(60)),
      );
    }
  }

  void _showPetSwitcher() {
    final provider = context.read<PetProvider>();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Select pet to track',
                style: Theme.of(ctx)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ListTile(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              tileColor: _trackingAll
                  ? Theme.of(ctx).colorScheme.primaryContainer
                  : null,
              leading:
                  const CircleAvatar(child: Text('🐾', style: TextStyle(fontSize: 20))),
              title: const Text('All pets'),
              subtitle: Text('${provider.pets.length} pets'),
              trailing: _trackingAll
                  ? Icon(Icons.check_circle,
                      color: Theme.of(ctx).colorScheme.primary)
                  : null,
              onTap: () {
                provider.selectPet(null);
                _startTrackingAll();
                Navigator.pop(ctx);
              },
            ),
            const Divider(),
            ...provider.pets.map((pet) {
              final isSelected =
                  !_trackingAll && provider.selectedPet?.id == pet.id;
              return ListTile(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                tileColor: isSelected
                    ? Theme.of(ctx).colorScheme.primaryContainer
                    : null,
                leading: CircleAvatar(
                  backgroundColor:
                      Theme.of(ctx).colorScheme.primaryContainer,
                  child: Text(_emojiFor(pet),
                      style: const TextStyle(fontSize: 20)),
                ),
                title: Text(pet.name,
                    style: TextStyle(
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal)),
                subtitle: Text('${pet.species} · ${pet.breed}'),
                trailing: isSelected
                    ? Icon(Icons.check_circle,
                        color: Theme.of(ctx).colorScheme.primary)
                    : null,
                onTap: () {
                  provider.selectPet(pet);
                  _startTrackingOne(pet);
                  Navigator.pop(ctx);
                },
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _emojiFor(Pet pet) {
    if (pet.species == 'Dog') return '🐶';
    if (pet.species == 'Cat') return '🐱';
    return '🐾';
  }

  List<Marker> _buildMarkers(List<Pet> pets, Pet? selectedPet) {
    if (_trackingAll) {
      return pets.map((pet) {
        final pos = _petPositions[pet.id] ?? _defaultPosition;
        return Marker(
          point: pos,
          width: 52,
          height: 52,
          child: Tooltip(
            message: pet.name,
            child: _PetMarker(emoji: _emojiFor(pet)),
          ),
        );
      }).toList();
    } else if (selectedPet != null) {
      final pos = _petPositions[selectedPet.id] ?? _defaultPosition;
      return [
        Marker(
          point: pos,
          width: 52,
          height: 52,
          child: _PetMarker(emoji: _emojiFor(selectedPet)),
        ),
      ];
    }
    return [];
  }

  // Renders one circle per active zone, for every pet currently being
  // tracked (all pets, or just the single selected pet). Danger zones are
  // always red; safe zones use their saved colour.
  List<CircleMarker> _buildGeofenceCircles(List<Pet> pets) {
    if (!_showGeofences) return [];
    final circles = <CircleMarker>[];
    final petsToShow = _trackingAll
        ? pets
        : (_trackingPetId != null
            ? pets.where((p) => p.id == _trackingPetId)
            : const Iterable<Pet>.empty());

    for (final pet in petsToShow) {
      final zones = _geofencesByPet[pet.id] ?? const <_Zone>[];
      for (final zone in zones) {
        if (!zone.active) continue;
        final color =
            zone.isDanger ? Colors.red : (_zoneColorMap[zone.color] ?? Colors.teal);
        circles.add(
          CircleMarker(
            point: zone.center,
            radius: zone.radius,
            useRadiusInMeter: true,
            color: color.withOpacity(0.15),
            borderColor: color,
            borderStrokeWidth: zone.isDanger ? 3 : 2,
          ),
        );
      }
    }
    return circles;
  }

  @override
  void dispose() {
    _cancelAll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PetProvider>();
    final selectedPet = provider.selectedPet;
    final pets = provider.pets;

    if (pets.isNotEmpty &&
        _subscriptions.isEmpty &&
        !_trackingAll &&
        _trackingPetId == null) {
      Future.microtask(() => _startTrackingOne(pets.first));
    }

    final geofenceCircles = _buildGeofenceCircles(pets);

    return Scaffold(
      appBar: AppBar(
        title: _trackingAll
            ? const Text('All pets')
            : selectedPet == null
                ? const Text('Live Location')
                : Row(children: [
                    Text(_emojiFor(selectedPet),
                        style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 8),
                    Text(selectedPet.name),
                  ]),
        actions: [
          if (pets.length > 1)
            IconButton(
              icon: const Icon(Icons.swap_horiz),
              tooltip: 'Switch pet',
              onPressed: _showPetSwitcher,
            ),
          IconButton(
            icon: Icon(Icons.fence,
                color: _showGeofences
                    ? Theme.of(context).colorScheme.primary
                    : null),
            tooltip: _showGeofences ? 'Hide geofences' : 'Show geofences',
            onPressed: () => setState(() => _showGeofences = !_showGeofences),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _defaultPosition,
              initialZoom: 15,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.geopaw_app',
              ),
              if (geofenceCircles.isNotEmpty)
                CircleLayer(circles: geofenceCircles),
              MarkerLayer(markers: _buildMarkers(pets, selectedPet)),
            ],
          ),

          if (_isLoading)
            const Center(child: CircularProgressIndicator()),

          if (pets.isEmpty && !_isLoading)
            Center(
              child: Card(
                margin: const EdgeInsets.all(32),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: const Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.pets, size: 48, color: Colors.grey),
                      SizedBox(height: 12),
                      Text('No pets added yet',
                          style:
                              TextStyle(fontWeight: FontWeight.bold)),
                      SizedBox(height: 6),
                      Text('Go to the Pet tab to add your pet first.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
              ),
            ),

          // Status card
          Positioned(
            left: 16,
            right: 16,
            bottom: 20,
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 14),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: _petPositions.isNotEmpty
                            ? Colors.green
                            : Colors.grey,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _trackingAll
                                ? 'Tracking ${pets.length} pets'
                                : selectedPet != null
                                    ? _petPositions.containsKey(selectedPet.id)
                                        ? '${selectedPet.name} — live'
                                        : '${selectedPet.name} — waiting for GPS...'
                                    : 'Waiting for GPS...',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Lat: ${_defaultPosition.latitude.toStringAsFixed(5)}  '
                            'Lng: ${_defaultPosition.longitude.toStringAsFixed(5)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.my_location),
                      tooltip: 'Centre on pet',
                      onPressed: _centreOnPets,
                    ),
                  ],
                ),
              ),
            ),
          ),

        ],
      ),
    );
  }
}

class _PetMarker extends StatelessWidget {
  final String emoji;
  const _PetMarker({required this.emoji});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(
              color: Colors.black26, blurRadius: 6, offset: Offset(0, 3))
        ],
      ),
      child: Center(
        child: Text(emoji, style: const TextStyle(fontSize: 22)),
      ),
    );
  }
}