// models/plan.dart
class Plan {
  final int id;
  final String code;
  final String name;
  final String description;
  final int price;
  final String currency;
  final bool isLifetime;
  final List<PlanFeature> features;

  Plan({
    required this.id,
    required this.code,
    required this.name,
    required this.description,
    required this.price,
    required this.currency,
    required this.isLifetime,
    required this.features,
  });

  factory Plan.fromJson(Map<String, dynamic> json) {
    return Plan(
      id: _parseInt(json['id']),
      code: json['code']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      price: _parseInt(json['price']),
      currency: json['currency']?.toString() ?? 'COP',
      isLifetime: _parseBool(json['is_lifetime']),
      features: (json['features'] as List? ?? [])
          .map((feature) => PlanFeature.fromJson(feature))
          .toList(),
    );
  }

  // 🔴 NUEVO: Método auxiliar para parsear ints
  static int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is String) {
      try {
        return int.parse(value);
      } catch (e) {
        return 0;
      }
    }
    if (value is double) return value.toInt();
    return 0;
  }

  // 🔴 NUEVO: Método auxiliar para parsear bools
  static bool _parseBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is int) return value == 1;
    if (value is String) {
      return value.toLowerCase() == 'true' || value == '1';
    }
    return false;
  }

  String get formattedPrice {
    return '\$${price.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (match) => '${match[1]}.',
        )}';
  }

  bool get isPremium => code.contains('premium');

  String get period {
    if (isLifetime) return 'Vitalicio';
    if (code.contains('monthly')) return 'Mensual';
    if (code.contains('annual')) return 'Anual';
    return 'Único';
  }
}

class PlanFeature {
  final String text;
  final bool included;

  PlanFeature({
    required this.text,
    required this.included,
  });

  factory PlanFeature.fromJson(Map<String, dynamic> json) {
    return PlanFeature(
      text: json['text']?.toString() ?? '',
      included: Plan._parseBool(json['included']), // 🔴 Usar el mismo helper
    );
  }
}