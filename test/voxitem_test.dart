import 'dart:math' as math;
import 'package:test/test.dart';
import 'package:voxitem/voxitem.dart';

void main() {
  group('StatBlock & StatModifier Pipeline', () {
    test('evaluates flat, percentAdd, and percentMult in standard RPG order', () {
      final stats = StatBlock({'attack': 10.0});
      final sword = Object();
      final potion = Object();

      stats.addModifier(StatModifier(statName: 'attack', value: 5.0, type: StatModifierType.flat, source: sword));
      stats.addModifier(StatModifier(statName: 'attack', value: 0.2, type: StatModifierType.percentAdd, source: sword));
      stats.addModifier(StatModifier(statName: 'attack', value: 0.3, type: StatModifierType.percentAdd, source: potion));
      stats.addModifier(StatModifier(statName: 'attack', value: 0.1, type: StatModifierType.percentMult, source: potion));

      // ((10 + 5) * (1 + 0.2 + 0.3)) * (1 + 0.1) = 15 * 1.5 * 1.1 = 24.75
      expect(stats.getValue('attack'), closeTo(24.75, 1e-4));

      // Removing potion buffs restores just sword buffs: (10 + 5) * 1.2 = 18.0
      stats.removeModifiersFromSource(potion);
      expect(stats.getValue('attack'), closeTo(18.0, 1e-4));
    });
  });

  group('GridInventory Spatial Packing, Rotation & Persistence', () {
    const rifle = ItemDefinition(id: 'rifle', name: 'Plasma Rifle', gridWidth: 3, gridHeight: 1, weight: 4.5);
    const potion = ItemDefinition(id: 'potion', name: 'Health Potion', maxStack: 5, weight: 0.5);
    const chest = ItemDefinition(id: 'plate', name: 'Chestplate', gridWidth: 2, gridHeight: 2, weight: 8.0);

    test('multi-cell placement, auto-rotation into tight spaces, and overlap rejection', () {
      // 3x3 grid
      final inv = GridInventory(width: 3, height: 3);

      // Fill top 2x2 with chestplate at (0, 0) and block bottom row at (0, 2)
      expect(inv.placeAt(ItemStack(chest), 0, 0), isTrue);
      expect(inv.placeAt(ItemStack(potion), 0, 2), isTrue);
      // Now only column x=2 (1x3 vertical strip) can hold a 3x1 rifle!
      final myRifle = ItemStack(rifle);
      expect(inv.addItem(myRifle), equals(0));
      expect(myRifle.rotated, isTrue);
      expect(inv.getAt(2, 0)?.stack, same(myRifle));
      expect(inv.getAt(2, 2)?.stack, same(myRifle));
    });

    test('auto-stacking, remainder overflow, and weight enforcement', () {
      final inv = GridInventory(width: 2, height: 2, maxWeight: 4.0);

      // 8 potions stack size 5 -> takes 1 slot of 5 and 1 slot of 3 -> 8 * 0.5 = 4.0 kg (exact fit)
      expect(inv.addItem(ItemStack(potion, quantity: 8)), equals(0));
      expect(inv.items.length, equals(2));
      expect(inv.countById('potion'), equals(8));

      // Adding 1 more exceeds weight cap (4.5 > 4.0)
      expect(inv.addItem(ItemStack(potion, quantity: 1)), equals(1));
    });

    test('JSON serialization round-trips layout cleanly', () {
      final reg = ItemRegistry()..registerAll([rifle, potion]);
      final inv = GridInventory(width: 4, height: 4);
      inv.placeAt(ItemStack(rifle), 1, 0, rotated: true);
      inv.placeAt(ItemStack(potion, quantity: 3), 0, 2);

      final saved = inv.toJson();
      final restored = GridInventory(width: 4, height: 4);
      restored.loadJson(saved, reg);

      expect(restored.getAt(1, 2)?.stack.definition.id, equals('rifle'));
      expect(restored.getAt(1, 2)?.stack.rotated, isTrue);
      expect(restored.countById('potion'), equals(3));
    });
  });

  group('EquipmentSlots', () {
    test('equipping and swapping gear dynamically updates StatBlock', () {
      final stats = StatBlock({'attack': 5.0, 'armor': 0.0});
      final gear = EquipmentSlots(stats: stats);

      final ironSword = ItemDefinition(
        id: 'iron_sword',
        name: 'Iron Sword',
        equipSlot: 'MainHand',
        equipModifiers: [StatModifier(statName: 'attack', value: 12.0)],
      );
      final dragonSword = ItemDefinition(
        id: 'dragon_sword',
        name: 'Dragon Sword',
        equipSlot: 'MainHand',
        equipModifiers: [
          StatModifier(statName: 'attack', value: 25.0),
          StatModifier(statName: 'attack', value: 0.5, type: StatModifierType.percentAdd),
        ],
      );

      final s1 = ItemStack(ironSword);
      final s2 = ItemStack(dragonSword);

      final eq1 = gear.equip('MainHand', s1);
      expect(eq1.equipped, isTrue);
      expect(eq1.previousItem, isNull);
      expect(stats.getValue('attack'), closeTo(17.0, 1e-4));

      // Swap with Dragon Sword -> previous item returned & modifiers swapped cleanly
      final eq2 = gear.equip('MainHand', s2);
      expect(eq2.equipped, isTrue);
      expect(eq2.previousItem, same(s1));
      // (5 + 25) * 1.5 = 45.0
      expect(stats.getValue('attack'), closeTo(45.0, 1e-4));

      gear.unequip('MainHand');
      expect(stats.getValue('attack'), closeTo(5.0, 1e-4));
    });
  });

  group('LootTable & CraftingSystem', () {
    const coin = ItemDefinition(id: 'coin', name: 'Gold Coin', maxStack: 999);
    const oak = ItemDefinition(id: 'oak_log', name: 'Oak Log', maxStack: 20, tags: {'wood'});
    const ingot = ItemDefinition(id: 'iron_ingot', name: 'Iron Ingot', maxStack: 20, tags: {'metal'});
    const gem = ItemDefinition(id: 'ruby', name: 'Ruby', maxStack: 10, rarity: ItemRarity.rare);
    const spear = ItemDefinition(id: 'spear', name: 'Iron Spear', gridWidth: 1, gridHeight: 3);

    test('LootTable evaluates guaranteed drops, luck weights, and deterministic RNG', () {
      const table = LootTable(
        minRolls: 3,
        maxRolls: 3,
        entries: [
          LootEntry(item: coin, minQuantity: 5, maxQuantity: 10, guaranteed: true),
          LootEntry(item: oak, weight: 80.0, minQuantity: 1, maxQuantity: 2),
          LootEntry(item: gem, weight: 2.0, luckFactor: 20.0),
        ],
      );

      final lowLuckDrops = table.roll(math.Random(123), context: const LootContext(luck: 0.0));
      expect(lowLuckDrops.any((s) => s.definition.id == 'coin' && s.quantity >= 5), isTrue);

      // With high luck, ruby appears much more often over repeated chests
      int rubyHighLuck = 0;
      int rubyLowLuck = 0;
      for (int i = 0; i < 100; i++) {
        final d1 = table.roll(math.Random(i), context: const LootContext(luck: 0.0));
        final d2 = table.roll(math.Random(i), context: const LootContext(luck: 5.0));
        if (d1.any((s) => s.definition.id == 'ruby')) rubyLowLuck++;
        if (d2.any((s) => s.definition.id == 'ruby')) rubyHighLuck++;
      }
      expect(rubyHighLuck, greaterThan(rubyLowLuck));
    });

    test('CraftingSystem validates stations, tag-based ingredients, and atomic crafting', () {
      const recipe = CraftingRecipe(
        id: 'craft_spear',
        station: 'forge',
        ingredients: [
          RecipeIngredient.tag('wood', 2),
          RecipeIngredient.item('iron_ingot', 1),
        ],
        output: spear,
      );

      final crafting = CraftingSystem([recipe]);
      final inv = GridInventory(width: 4, height: 4);
      inv.addItem(ItemStack(oak, quantity: 3));
      inv.addItem(ItemStack(ingot, quantity: 1));

      // Cannot craft without forge station
      expect(crafting.canCraft(recipe, inv, activeStation: 'hand'), isFalse);
      // Can craft at forge
      expect(crafting.canCraft(recipe, inv, activeStation: 'forge'), isTrue);

      expect(crafting.craft(recipe, inv, activeStation: 'forge'), isTrue);
      expect(inv.countById('oak_log'), equals(1)); // 3 - 2 = 1 left
      expect(inv.countById('iron_ingot'), equals(0));
      expect(inv.countById('spear'), equals(1));
    });
  });
}
