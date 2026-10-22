class Pet {
  final String id;
  final String name;
  final String species;
  final String breed;
  final String gender;
  final double weightKg;

  Pet({
    required this.id,
    required this.name,
    required this.species,
    required this.breed,
    required this.gender,
    required this.weightKg,
  });

  // Convert Firebase snapshot to Pet object
  factory Pet.fromMap(String id, Map<dynamic, dynamic> map) {
    return Pet(
      id: id,
      name: map['name'] ?? '',
      species: map['species'] ?? '',
      breed: map['breed'] ?? '',
      gender: map['gender'] ?? '',
      weightKg: (map['weightKg'] as num?)?.toDouble() ?? 0.0,
    );
  }

  // Convert Pet object to Map for Firebase
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'species': species,
      'breed': breed,
      'gender': gender,
      'weightKg': weightKg,
    };
  }
}