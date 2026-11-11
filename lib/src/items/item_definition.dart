import '../stats/stat_block.dart';

/// Item tier classification for UI tinting and loot rarity filtering.
enum ItemRarity {
  common,
  uncommon,
  rare,
  epic,
  legendary,
  unique,
}

/// Static blueprint describing an item's dimensions, stacking rules, tags, and equip stats.
class ItemDefinition {
  final String id;
  final String name;
  final String description;
  final int gridWidth;
  final int gridHeight;
  final int maxStack;
  final double weight;
  final ItemRarity rarity;
  final Set<String> tags;
  final String? equipSlot;
  final List<StatModifier> equipModifiers;
  final Map<String, dynamic> metadata;

  const ItemDefinition({
    required this.id,
    required this.name,
    this.description = '',
    this.gridWidth = 1,
    this.gridHeight = 1,
    this.maxStack = 1,
    this.weight = 1.0,
    this.rarity = ItemRarity.common,
    this.tags = const {},
    this.equipSlot,
    this.equipModifiers = const [],
    this.metadata = const {},
  });

  bool hasTag(String tag) => tags.contains(tag);
}

/// Central catalog mapping item IDs to [ItemDefinition] instances.
class ItemRegistry {
  final Map<String, ItemDefinition> _items = {};

  void register(ItemDefinition def) => _items[def.id] = def;

  void registerAll(Iterable<ItemDefinition> defs) {
    for (final d in defs) {
      _items[d.id] = d;
    }
  }

  ItemDefinition? get(String id) => _items[id];

  Iterable<ItemDefinition> get all => _items.values;
}
