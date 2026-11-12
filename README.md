<p align="center">
  <img src="assets/logo.svg" width="88" alt="voxitem logo"/>
</p>

# voxitem

Pure Dart RPG & survival inventory toolkit: spatial 2D grid containers, item stacking/rotation, equipment slots, weighted loot drops, tag-aware crafting recipes, and hierarchical stat modifier pipelines.

## Features

- **RPG Stat Pipeline (`StatBlock`, `StatValue`, `StatModifier`):** Ordered flat additive, percentage additive (`percentAdd`), and compound multiplicative (`percentMult`) buffs with source-tagged cleanup and clamping.
- **2D Spatial Grid Inventory (`GridInventory`):** Multi-cell items (`2x3`, `1x4`) with 90-degree rotation, auto-stacking, stack splitting, weight limits, and JSON serialization.
- **Equipment Slots (`EquipmentSlots`):** Slot validation by tag/slot constraint with automatic `StatModifier` attachment/detachment on equip/unequip.
- **Weighted Loot Tables (`LootTable`):** Contextual conditional drops, guaranteed items, luck scaling, and multi-roll deterministic generation.
- **Crafting System (`CraftingSystem`, `CraftingRecipe`):** Atomic ingredient validation supporting both exact item IDs and interchangeable tags (e.g., any `'wood'`).
