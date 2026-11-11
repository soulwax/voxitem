import 'dart:math' as math;
import '../items/item_definition.dart';
import '../items/item_stack.dart';

/// Contextual parameters passed into loot evaluation (luck, area tier, flags).
class LootContext {
  final double luck;
  final int level;
  final Set<String> tags;

  const LootContext({
    this.luck = 0.0,
    this.level = 1,
    this.tags = const {},
  });
}

/// Weighted or guaranteed entry within a [LootTable].
class LootEntry {
  final ItemDefinition? item;
  final LootTable? nestedTable;
  final double weight;
  final int minQuantity;
  final int maxQuantity;
  final bool guaranteed;
  final double luckFactor;
  final bool Function(LootContext context)? condition;

  const LootEntry({
    this.item,
    this.nestedTable,
    this.weight = 10.0,
    this.minQuantity = 1,
    this.maxQuantity = 1,
    this.guaranteed = false,
    this.luckFactor = 0.0,
    this.condition,
  });

  /// Creates an entry representing an empty/no-drop weight slice.
  const LootEntry.nothing({this.weight = 10.0, this.condition})
      : item = null,
        nestedTable = null,
        minQuantity = 0,
        maxQuantity = 0,
        guaranteed = false,
        luckFactor = 0.0;

  double effectiveWeight(LootContext context) {
    if (condition != null && !condition!(context)) return 0.0;
    return math.max(0.0, weight + luckFactor * context.luck);
  }
}

/// Weighted probabilistic drop generator supporting nested tables, luck, and guaranteed items.
class LootTable {
  final int minRolls;
  final int maxRolls;
  final List<LootEntry> entries;

  const LootTable({
    this.minRolls = 1,
    this.maxRolls = 1,
    required this.entries,
  });

  /// Generates random loot drops deterministically using [rng].
  List<ItemStack> roll(
    math.Random rng, {
    LootContext context = const LootContext(),
    bool mergeStacks = true,
  }) {
    final dropped = <ItemStack>[];

    // 1. Guaranteed drops
    for (final e in entries) {
      if (e.guaranteed && (e.condition == null || e.condition!(context))) {
        _resolveEntry(e, rng, context, dropped);
      }
    }

    // 2. Weighted random rolls
    final pool = <LootEntry>[];
    double totalWeight = 0.0;
    for (final e in entries) {
      if (e.guaranteed) continue;
      final w = e.effectiveWeight(context);
      if (w > 0.0) {
        pool.add(e);
        totalWeight += w;
      }
    }

    if (pool.isNotEmpty && totalWeight > 0.0) {
      final rollCount = minRolls + (maxRolls > minRolls ? rng.nextInt(maxRolls - minRolls + 1) : 0);
      for (int r = 0; r < rollCount; r++) {
        var cursor = rng.nextDouble() * totalWeight;
        for (final entry in pool) {
          final w = entry.effectiveWeight(context);
          if (cursor <= w) {
            _resolveEntry(entry, rng, context, dropped);
            break;
          }
          cursor -= w;
        }
      }
    }

    if (!mergeStacks || dropped.length <= 1) return dropped;

    // Coalesce identical stackable drops
    final merged = <ItemStack>[];
    for (final stack in dropped) {
      var qty = stack.quantity;
      if (stack.definition.maxStack > 1) {
        for (final existing in merged) {
          if (existing.definition.id == stack.definition.id && !existing.isFull) {
            final move = math.min(qty, existing.remainingCapacity);
            existing.quantity += move;
            qty -= move;
            if (qty <= 0) break;
          }
        }
      }
      if (qty > 0) {
        merged.add(ItemStack(stack.definition, quantity: qty));
      }
    }
    return merged;
  }

  void _resolveEntry(
    LootEntry entry,
    math.Random rng,
    LootContext context,
    List<ItemStack> out,
  ) {
    if (entry.nestedTable != null) {
      out.addAll(entry.nestedTable!.roll(rng, context: context, mergeStacks: false));
      return;
    }
    final def = entry.item;
    if (def == null) return;

    final span = math.max(0, entry.maxQuantity - entry.minQuantity);
    final qty = entry.minQuantity + (span > 0 ? rng.nextInt(span + 1) : 0);
    if (qty > 0) {
      out.add(ItemStack(def, quantity: qty));
    }
  }
}
