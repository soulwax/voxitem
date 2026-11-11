import 'item_definition.dart';

/// Mutable runtime instance holding one or more stacked items of a single [ItemDefinition].
class ItemStack {
  static int _nextInstanceSeq = 1;

  final String instanceId;
  final ItemDefinition definition;
  int quantity;
  bool rotated;
  double durability;
  final double maxDurability;
  final Map<String, dynamic> customData;

  ItemStack(
    this.definition, {
    this.quantity = 1,
    this.rotated = false,
    String? instanceId,
    this.durability = 100.0,
    this.maxDurability = 100.0,
    Map<String, dynamic>? customData,
  })  : instanceId = instanceId ?? 'item_${_nextInstanceSeq++}',
        customData = customData ?? {};

  int get effectiveWidth => rotated ? definition.gridHeight : definition.gridWidth;
  int get effectiveHeight => rotated ? definition.gridWidth : definition.gridHeight;
  double get totalWeight => definition.weight * quantity;
  int get remainingCapacity => (definition.maxStack - quantity).clamp(0, definition.maxStack);
  bool get isFull => quantity >= definition.maxStack;
  bool get isEmpty => quantity <= 0;

  /// Whether [other] can merge into this stack (same item definition, stackable, and custom data compatible).
  bool canStackWith(ItemStack other) {
    if (identical(this, other)) return false;
    if (definition.id != other.definition.id) return false;
    if (definition.maxStack <= 1 || isFull) return false;
    if (customData.isNotEmpty || other.customData.isNotEmpty) return false;
    return true;
  }

  /// Splits [amount] items off this stack into a new [ItemStack], returning null if invalid.
  ItemStack? split(int amount) {
    if (amount <= 0 || amount >= quantity) return null;
    quantity -= amount;
    return ItemStack(
      definition,
      quantity: amount,
      rotated: rotated,
      durability: durability,
      maxDurability: maxDurability,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': definition.id,
        'qty': quantity,
        'rot': rotated,
        if (durability != maxDurability) 'durability': durability,
      };
}
