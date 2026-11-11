import '../items/item_stack.dart';
import '../stats/stat_block.dart';

/// Manages named gear/equipment slots and automatically binds item stat modifiers to a [StatBlock].
class EquipmentSlots {
  final StatBlock? stats;
  final Map<String, Set<String>> _allowedSlotTypes = {};
  final Map<String, ItemStack?> _equipped = {};

  EquipmentSlots({
    List<String> slotNames = const ['Head', 'Chest', 'Legs', 'Boots', 'MainHand', 'OffHand', 'Accessory'],
    this.stats,
  }) {
    for (final s in slotNames) {
      _equipped[s] = null;
    }
  }

  /// Configures allowed `equipSlot` identifiers or item tags accepted by [slotName].
  void setSlotRule(String slotName, Set<String> allowedTypes) {
    _equipped.putIfAbsent(slotName, () => null);
    _allowedSlotTypes[slotName] = allowedTypes;
  }

  Iterable<String> get slotNames => _equipped.keys;

  ItemStack? getEquipped(String slotName) => _equipped[slotName];

  bool canEquip(String slotName, ItemStack stack) {
    if (!_equipped.containsKey(slotName)) return false;
    final rules = _allowedSlotTypes[slotName];
    if (rules != null && rules.isNotEmpty) {
      final slotMatch = stack.definition.equipSlot != null && rules.contains(stack.definition.equipSlot);
      final tagMatch = stack.definition.tags.any(rules.contains);
      return slotMatch || tagMatch;
    }
    // If no custom rule, match exact slot name when item specifies equipSlot
    if (stack.definition.equipSlot != null) {
      return stack.definition.equipSlot == slotName;
    }
    return false;
  }

  /// Equips [stack] into [slotName], attaching its modifiers to [stats].
  /// Returns `(success, previousItem)` where `previousItem` is any item that was displaced.
  ({bool equipped, ItemStack? previousItem}) equip(String slotName, ItemStack stack) {
    if (!canEquip(slotName, stack)) {
      return (equipped: false, previousItem: null);
    }

    final previous = unequip(slotName);
    _equipped[slotName] = stack;

    if (stats != null) {
      for (final mod in stack.definition.equipModifiers) {
        stats!.addModifier(mod, overrideSource: stack);
      }
    }

    return (equipped: true, previousItem: previous);
  }

  /// Unequips whatever occupies [slotName] and removes its attached stat modifiers.
  ItemStack? unequip(String slotName) {
    final current = _equipped[slotName];
    if (current == null) return null;

    _equipped[slotName] = null;
    stats?.removeModifiersFromSource(current);
    return current;
  }
}
