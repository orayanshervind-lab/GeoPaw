import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geopaw_app/services/pet_provider.dart';
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