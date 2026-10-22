import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';
import '../services/pet_provider.dart';

class GeofenceZone {
  final String id;
  final String name;
  final LatLng center;
  final double radius;
  final bool active;
  final String color;
  final String type; // 'safe' or 'danger'

  GeofenceZone({
    required this.id,
    required this.name,
    required this.center,
    required this.radius,
    required this.active,
    required this.color,
    this.type = 'safe',
  });

  factory GeofenceZone.fromMap(String id, Map<dynamic, dynamic> map) {
    return GeofenceZone(
      id: id,
      name: map['name'] ?? 'Zone',
      center: LatLng(
        (map['latitude'] as num).toDouble(),
        (map['longitude'] as num).toDouble(),
      ),
      radius: (map['radiusM'] as num?)?.toDouble() ??
          (map['radius'] as num?)?.toDouble() ?? 200,
      active: map['active'] == true,
      color: map['color'] ?? 'teal',
      type: map['type'] ?? 'safe',
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'latitude': center.latitude,
        'longitude': center.longitude,
        'radiusM': radius,
        'active': active,
        'color': color,
        'type': type,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      };

  bool get isDanger => type == 'danger';
}

class GeofenceScreen extends StatefulWidget {
  const GeofenceScreen({super.key});

  @override
  State<GeofenceScreen> createState() => _GeofenceScreenState();
}

class _GeofenceScreenState extends State<GeofenceScreen> {
  final MapController _mapController = MapController();

  List<GeofenceZone> _zones = [];
  bool _isLoading = true;
  bool _isAddingMode = false;
  LatLng? _pendingCenter;
  double _pendingRadius = 200;
  String _pendingName = '';
  String _pendingColor = 'teal';
  String _pendingType = 'safe'; // 'safe' or 'danger'

  String get _petId =>
      context.read<PetProvider>().selectedPet?.id ??
      FirebaseAuth.instance.currentUser?.uid ??
      'demo';

  final Map<String, Color> _colorMap = {
    'teal': Colors.teal,
    'orange': Colors.orange,
    'purple': Colors.purple,
    'red': Colors.red,
    'blue': Colors.blue,
    'green': Colors.green,
  };

  @override
  void initState() {
    super.initState();
    _loadZones();
  }

  void _loadZones() {
    final ref = FirebaseDatabase.instance.ref('geofences/$_petId');
    ref.onValue.listen((event) {
      final data = event.snapshot.value;
      final List<GeofenceZone> loaded = [];
      if (data != null && data is Map) {
        data.forEach((key, value) {
          if (value is Map) {
            loaded.add(GeofenceZone.fromMap(key.toString(), value));
          }
        });
      }
      if (mounted) {
        setState(() {
          _zones = loaded;
          _isLoading = false;
        });
      }
    });

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  void _onMapTap(LatLng point) {
    if (!_isAddingMode) return;
    setState(() => _pendingCenter = point);
  }

  void _enterAddMode() {
    setState(() {
      _isAddingMode = true;
      _pendingCenter = null;
      _pendingName = '';
      _pendingRadius = 200;
      _pendingColor = 'teal';
      _pendingType = 'safe';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Tap anywhere on the map to place a geofence'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _cancelAddMode() {
    setState(() {
      _isAddingMode = false;
      _pendingCenter = null;
    });
  }

  Future<void> _saveZone() async {
    if (_pendingCenter == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tap the map to place the zone first')),
      );
      return;
    }

    final name = _pendingName.trim().isEmpty
        ? (_pendingType == 'danger'
            ? 'Danger Zone ${_zones.length + 1}'
            : 'Zone ${_zones.length + 1}')
        : _pendingName.trim();

  
    final color = _pendingType == 'danger' ? 'red' : _pendingColor;

    final zone = GeofenceZone(
      id: '',
      name: name,
      center: _pendingCenter!,
      radius: _pendingRadius,
      active: true,
      color: color,
      type: _pendingType,
    );

    await FirebaseDatabase.instance
        .ref('geofences/$_petId')
        .push()
        .set(zone.toMap());

    setState(() {
      _isAddingMode = false;
      _pendingCenter = null;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"$name" saved'),
          backgroundColor:
              _pendingType == 'danger' ? Colors.red : Colors.green,
        ),
      );
    }
  }

  Future<void> _toggleZone(GeofenceZone zone) async {
    await FirebaseDatabase.instance
        .ref('geofences/$_petId/${zone.id}/active')
        .set(!zone.active);
  }

  Future<void> _deleteZone(GeofenceZone zone) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${zone.name}"?'),
        content: const Text('This geofence zone will be removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await FirebaseDatabase.instance
          .ref('geofences/$_petId/${zone.id}')
          .remove();
    }
  }

  Color _zoneColor(GeofenceZone zone) {
    if (zone.isDanger) return Colors.red;
    return _colorMap[zone.color] ?? Colors.teal;
  }

  void _showZoneDetails(GeofenceZone zone) {
    final color = _zoneColor(zone);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Text(zone.name,
                    style: Theme.of(ctx)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                // Zone type badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: zone.isDanger
                        ? Colors.red.withOpacity(0.15)
                        : Colors.green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: zone.isDanger ? Colors.red : Colors.green),
                  ),
                  child: Text(
                    zone.isDanger ? '⚠️ Danger' : '✅ Safe',
                    style: TextStyle(
                      fontSize: 11,
                      color: zone.isDanger ? Colors.red : Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                Switch(
                  value: zone.active,
                  onChanged: (_) {
                    _toggleZone(zone);
                    Navigator.pop(ctx);
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
                'Center: ${zone.center.latitude.toStringAsFixed(5)}, '
                '${zone.center.longitude.toStringAsFixed(5)}'),
            Text('Radius: ${zone.radius.toInt()} m'),
            Text('Status: ${zone.active ? "Active" : "Inactive"}'),
            Text(
              zone.isDanger
                  ? 'Alert: fires when pet enters this zone'
                  : 'Alert: fires when pet leaves this zone',
              style: TextStyle(
                  color: zone.isDanger ? Colors.red : Colors.green,
                  fontSize: 12),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _deleteZone(zone);
                    },
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    label: const Text('Delete',
                        style: TextStyle(color: Colors.red)),
                    style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      _mapController.move(zone.center, 15);
                      Navigator.pop(ctx);
                    },
                    icon: const Icon(Icons.center_focus_strong),
                    label: const Text('View on map'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedPet = context.watch<PetProvider>().selectedPet;

    // Pending zone color — danger zones always red
    final pendingColor = _pendingType == 'danger'
        ? Colors.red
        : (_colorMap[_pendingColor] ?? Colors.teal);

    return Scaffold(
      appBar: AppBar(
        title: Text(selectedPet != null
            ? '${selectedPet.name}\'s Geofences'
            : 'Geofences'),
        actions: [
          if (_isAddingMode)
            TextButton(
              onPressed: _cancelAddMode,
              child: const Text('Cancel'),
            )
          else
            IconButton(
              icon: const Icon(Icons.list),
              tooltip: 'Zone list',
              onPressed: _showZoneList,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: const LatLng(6.9271, 79.8612),
                    initialZoom: 14,
                    onTap: (_, point) => _onMapTap(point),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.geopaw_app',
                    ),

                    // Saved zones
                    CircleLayer(
                      circles: _zones.map((zone) {
                        final color = _zoneColor(zone);
                        return CircleMarker(
                          point: zone.center,
                          radius: zone.radius,
                          useRadiusInMeter: true,
                          color: zone.active
                              ? color.withOpacity(0.15)
                              : Colors.grey.withOpacity(0.1),
                          borderColor: zone.active ? color : Colors.grey,
                          borderStrokeWidth: zone.isDanger ? 3 : 2,
                        );
                      }).toList(),
                    ),

                    // Zone center pin
                    MarkerLayer(
                      markers: _zones.map((zone) {
                        final color = _zoneColor(zone);
                        return Marker(
                          point: zone.center,
                          width: 36,
                          height: 36,
                          child: GestureDetector(
                            onTap: () => _showZoneDetails(zone),
                            child: Container(
                              decoration: BoxDecoration(
                                color: zone.active ? color : Colors.grey,
                                shape: BoxShape.circle,
                                boxShadow: const [
                                  BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 4,
                                      offset: Offset(0, 2))
                                ],
                              ),
                              child: Icon(
                                zone.isDanger
                                    ? Icons.warning_rounded
                                    : Icons.fence,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),

                    // Pending zone preview
                    if (_pendingCenter != null) ...[
                      CircleLayer(
                        circles: [
                          CircleMarker(
                            point: _pendingCenter!,
                            radius: _pendingRadius,
                            useRadiusInMeter: true,
                            color: pendingColor.withOpacity(0.2),
                            borderColor: pendingColor,
                            borderStrokeWidth: 2,
                          ),
                        ],
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _pendingCenter!,
                            width: 36,
                            height: 36,
                            child: Container(
                              decoration: BoxDecoration(
                                color: pendingColor,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.add_location,
                                  color: Colors.white, size: 20),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),

                // Add mode panel
                if (_isAddingMode)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 20,
                    child: Card(
                      elevation: 6,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _pendingCenter == null
                                  ? '📍 Tap map to place zone'
                                  : '✅ Zone placed — configure below',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 12),

                            // Zone type chooser
                            Row(
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => setState(
                                        () => _pendingType = 'safe'),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 10),
                                      decoration: BoxDecoration(
                                        color: _pendingType == 'safe'
                                            ? Colors.green
                                            : Colors.grey.shade200,
                                        borderRadius: const BorderRadius.only(
                                          topLeft: Radius.circular(8),
                                          bottomLeft: Radius.circular(8),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.shield,
                                              size: 16,
                                              color: _pendingType == 'safe'
                                                  ? Colors.white
                                                  : Colors.grey),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Safe Zone',
                                            style: TextStyle(
                                              color: _pendingType == 'safe'
                                                  ? Colors.white
                                                  : Colors.grey,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => setState(
                                        () => _pendingType = 'danger'),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 10),
                                      decoration: BoxDecoration(
                                        color: _pendingType == 'danger'
                                            ? Colors.red
                                            : Colors.grey.shade200,
                                        borderRadius: const BorderRadius.only(
                                          topRight: Radius.circular(8),
                                          bottomRight: Radius.circular(8),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.warning_rounded,
                                              size: 16,
                                              color: _pendingType == 'danger'
                                                  ? Colors.white
                                                  : Colors.grey),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Danger Zone',
                                            style: TextStyle(
                                              color: _pendingType == 'danger'
                                                  ? Colors.white
                                                  : Colors.grey,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _pendingType == 'danger'
                                  ? '⚠️ Alert fires when pet enters this zone'
                                  : '✅ Alert fires when pet leaves this zone',
                              style: TextStyle(
                                fontSize: 11,
                                color: _pendingType == 'danger'
                                    ? Colors.red
                                    : Colors.green,
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Zone name input
                            TextField(
                              decoration: const InputDecoration(
                                labelText: 'Zone name',
                                hintText: 'e.g. Home, Park, Road',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              onChanged: (v) => _pendingName = v,
                            ),
                            const SizedBox(height: 12),

                            // Radius selection slider
                            Row(
                              children: [
                                Icon(Icons.radio_button_checked,
                                    size: 16, color: pendingColor),
                                const SizedBox(width: 6),
                                Text('Radius: ${_pendingRadius.toInt()} m'),
                              ],
                            ),
                            Slider(
                              value: _pendingRadius,
                              min: 50,
                              max: 2000,
                              divisions: 39,
                              label: '${_pendingRadius.toInt()} m',
                              activeColor: pendingColor,
                              onChanged: (v) =>
                                  setState(() => _pendingRadius = v),
                            ),

                            // Color picker
                            if (_pendingType == 'safe') ...[
                              const Text('Colour:'),
                              const SizedBox(height: 8),
                              Row(
                                children: _colorMap.entries.map((entry) {
                                  final selected =
                                      _pendingColor == entry.key;
                                  return GestureDetector(
                                    onTap: () => setState(
                                        () => _pendingColor = entry.key),
                                    child: Container(
                                      width: 28,
                                      height: 28,
                                      margin:
                                          const EdgeInsets.only(right: 8),
                                      decoration: BoxDecoration(
                                        color: entry.value,
                                        shape: BoxShape.circle,
                                        border: selected
                                            ? Border.all(
                                                color: Colors.black,
                                                width: 2.5)
                                            : null,
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 14),
                            ] else
                              const SizedBox(height: 8),

                            // Save button
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: _pendingType == 'danger'
                                      ? Colors.red
                                      : null,
                                ),
                                onPressed: _saveZone,
                                icon: const Icon(Icons.save),
                                label: const Text('Save zone'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Zone count chip
                if (!_isAddingMode)
                  Positioned(
                    top: 12,
                    left: 16,
                    child: Row(
                      children: [
                        Chip(
                          avatar: const Icon(Icons.shield, size: 16,
                              color: Colors.green),
                          label: Text(
                              '${_zones.where((z) => !z.isDanger).length} safe'),
                          backgroundColor:
                              Colors.green.withOpacity(0.1),
                        ),
                        const SizedBox(width: 8),
                        Chip(
                          avatar: const Icon(Icons.warning_rounded,
                              size: 16, color: Colors.red),
                          label: Text(
                              '${_zones.where((z) => z.isDanger).length} danger'),
                          backgroundColor: Colors.red.withOpacity(0.1),
                        ),
                      ],
                    ),
                  ),
              ],
            ),

      floatingActionButton: !_isAddingMode
          ? FloatingActionButton.extended(
              onPressed: _enterAddMode,
              icon: const Icon(Icons.add_location_alt),
              label: const Text('Add zone'),
            )
          : null,
    );
  }

  void _showZoneList() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        builder: (_, controller) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Geofence zones',
                  style: Theme.of(ctx)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              if (_zones.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('No zones added yet',
                        style: TextStyle(color: Colors.grey)),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    controller: controller,
                    itemCount: _zones.length,
                    itemBuilder: (_, i) {
                      final zone = _zones[i];
                      final color = _zoneColor(zone);
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: color.withOpacity(0.2),
                          child: Icon(
                            zone.isDanger
                                ? Icons.warning_rounded
                                : Icons.fence,
                            color: color,
                            size: 20,
                          ),
                        ),
                        title: Row(
                          children: [
                            Text(zone.name),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: zone.isDanger
                                    ? Colors.red.withOpacity(0.1)
                                    : Colors.green.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                zone.isDanger ? 'Danger' : 'Safe',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: zone.isDanger
                                        ? Colors.red
                                        : Colors.green),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Text('${zone.radius.toInt()} m · '
                            '${zone.active ? "Active" : "Inactive"}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              value: zone.active,
                              onChanged: (_) => _toggleZone(zone),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.red, size: 20),
                              onPressed: () {
                                Navigator.pop(ctx);
                                _deleteZone(zone);
                              },
                            ),
                          ],
                        ),
                        onTap: () {
                          _mapController.move(zone.center, 15);
                          Navigator.pop(ctx);
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
//