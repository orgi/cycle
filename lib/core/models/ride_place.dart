/// What a [RidePlace] does to a ride.
enum PlaceTrigger {
  /// Leaving the place starts a ride.
  start('Start', 'Starts a ride when you leave'),

  /// Arriving at the place stops the ride.
  stop('Stop', 'Stops the ride when you arrive'),

  /// Both: leaving starts a ride, arriving stops it (home, work).
  startAndStop(
    'Both',
    'Starts a ride when you leave, stops it when you arrive',
  );

  const PlaceTrigger(this.label, this.description);
  final String label;
  final String description;

  bool get startsRides => this != stop;
  bool get stopsRides => this != start;
}

/// A place where rides start or stop by themselves: a circle of
/// [radiusMeters] around a point (see `PlaceTriggerDetector` for the rule).
/// Belongs to the phone, not to a bike. Immutable.
class RidePlace {
  const RidePlace({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.radiusMeters = defaultRadiusMeters,
    this.trigger = PlaceTrigger.startAndStop,
  });

  static const double defaultRadiusMeters = 50;

  /// The radii offered when editing a place. Below 25 m a good fix's own
  /// error (up to 10 m) is a large part of the circle.
  static const List<double> radiusChoices = [25, 50, 100, 200];

  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final double radiusMeters;
  final PlaceTrigger trigger;

  RidePlace copyWith({
    String? name,
    double? latitude,
    double? longitude,
    double? radiusMeters,
    PlaceTrigger? trigger,
  }) => RidePlace(
    id: id,
    name: name ?? this.name,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    radiusMeters: radiusMeters ?? this.radiusMeters,
    trigger: trigger ?? this.trigger,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'lat': latitude,
    'lon': longitude,
    'radius_m': radiusMeters,
    'trigger': trigger.name,
  };

  /// Null for an entry without a usable id or position. A missing radius or
  /// an unknown trigger falls back to the default.
  static RidePlace? fromJson(Map<String, dynamic> json) {
    final id = json['id'], lat = json['lat'], lon = json['lon'];
    if (id is! String || lat is! num || lon is! num) return null;
    final radius = json['radius_m'];
    return RidePlace(
      id: id,
      name: json['name'] is String ? json['name'] as String : 'Place',
      latitude: lat.toDouble(),
      longitude: lon.toDouble(),
      radiusMeters: radius is num && radius > 0
          ? radius.toDouble()
          : defaultRadiusMeters,
      trigger: PlaceTrigger.values.firstWhere(
        (t) => t.name == json['trigger'],
        orElse: () => PlaceTrigger.startAndStop,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RidePlace &&
      other.id == id &&
      other.name == name &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.radiusMeters == radiusMeters &&
      other.trigger == trigger;

  @override
  int get hashCode =>
      Object.hash(id, name, latitude, longitude, radiusMeters, trigger);

  @override
  String toString() => 'RidePlace(${toJson()})';
}
