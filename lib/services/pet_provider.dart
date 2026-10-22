import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/pet.dart';

class PetProvider extends ChangeNotifier {
  List<Pet> _pets = [];
  Pet? _selectedPet;
  bool _isLoading = true;

  List<Pet> get pets => _pets;
  Pet? get selectedPet => _selectedPet;
  bool get isLoading => _isLoading;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? 'demo';

  void loadPets() {
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
      _pets = loaded;
      // Auto-select first pet if none selected
      if (_selectedPet == null && loaded.isNotEmpty) {
        _selectedPet = loaded.first;
      }
      // Keep selected pet in sync if it was updated
      if (_selectedPet != null) {
        final updated = loaded.where((p) => p.id == _selectedPet!.id);
        if (updated.isNotEmpty) _selectedPet = updated.first;
      }
      _isLoading = false;
      notifyListeners();
    });
  }

  void selectPet(Pet? pet) {
    _selectedPet = pet;
    notifyListeners();
  }

  void clear() {
    _pets = [];
    _selectedPet = null;
    _isLoading = true;
    notifyListeners();
  }
}