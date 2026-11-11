import 'dart:math' as math;

/// How a [StatModifier] combines with base and sibling modifiers.
enum StatModifierType {
  /// Added directly to base value before percentage scaling.
  flat(100),

  /// Summed together with all other [percentAdd] modifiers into a single scaling factor: `(base + flatSum) * (1 + sumPercentAdd)`.
  percentAdd(200),

  /// Applied multiplicatively one after another: `value *= (1 + modifier.value)`.
  percentMult(300);

  final int defaultOrder;
  const StatModifierType(this.defaultOrder);
}

/// Single additive or multiplicative buff/debuff targeting a named stat.
class StatModifier {
  final String statName;
  final double value;
  final StatModifierType type;
  final int order;
  final Object? source;

  StatModifier({
    required this.statName,
    required this.value,
    this.type = StatModifierType.flat,
    int? order,
    this.source,
  }) : order = order ?? type.defaultOrder;
}

/// Evaluable stat tracking a base scalar and sorted [StatModifier] stack.
class StatValue {
  double _baseValue;
  final double? minValue;
  final double? maxValue;

  final List<StatModifier> _modifiers = [];
  bool _dirty = true;
  double _cachedValue = 0.0;

  StatValue(
    double baseValue, {
    this.minValue,
    this.maxValue,
  }) : _baseValue = baseValue;

  double get baseValue => _baseValue;
  set baseValue(double v) {
    if (_baseValue != v) {
      _baseValue = v;
      _dirty = true;
    }
  }

  List<StatModifier> get modifiers => List.unmodifiable(_modifiers);

  /// Current effective value after evaluating all active modifiers cleanly in order.
  double get value {
    if (_dirty) {
      _cachedValue = _recalculate();
      _dirty = false;
    }
    return _cachedValue;
  }

  void addModifier(StatModifier mod) {
    _modifiers.add(mod);
    _modifiers.sort((a, b) => a.order.compareTo(b.order));
    _dirty = true;
  }

  bool removeModifier(StatModifier mod) {
    final removed = _modifiers.remove(mod);
    if (removed) _dirty = true;
    return removed;
  }

  /// Removes every modifier tagged with [source] (e.g., unequipped item or expired buff).
  int removeModifiersFromSource(Object source) {
    final before = _modifiers.length;
    _modifiers.removeWhere((m) => identical(m.source, source) || m.source == source);
    final removed = before - _modifiers.length;
    if (removed > 0) _dirty = true;
    return removed;
  }

  void clearModifiers() {
    if (_modifiers.isEmpty) return;
    _modifiers.clear();
    _dirty = true;
  }

  double _recalculate() {
    double finalValue = _baseValue;
    double sumPercentAdd = 0.0;

    for (int i = 0; i < _modifiers.length; i++) {
      final mod = _modifiers[i];
      if (mod.type == StatModifierType.flat) {
        finalValue += mod.value;
      } else if (mod.type == StatModifierType.percentAdd) {
        sumPercentAdd += mod.value;
        final isLast = i + 1 >= _modifiers.length ||
            _modifiers[i + 1].type != StatModifierType.percentAdd;
        if (isLast) {
          finalValue *= 1.0 + sumPercentAdd;
          sumPercentAdd = 0.0;
        }
      } else if (mod.type == StatModifierType.percentMult) {
        finalValue *= 1.0 + mod.value;
      }
    }

    if (minValue != null) finalValue = math.max(minValue!, finalValue);
    if (maxValue != null) finalValue = math.min(maxValue!, finalValue);
    return (finalValue * 10000).roundToDouble() / 10000.0;
  }
}

/// Collection of named stats (HP, Attack, Armor, Speed, CritChance) for a character or unit.
class StatBlock {
  final Map<String, StatValue> _stats = {};

  StatBlock([Map<String, double>? initialBaseStats]) {
    if (initialBaseStats != null) {
      for (final e in initialBaseStats.entries) {
        _stats[e.key] = StatValue(e.value);
      }
    }
  }

  StatValue defineStat(String name, double baseValue, {double? minValue, double? maxValue}) {
    final stat = StatValue(baseValue, minValue: minValue, maxValue: maxValue);
    _stats[name] = stat;
    return stat;
  }

  StatValue? getStat(String name) => _stats[name];

  double getValue(String name, {double fallback = 0.0}) => _stats[name]?.value ?? fallback;

  void setBase(String name, double value) {
    final existing = _stats[name];
    if (existing != null) {
      existing.baseValue = value;
    } else {
      _stats[name] = StatValue(value);
    }
  }

  void addModifier(StatModifier mod, {Object? overrideSource}) {
    final stat = _stats.putIfAbsent(mod.statName, () => StatValue(0.0));
    final effectiveMod = overrideSource == null
        ? mod
        : StatModifier(
            statName: mod.statName,
            value: mod.value,
            type: mod.type,
            order: mod.order,
            source: overrideSource,
          );
    stat.addModifier(effectiveMod);
  }

  int removeModifiersFromSource(Object source) {
    int count = 0;
    for (final stat in _stats.values) {
      count += stat.removeModifiersFromSource(source);
    }
    return count;
  }
}
