import 'dart:math' as math;
import '../items/item_definition.dart';
import '../items/item_stack.dart';

/// Positioned item entry inside a [GridInventory].
class PlacedItem {
  final ItemStack stack;
  int x;
  int y;

  PlacedItem(this.stack, this.x, this.y);

  int get width => stack.effectiveWidth;
  int get height => stack.effectiveHeight;

  bool occupies(int cx, int cy) =>
      cx >= x && cx < x + width && cy >= y && cy < y + height;
}

/// 2D spatial grid container supporting multi-cell items, rotation, weight caps, and auto-stacking.
class GridInventory {
  final int width;
  final int height;
  final double? maxWeight;

  final List<PlacedItem> _items = [];

  GridInventory({
    this.width = 10,
    this.height = 6,
    this.maxWeight,
  });

  List<PlacedItem> get items => List.unmodifiable(_items);

  double get totalWeight {
    double sum = 0.0;
    for (final entry in _items) {
      sum += entry.stack.totalWeight;
    }
    return sum;
  }

  /// Checks whether [weightDelta] fits inside [maxWeight], if configured.
  bool fitsWeight(double weightDelta) {
    if (maxWeight == null) return true;
    return totalWeight + weightDelta <= maxWeight! + 1e-6;
  }

  /// Returns the item covering grid cell ([x], [y]), or null if empty.
  PlacedItem? getAt(int x, int y) {
    if (x < 0 || x >= width || y < 0 || y >= height) return null;
    for (final entry in _items) {
      if (entry.occupies(x, y)) return entry;
    }
    return null;
  }

  /// Checks whether [stack] can be placed at ([x], [y]) with orientation [rotated].
  bool canPlaceAt(
    ItemStack stack,
    int x,
    int y, {
    bool? rotated,
    ItemStack? ignoreItem,
  }) {
    final rot = rotated ?? stack.rotated;
    final w = rot ? stack.definition.gridHeight : stack.definition.gridWidth;
    final h = rot ? stack.definition.gridWidth : stack.definition.gridHeight;

    if (x < 0 || y < 0 || x + w > width || y + h > height) return false;

    for (final entry in _items) {
      if (identical(entry.stack, ignoreItem)) continue;
      final overlapsX = x < entry.x + entry.width && x + w > entry.x;
      final overlapsY = y < entry.y + entry.height && y + h > entry.y;
      if (overlapsX && overlapsY) return false;
    }
    return true;
  }

  /// Scans left-to-right, top-to-bottom for a free grid coordinate for [stack].
  ({int x, int y, bool rotated})? findFreeSlot(
    ItemStack stack, {
    bool allowRotate = true,
  }) {
    // Try original orientation first
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        if (canPlaceAt(stack, x, y, rotated: stack.rotated)) {
          return (x: x, y: y, rotated: stack.rotated);
        }
      }
    }
    // Try rotated orientation if rectangular
    if (allowRotate && stack.definition.gridWidth != stack.definition.gridHeight) {
      final altRot = !stack.rotated;
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          if (canPlaceAt(stack, x, y, rotated: altRot)) {
            return (x: x, y: y, rotated: altRot);
          }
        }
      }
    }
    return null;
  }

  /// Explicitly places [stack] at grid cell ([x], [y]).
  bool placeAt(ItemStack stack, int x, int y, {bool? rotated}) {
    if (!fitsWeight(stack.totalWeight)) return false;
    final rot = rotated ?? stack.rotated;
    if (!canPlaceAt(stack, x, y, rotated: rot)) return false;
    stack.rotated = rot;
    _items.add(PlacedItem(stack, x, y));
    return true;
  }

  /// Moves or rotates an existing item within the grid.
  bool moveItem(ItemStack stack, int toX, int toY, {bool? rotated}) {
    final entry = _findEntry(stack);
    if (entry == null) return false;
    final rot = rotated ?? stack.rotated;
    if (!canPlaceAt(stack, toX, toY, rotated: rot, ignoreItem: stack)) return false;
    stack.rotated = rot;
    entry.x = toX;
    entry.y = toY;
    return true;
  }

  /// Rotates an item 90 degrees in place if space permits.
  bool rotateItem(ItemStack stack) {
    final entry = _findEntry(stack);
    if (entry == null) return false;
    return moveItem(stack, entry.x, entry.y, rotated: !stack.rotated);
  }

  /// Adds as much of [stack] as possible (stacking first, then placing into free cells).
  /// Returns the unplaced remainder quantity (0 if completely added).
  int addItem(
    ItemStack stack, {
    bool allowAutoStack = true,
    bool allowAutoRotate = true,
  }) {
    if (stack.quantity <= 0) return 0;

    // 1. Top up existing partial stacks
    if (allowAutoStack && stack.definition.maxStack > 1) {
      for (final entry in _items) {
        if (entry.stack.canStackWith(stack) && stack.quantity > 0) {
          final room = entry.stack.remainingCapacity;
          final weightRoom = maxWeight == null
              ? room
              : ((maxWeight! - totalWeight) / math.max(1e-6, stack.definition.weight))
                  .floor();
          final moveQty = math.min(stack.quantity, math.min(room, weightRoom));
          if (moveQty > 0) {
            entry.stack.quantity += moveQty;
            stack.quantity -= moveQty;
          }
        }
      }
    }

    if (stack.quantity <= 0) return 0;

    // 2. Place remaining stack(s) into free grid slots
    while (stack.quantity > 0) {
      final chunkQty = math.min(stack.quantity, stack.definition.maxStack);
      final chunkWeight = chunkQty * stack.definition.weight;
      if (!fitsWeight(chunkWeight)) break;

      final piece = chunkQty == stack.quantity
          ? stack
          : ItemStack(
              stack.definition,
              quantity: chunkQty,
              rotated: stack.rotated,
              durability: stack.durability,
              maxDurability: stack.maxDurability,
            );

      final slot = findFreeSlot(piece, allowRotate: allowAutoRotate);
      if (slot == null) break;

      piece.rotated = slot.rotated;
      _items.add(PlacedItem(piece, slot.x, slot.y));
      if (identical(piece, stack)) {
        return 0;
      }
      stack.quantity -= chunkQty;
    }

    return stack.quantity;
  }

  /// Splits [amount] off [source] and places the new stack in the next free slot.
  ItemStack? splitToFreeSlot(ItemStack source, int amount) {
    if (_findEntry(source) == null) return null;
    if (amount <= 0 || amount >= source.quantity) return null;
    final split = ItemStack(source.definition, quantity: amount);
    final slot = findFreeSlot(split);
    if (slot == null) return null;
    source.quantity -= amount;
    split.rotated = slot.rotated;
    _items.add(PlacedItem(split, slot.x, slot.y));
    return split;
  }

  /// Removes a specific [ItemStack] instance from the grid.
  bool removeItem(ItemStack stack) {
    final idx = _items.indexWhere((e) => identical(e.stack, stack));
    if (idx < 0) return false;
    _items.removeAt(idx);
    return true;
  }

  /// Consumes up to [quantity] items matching [itemId], returning the actual count removed.
  int removeById(String itemId, int quantity) {
    int remaining = quantity;
    for (int i = _items.length - 1; i >= 0 && remaining > 0; i--) {
      final entry = _items[i];
      if (entry.stack.definition.id == itemId) {
        final take = math.min(remaining, entry.stack.quantity);
        entry.stack.quantity -= take;
        remaining -= take;
        if (entry.stack.quantity <= 0) {
          _items.removeAt(i);
        }
      }
    }
    return quantity - remaining;
  }

  /// Consumes up to [quantity] items matching [tag], returning the actual count removed.
  int removeByTag(String tag, int quantity) {
    int remaining = quantity;
    for (int i = _items.length - 1; i >= 0 && remaining > 0; i--) {
      final entry = _items[i];
      if (entry.stack.definition.hasTag(tag)) {
        final take = math.min(remaining, entry.stack.quantity);
        entry.stack.quantity -= take;
        remaining -= take;
        if (entry.stack.quantity <= 0) {
          _items.removeAt(i);
        }
      }
    }
    return quantity - remaining;
  }

  /// Counts total quantity across all stacks with [itemId].
  int countById(String itemId) {
    int total = 0;
    for (final e in _items) {
      if (e.stack.definition.id == itemId) total += e.stack.quantity;
    }
    return total;
  }

  /// Counts total quantity across all stacks possessing [tag].
  int countByTag(String tag) {
    int total = 0;
    for (final e in _items) {
      if (e.stack.definition.hasTag(tag)) total += e.stack.quantity;
    }
    return total;
  }

  void clear() => _items.clear();

  PlacedItem? _findEntry(ItemStack stack) {
    for (final e in _items) {
      if (identical(e.stack, stack)) return e;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'width': width,
        'height': height,
        'items': _items
            .map((e) => {
                  'x': e.x,
                  'y': e.y,
                  ...e.stack.toJson(),
                })
            .toList(),
      };

  void loadJson(Map<String, dynamic> data, ItemRegistry registry) {
    clear();
    final rawItems = data['items'] as List? ?? [];
    for (final itemJson in rawItems) {
      final map = itemJson as Map<String, dynamic>;
      final def = registry.get(map['id'] as String);
      if (def == null) continue;
      final stack = ItemStack(
        def,
        quantity: (map['qty'] as int?) ?? 1,
        rotated: (map['rot'] as bool?) ?? false,
        durability: (map['durability'] as num?)?.toDouble() ?? 100.0,
      );
      placeAt(stack, map['x'] as int, map['y'] as int, rotated: stack.rotated);
    }
  }
}
