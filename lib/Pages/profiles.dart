import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/pet.dart';
import '../Pages/login.dart';

class PetProfileScreen extends StatefulWidget {
  const PetProfileScreen({super.key});

  @override
  State<PetProfileScreen> createState() => _PetProfileScreenState();
}

class _PetProfileScreenState extends State<PetProfileScreen> {
  List<Pet> _pets = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPets();
  }

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? 'demo';

  void _loadPets() {
    final ref = FirebaseDatabase.instance.ref('pets/$_uid');
    ref.onValue.listen((event) {
      final data = event.snapshot.value;
      final List<Pet> loaded = [];
      if (data != null && data is Map) {
        data.forEach((key, value) {
          if (value is Map) {
            loaded.add(Pet.fromMap(key.toString(), value));
          }
        });
      }
      if (mounted) setState(() { _pets = loaded; _isLoading = false; });
    });
  }

  void _showAddEditDialog({Pet? pet}) {
    final nameController = TextEditingController(text: pet?.name ?? '');
    final breedController = TextEditingController(text: pet?.breed ?? '');
    final weightController = TextEditingController(
        text: pet != null ? pet.weightKg.toString() : '');
    String species = pet?.species ?? 'Dog';
    String gender = pet?.gender ?? 'Male';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(pet == null ? 'Add pet' : 'Edit pet'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Pet name',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.pets),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: species,
                  decoration: const InputDecoration(
                    labelText: 'Species',
                    border: OutlineInputBorder(),
                  ),
                  items: ['Dog', 'Cat', 'Other'].map((s) =>
                    DropdownMenuItem(value: s, child: Text(s))).toList(),
                  onChanged: (v) => setDialogState(() => species = v!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: breedController,
                  decoration: const InputDecoration(
                    labelText: 'Breed',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: gender,
                  decoration: const InputDecoration(
                    labelText: 'Gender',
                    border: OutlineInputBorder(),
                  ),
                  items: ['Male', 'Female'].map((g) =>
                    DropdownMenuItem(value: g, child: Text(g))).toList(),
                  onChanged: (v) => setDialogState(() => gender = v!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: weightController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Weight (kg)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;

                final newPet = Pet(
                  id: pet?.id ?? '',
                  name: name,
                  species: species,
                  breed: breedController.text.trim(),
                  gender: gender,
                  weightKg: double.tryParse(weightController.text) ?? 0.0,
                );

                final ref = FirebaseDatabase.instance.ref('pets/$_uid');
                if (pet == null) {
                  // New pet — push generates a unique ID
                  await ref.push().set(newPet.toMap());
                } else {
                  // Edit existing pet
                  await ref.child(pet.id).set(newPet.toMap());
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _deletePet(Pet pet) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove pet?'),
        content: Text('Remove ${pet.name} from your account?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await FirebaseDatabase.instance
          .ref('pets/$_uid/${pet.id}')
          .remove();
    }
  }

  void _signOut() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Pets'),
        actions: [
  TextButton.icon(
    onPressed: _signOut,
    icon: const Icon(Icons.logout),
    label: const Text('Sign out'),
    style: TextButton.styleFrom(
      foregroundColor: Theme.of(context).colorScheme.error,
    ),
  ),
  const SizedBox(width: 8),
],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _pets.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.pets, size: 72, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text('No pets added yet',
                          style: TextStyle(fontSize: 16, color: Colors.grey)),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: () => _showAddEditDialog(),
                        icon: const Icon(Icons.add),
                        label: const Text('Add your pet'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _pets.length,
                  itemBuilder: (context, index) {
                    final pet = _pets[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 30,
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer,
                              child: Text(
                                pet.species == 'Dog'
                                    ? '🐶'
                                    : pet.species == 'Cat'
                                        ? '🐱'
                                        : '🐾',
                                style: const TextStyle(fontSize: 28),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(pet.name,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                              fontWeight:
                                                  FontWeight.bold)),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${pet.species} · ${pet.breed.isNotEmpty ? pet.breed : "Unknown breed"}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                  Text(
                                    '${pet.gender} · ${pet.weightKg} kg',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuButton(
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                    value: 'edit',
                                    child: ListTile(
                                        leading: Icon(Icons.edit),
                                        title: Text('Edit'))),
                                const PopupMenuItem(
                                    value: 'delete',
                                    child: ListTile(
                                        leading: Icon(Icons.delete,
                                            color: Colors.red),
                                        title: Text('Remove',
                                            style: TextStyle(
                                                color: Colors.red)))),
                              ],
                              onSelected: (val) {
                                if (val == 'edit') {
                                  _showAddEditDialog(pet: pet);
                                } else if (val == 'delete') {
                                  _deletePet(pet);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: _pets.isNotEmpty
          ? FloatingActionButton(
              onPressed: () => _showAddEditDialog(),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}