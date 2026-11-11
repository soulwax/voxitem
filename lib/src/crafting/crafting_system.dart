import '../inventory/grid_inventory.dart';
import '../items/item_definition.dart';
import '../items/item_stack.dart';

/// Required input material matching either an exact item ID or an interchangeable category tag.
class RecipeIngredient {
  final String? itemId;
  final String? tag;
  final int count;

  const RecipeIngredient.item(String this.itemId, [this.count = 1]) : tag = null;
  const RecipeIngredient.tag(String this.tag, [this.count = 1]) : itemId = null;

  bool matches(ItemDefinition def) {
    if (itemId != null) return def.id == itemId;
    if (tag != null) return def.hasTag(tag!);
    return false;
  }
}

/// Recipe transforming [ingredients] into an [output] item stack at an optional crafting station.
class CraftingRecipe {
  final String id;
  final String? station;
  final List<RecipeIngredient> ingredients;
  final ItemDefinition output;
  final int outputQuantity;
  final double craftDuration;

  const CraftingRecipe({
    required this.id,
    this.station,
    required this.ingredients,
    required this.output,
    this.outputQuantity = 1,
    this.craftDuration = 0.0,
  });
}

/// Evaluates and executes crafting recipes against a [GridInventory].
class CraftingSystem {
  final List<CraftingRecipe> recipes;

  CraftingSystem([List<CraftingRecipe>? initialRecipes])
      : recipes = initialRecipes != null ? List.of(initialRecipes) : [];

  /// Checks whether [recipe] can be crafted right now (station match + non-overlapping ingredient availability).
  bool canCraft(
    CraftingRecipe recipe,
    GridInventory inventory, {
    String? activeStation,
  }) {
    if (recipe.station != null && recipe.station != activeStation) {
      return false;
    }

    // Track remaining counts per stack index so two ingredients don't double-count one item
    final available = <int, int>{};
    for (int i = 0; i < inventory.items.length; i++) {
      available[i] = inventory.items[i].stack.quantity;
    }

    for (final req in recipe.ingredients) {
      int needed = req.count;
      for (int i = 0; i < inventory.items.length && needed > 0; i++) {
        final stack = inventory.items[i].stack;
        if (!req.matches(stack.definition)) continue;
        final avail = available[i]!;
        if (avail > 0) {
          final take = needed < avail ? needed : avail;
          available[i] = avail - take;
          needed -= take;
        }
      }
      if (needed > 0) return false;
    }

    return true;
  }

  /// Returns all registered recipes currently craftable inside [inventory].
  List<CraftingRecipe> getCraftableRecipes(
    GridInventory inventory, {
    String? activeStation,
  }) {
    return recipes
        .where((r) => canCraft(r, inventory, activeStation: activeStation))
        .toList();
  }

  /// Atomically consumes required ingredients and places the crafted output into [inventory].
  /// Returns true if crafting succeeded and output fit into inventory.
  bool craft(
    CraftingRecipe recipe,
    GridInventory inventory, {
    String? activeStation,
  }) {
    if (!canCraft(recipe, inventory, activeStation: activeStation)) return false;

    // Consume ingredients first; keep rollback log in case output doesn't fit in spatial grid
    final consumedStacks = <({ItemDefinition def, int qty, int x, int y, bool rot})>[];

    for (final req in recipe.ingredients) {
      int needed = req.count;
      for (int i = inventory.items.length - 1; i >= 0 && needed > 0; i--) {
        final entry = inventory.items[i];
        if (!req.matches(entry.stack.definition)) continue;
        final take = needed < entry.stack.quantity ? needed : entry.stack.quantity;
        consumedStacks.add((
          def: entry.stack.definition,
          qty: take,
          x: entry.x,
          y: entry.y,
          rot: entry.stack.rotated,
        ));
        entry.stack.quantity -= take;
        needed -= take;
        if (entry.stack.quantity <= 0) {
          inventory.removeItem(entry.stack);
        }
      }
    }

    final result = ItemStack(recipe.output, quantity: recipe.outputQuantity);
    final remainder = inventory.addItem(result);

    if (remainder > 0) {
      // Output didn't fit cleanly -> restore exact items back into inventory (atomic transaction)
      for (final restore in consumedStacks) {
        inventory.addItem(
          ItemStack(restore.def, quantity: restore.qty, rotated: restore.rot),
        );
      }
      return false;
    }

    return true;
  }
}
