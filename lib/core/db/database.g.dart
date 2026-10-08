// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $TracksTable extends Tracks with TableInfo<$TracksTable, Track> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TracksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('Ride'),
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
    'started_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endedAtMeta = const VerificationMeta(
    'endedAt',
  );
  @override
  late final GeneratedColumn<DateTime> endedAt = GeneratedColumn<DateTime>(
    'ended_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _distanceMetersMeta = const VerificationMeta(
    'distanceMeters',
  );
  @override
  late final GeneratedColumn<double> distanceMeters = GeneratedColumn<double>(
    'distance_meters',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _durationSecondsMeta = const VerificationMeta(
    'durationSeconds',
  );
  @override
  late final GeneratedColumn<int> durationSeconds = GeneratedColumn<int>(
    'duration_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _avgSpeedMpsMeta = const VerificationMeta(
    'avgSpeedMps',
  );
  @override
  late final GeneratedColumn<double> avgSpeedMps = GeneratedColumn<double>(
    'avg_speed_mps',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _maxSpeedMpsMeta = const VerificationMeta(
    'maxSpeedMps',
  );
  @override
  late final GeneratedColumn<double> maxSpeedMps = GeneratedColumn<double>(
    'max_speed_mps',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _batteryStartPercentMeta =
      const VerificationMeta('batteryStartPercent');
  @override
  late final GeneratedColumn<int> batteryStartPercent = GeneratedColumn<int>(
    'battery_start_percent',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _batteryEndPercentMeta = const VerificationMeta(
    'batteryEndPercent',
  );
  @override
  late final GeneratedColumn<int> batteryEndPercent = GeneratedColumn<int>(
    'battery_end_percent',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bikeProfileIdMeta = const VerificationMeta(
    'bikeProfileId',
  );
  @override
  late final GeneratedColumn<String> bikeProfileId = GeneratedColumn<String>(
    'bike_profile_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameClockMeta = const VerificationMeta(
    'nameClock',
  );
  @override
  late final GeneratedColumn<String> nameClock = GeneratedColumn<String>(
    'name_clock',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bikeClockMeta = const VerificationMeta(
    'bikeClock',
  );
  @override
  late final GeneratedColumn<String> bikeClock = GeneratedColumn<String>(
    'bike_clock',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _geometryClockMeta = const VerificationMeta(
    'geometryClock',
  );
  @override
  late final GeneratedColumn<String> geometryClock = GeneratedColumn<String>(
    'geometry_clock',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deletedClockMeta = const VerificationMeta(
    'deletedClock',
  );
  @override
  late final GeneratedColumn<String> deletedClock = GeneratedColumn<String>(
    'deleted_clock',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pointsPurgedMeta = const VerificationMeta(
    'pointsPurged',
  );
  @override
  late final GeneratedColumn<bool> pointsPurged = GeneratedColumn<bool>(
    'points_purged',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("points_purged" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    startedAt,
    endedAt,
    distanceMeters,
    durationSeconds,
    avgSpeedMps,
    maxSpeedMps,
    batteryStartPercent,
    batteryEndPercent,
    bikeProfileId,
    nameClock,
    bikeClock,
    geometryClock,
    deletedClock,
    deletedAt,
    pointsPurged,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tracks';
  @override
  VerificationContext validateIntegrity(
    Insertable<Track> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('ended_at')) {
      context.handle(
        _endedAtMeta,
        endedAt.isAcceptableOrUnknown(data['ended_at']!, _endedAtMeta),
      );
    }
    if (data.containsKey('distance_meters')) {
      context.handle(
        _distanceMetersMeta,
        distanceMeters.isAcceptableOrUnknown(
          data['distance_meters']!,
          _distanceMetersMeta,
        ),
      );
    }
    if (data.containsKey('duration_seconds')) {
      context.handle(
        _durationSecondsMeta,
        durationSeconds.isAcceptableOrUnknown(
          data['duration_seconds']!,
          _durationSecondsMeta,
        ),
      );
    }
    if (data.containsKey('avg_speed_mps')) {
      context.handle(
        _avgSpeedMpsMeta,
        avgSpeedMps.isAcceptableOrUnknown(
          data['avg_speed_mps']!,
          _avgSpeedMpsMeta,
        ),
      );
    }
    if (data.containsKey('max_speed_mps')) {
      context.handle(
        _maxSpeedMpsMeta,
        maxSpeedMps.isAcceptableOrUnknown(
          data['max_speed_mps']!,
          _maxSpeedMpsMeta,
        ),
      );
    }
    if (data.containsKey('battery_start_percent')) {
      context.handle(
        _batteryStartPercentMeta,
        batteryStartPercent.isAcceptableOrUnknown(
          data['battery_start_percent']!,
          _batteryStartPercentMeta,
        ),
      );
    }
    if (data.containsKey('battery_end_percent')) {
      context.handle(
        _batteryEndPercentMeta,
        batteryEndPercent.isAcceptableOrUnknown(
          data['battery_end_percent']!,
          _batteryEndPercentMeta,
        ),
      );
    }
    if (data.containsKey('bike_profile_id')) {
      context.handle(
        _bikeProfileIdMeta,
        bikeProfileId.isAcceptableOrUnknown(
          data['bike_profile_id']!,
          _bikeProfileIdMeta,
        ),
      );
    }
    if (data.containsKey('name_clock')) {
      context.handle(
        _nameClockMeta,
        nameClock.isAcceptableOrUnknown(data['name_clock']!, _nameClockMeta),
      );
    }
    if (data.containsKey('bike_clock')) {
      context.handle(
        _bikeClockMeta,
        bikeClock.isAcceptableOrUnknown(data['bike_clock']!, _bikeClockMeta),
      );
    }
    if (data.containsKey('geometry_clock')) {
      context.handle(
        _geometryClockMeta,
        geometryClock.isAcceptableOrUnknown(
          data['geometry_clock']!,
          _geometryClockMeta,
        ),
      );
    }
    if (data.containsKey('deleted_clock')) {
      context.handle(
        _deletedClockMeta,
        deletedClock.isAcceptableOrUnknown(
          data['deleted_clock']!,
          _deletedClockMeta,
        ),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('points_purged')) {
      context.handle(
        _pointsPurgedMeta,
        pointsPurged.isAcceptableOrUnknown(
          data['points_purged']!,
          _pointsPurgedMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Track map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Track(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}started_at'],
      )!,
      endedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}ended_at'],
      ),
      distanceMeters: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}distance_meters'],
      )!,
      durationSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_seconds'],
      )!,
      avgSpeedMps: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}avg_speed_mps'],
      )!,
      maxSpeedMps: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}max_speed_mps'],
      )!,
      batteryStartPercent: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}battery_start_percent'],
      ),
      batteryEndPercent: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}battery_end_percent'],
      ),
      bikeProfileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}bike_profile_id'],
      ),
      nameClock: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name_clock'],
      ),
      bikeClock: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}bike_clock'],
      ),
      geometryClock: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}geometry_clock'],
      ),
      deletedClock: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}deleted_clock'],
      ),
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      pointsPurged: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}points_purged'],
      )!,
    );
  }

  @override
  $TracksTable createAlias(String alias) {
    return $TracksTable(attachedDatabase, alias);
  }
}

class Track extends DataClass implements Insertable<Track> {
  final int id;
  final String name;
  final DateTime startedAt;
  final DateTime? endedAt;
  final double distanceMeters;
  final int durationSeconds;
  final double avgSpeedMps;
  final double maxSpeedMps;
  final int? batteryStartPercent;
  final int? batteryEndPercent;
  final String? bikeProfileId;
  final String? nameClock;
  final String? bikeClock;
  final String? geometryClock;
  final String? deletedClock;
  final DateTime? deletedAt;
  final bool pointsPurged;
  const Track({
    required this.id,
    required this.name,
    required this.startedAt,
    this.endedAt,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.avgSpeedMps,
    required this.maxSpeedMps,
    this.batteryStartPercent,
    this.batteryEndPercent,
    this.bikeProfileId,
    this.nameClock,
    this.bikeClock,
    this.geometryClock,
    this.deletedClock,
    this.deletedAt,
    required this.pointsPurged,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['started_at'] = Variable<DateTime>(startedAt);
    if (!nullToAbsent || endedAt != null) {
      map['ended_at'] = Variable<DateTime>(endedAt);
    }
    map['distance_meters'] = Variable<double>(distanceMeters);
    map['duration_seconds'] = Variable<int>(durationSeconds);
    map['avg_speed_mps'] = Variable<double>(avgSpeedMps);
    map['max_speed_mps'] = Variable<double>(maxSpeedMps);
    if (!nullToAbsent || batteryStartPercent != null) {
      map['battery_start_percent'] = Variable<int>(batteryStartPercent);
    }
    if (!nullToAbsent || batteryEndPercent != null) {
      map['battery_end_percent'] = Variable<int>(batteryEndPercent);
    }
    if (!nullToAbsent || bikeProfileId != null) {
      map['bike_profile_id'] = Variable<String>(bikeProfileId);
    }
    if (!nullToAbsent || nameClock != null) {
      map['name_clock'] = Variable<String>(nameClock);
    }
    if (!nullToAbsent || bikeClock != null) {
      map['bike_clock'] = Variable<String>(bikeClock);
    }
    if (!nullToAbsent || geometryClock != null) {
      map['geometry_clock'] = Variable<String>(geometryClock);
    }
    if (!nullToAbsent || deletedClock != null) {
      map['deleted_clock'] = Variable<String>(deletedClock);
    }
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['points_purged'] = Variable<bool>(pointsPurged);
    return map;
  }

  TracksCompanion toCompanion(bool nullToAbsent) {
    return TracksCompanion(
      id: Value(id),
      name: Value(name),
      startedAt: Value(startedAt),
      endedAt: endedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(endedAt),
      distanceMeters: Value(distanceMeters),
      durationSeconds: Value(durationSeconds),
      avgSpeedMps: Value(avgSpeedMps),
      maxSpeedMps: Value(maxSpeedMps),
      batteryStartPercent: batteryStartPercent == null && nullToAbsent
          ? const Value.absent()
          : Value(batteryStartPercent),
      batteryEndPercent: batteryEndPercent == null && nullToAbsent
          ? const Value.absent()
          : Value(batteryEndPercent),
      bikeProfileId: bikeProfileId == null && nullToAbsent
          ? const Value.absent()
          : Value(bikeProfileId),
      nameClock: nameClock == null && nullToAbsent
          ? const Value.absent()
          : Value(nameClock),
      bikeClock: bikeClock == null && nullToAbsent
          ? const Value.absent()
          : Value(bikeClock),
      geometryClock: geometryClock == null && nullToAbsent
          ? const Value.absent()
          : Value(geometryClock),
      deletedClock: deletedClock == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedClock),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      pointsPurged: Value(pointsPurged),
    );
  }

  factory Track.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Track(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      startedAt: serializer.fromJson<DateTime>(json['startedAt']),
      endedAt: serializer.fromJson<DateTime?>(json['endedAt']),
      distanceMeters: serializer.fromJson<double>(json['distanceMeters']),
      durationSeconds: serializer.fromJson<int>(json['durationSeconds']),
      avgSpeedMps: serializer.fromJson<double>(json['avgSpeedMps']),
      maxSpeedMps: serializer.fromJson<double>(json['maxSpeedMps']),
      batteryStartPercent: serializer.fromJson<int?>(
        json['batteryStartPercent'],
      ),
      batteryEndPercent: serializer.fromJson<int?>(json['batteryEndPercent']),
      bikeProfileId: serializer.fromJson<String?>(json['bikeProfileId']),
      nameClock: serializer.fromJson<String?>(json['nameClock']),
      bikeClock: serializer.fromJson<String?>(json['bikeClock']),
      geometryClock: serializer.fromJson<String?>(json['geometryClock']),
      deletedClock: serializer.fromJson<String?>(json['deletedClock']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      pointsPurged: serializer.fromJson<bool>(json['pointsPurged']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'startedAt': serializer.toJson<DateTime>(startedAt),
      'endedAt': serializer.toJson<DateTime?>(endedAt),
      'distanceMeters': serializer.toJson<double>(distanceMeters),
      'durationSeconds': serializer.toJson<int>(durationSeconds),
      'avgSpeedMps': serializer.toJson<double>(avgSpeedMps),
      'maxSpeedMps': serializer.toJson<double>(maxSpeedMps),
      'batteryStartPercent': serializer.toJson<int?>(batteryStartPercent),
      'batteryEndPercent': serializer.toJson<int?>(batteryEndPercent),
      'bikeProfileId': serializer.toJson<String?>(bikeProfileId),
      'nameClock': serializer.toJson<String?>(nameClock),
      'bikeClock': serializer.toJson<String?>(bikeClock),
      'geometryClock': serializer.toJson<String?>(geometryClock),
      'deletedClock': serializer.toJson<String?>(deletedClock),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'pointsPurged': serializer.toJson<bool>(pointsPurged),
    };
  }

  Track copyWith({
    int? id,
    String? name,
    DateTime? startedAt,
    Value<DateTime?> endedAt = const Value.absent(),
    double? distanceMeters,
    int? durationSeconds,
    double? avgSpeedMps,
    double? maxSpeedMps,
    Value<int?> batteryStartPercent = const Value.absent(),
    Value<int?> batteryEndPercent = const Value.absent(),
    Value<String?> bikeProfileId = const Value.absent(),
    Value<String?> nameClock = const Value.absent(),
    Value<String?> bikeClock = const Value.absent(),
    Value<String?> geometryClock = const Value.absent(),
    Value<String?> deletedClock = const Value.absent(),
    Value<DateTime?> deletedAt = const Value.absent(),
    bool? pointsPurged,
  }) => Track(
    id: id ?? this.id,
    name: name ?? this.name,
    startedAt: startedAt ?? this.startedAt,
    endedAt: endedAt.present ? endedAt.value : this.endedAt,
    distanceMeters: distanceMeters ?? this.distanceMeters,
    durationSeconds: durationSeconds ?? this.durationSeconds,
    avgSpeedMps: avgSpeedMps ?? this.avgSpeedMps,
    maxSpeedMps: maxSpeedMps ?? this.maxSpeedMps,
    batteryStartPercent: batteryStartPercent.present
        ? batteryStartPercent.value
        : this.batteryStartPercent,
    batteryEndPercent: batteryEndPercent.present
        ? batteryEndPercent.value
        : this.batteryEndPercent,
    bikeProfileId: bikeProfileId.present
        ? bikeProfileId.value
        : this.bikeProfileId,
    nameClock: nameClock.present ? nameClock.value : this.nameClock,
    bikeClock: bikeClock.present ? bikeClock.value : this.bikeClock,
    geometryClock: geometryClock.present
        ? geometryClock.value
        : this.geometryClock,
    deletedClock: deletedClock.present ? deletedClock.value : this.deletedClock,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    pointsPurged: pointsPurged ?? this.pointsPurged,
  );
  Track copyWithCompanion(TracksCompanion data) {
    return Track(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      endedAt: data.endedAt.present ? data.endedAt.value : this.endedAt,
      distanceMeters: data.distanceMeters.present
          ? data.distanceMeters.value
          : this.distanceMeters,
      durationSeconds: data.durationSeconds.present
          ? data.durationSeconds.value
          : this.durationSeconds,
      avgSpeedMps: data.avgSpeedMps.present
          ? data.avgSpeedMps.value
          : this.avgSpeedMps,
      maxSpeedMps: data.maxSpeedMps.present
          ? data.maxSpeedMps.value
          : this.maxSpeedMps,
      batteryStartPercent: data.batteryStartPercent.present
          ? data.batteryStartPercent.value
          : this.batteryStartPercent,
      batteryEndPercent: data.batteryEndPercent.present
          ? data.batteryEndPercent.value
          : this.batteryEndPercent,
      bikeProfileId: data.bikeProfileId.present
          ? data.bikeProfileId.value
          : this.bikeProfileId,
      nameClock: data.nameClock.present ? data.nameClock.value : this.nameClock,
      bikeClock: data.bikeClock.present ? data.bikeClock.value : this.bikeClock,
      geometryClock: data.geometryClock.present
          ? data.geometryClock.value
          : this.geometryClock,
      deletedClock: data.deletedClock.present
          ? data.deletedClock.value
          : this.deletedClock,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      pointsPurged: data.pointsPurged.present
          ? data.pointsPurged.value
          : this.pointsPurged,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Track(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('distanceMeters: $distanceMeters, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('avgSpeedMps: $avgSpeedMps, ')
          ..write('maxSpeedMps: $maxSpeedMps, ')
          ..write('batteryStartPercent: $batteryStartPercent, ')
          ..write('batteryEndPercent: $batteryEndPercent, ')
          ..write('bikeProfileId: $bikeProfileId, ')
          ..write('nameClock: $nameClock, ')
          ..write('bikeClock: $bikeClock, ')
          ..write('geometryClock: $geometryClock, ')
          ..write('deletedClock: $deletedClock, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('pointsPurged: $pointsPurged')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    startedAt,
    endedAt,
    distanceMeters,
    durationSeconds,
    avgSpeedMps,
    maxSpeedMps,
    batteryStartPercent,
    batteryEndPercent,
    bikeProfileId,
    nameClock,
    bikeClock,
    geometryClock,
    deletedClock,
    deletedAt,
    pointsPurged,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Track &&
          other.id == this.id &&
          other.name == this.name &&
          other.startedAt == this.startedAt &&
          other.endedAt == this.endedAt &&
          other.distanceMeters == this.distanceMeters &&
          other.durationSeconds == this.durationSeconds &&
          other.avgSpeedMps == this.avgSpeedMps &&
          other.maxSpeedMps == this.maxSpeedMps &&
          other.batteryStartPercent == this.batteryStartPercent &&
          other.batteryEndPercent == this.batteryEndPercent &&
          other.bikeProfileId == this.bikeProfileId &&
          other.nameClock == this.nameClock &&
          other.bikeClock == this.bikeClock &&
          other.geometryClock == this.geometryClock &&
          other.deletedClock == this.deletedClock &&
          other.deletedAt == this.deletedAt &&
          other.pointsPurged == this.pointsPurged);
}

class TracksCompanion extends UpdateCompanion<Track> {
  final Value<int> id;
  final Value<String> name;
  final Value<DateTime> startedAt;
  final Value<DateTime?> endedAt;
  final Value<double> distanceMeters;
  final Value<int> durationSeconds;
  final Value<double> avgSpeedMps;
  final Value<double> maxSpeedMps;
  final Value<int?> batteryStartPercent;
  final Value<int?> batteryEndPercent;
  final Value<String?> bikeProfileId;
  final Value<String?> nameClock;
  final Value<String?> bikeClock;
  final Value<String?> geometryClock;
  final Value<String?> deletedClock;
  final Value<DateTime?> deletedAt;
  final Value<bool> pointsPurged;
  const TracksCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.endedAt = const Value.absent(),
    this.distanceMeters = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    this.avgSpeedMps = const Value.absent(),
    this.maxSpeedMps = const Value.absent(),
    this.batteryStartPercent = const Value.absent(),
    this.batteryEndPercent = const Value.absent(),
    this.bikeProfileId = const Value.absent(),
    this.nameClock = const Value.absent(),
    this.bikeClock = const Value.absent(),
    this.geometryClock = const Value.absent(),
    this.deletedClock = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.pointsPurged = const Value.absent(),
  });
  TracksCompanion.insert({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    required DateTime startedAt,
    this.endedAt = const Value.absent(),
    this.distanceMeters = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    this.avgSpeedMps = const Value.absent(),
    this.maxSpeedMps = const Value.absent(),
    this.batteryStartPercent = const Value.absent(),
    this.batteryEndPercent = const Value.absent(),
    this.bikeProfileId = const Value.absent(),
    this.nameClock = const Value.absent(),
    this.bikeClock = const Value.absent(),
    this.geometryClock = const Value.absent(),
    this.deletedClock = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.pointsPurged = const Value.absent(),
  }) : startedAt = Value(startedAt);
  static Insertable<Track> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<DateTime>? startedAt,
    Expression<DateTime>? endedAt,
    Expression<double>? distanceMeters,
    Expression<int>? durationSeconds,
    Expression<double>? avgSpeedMps,
    Expression<double>? maxSpeedMps,
    Expression<int>? batteryStartPercent,
    Expression<int>? batteryEndPercent,
    Expression<String>? bikeProfileId,
    Expression<String>? nameClock,
    Expression<String>? bikeClock,
    Expression<String>? geometryClock,
    Expression<String>? deletedClock,
    Expression<DateTime>? deletedAt,
    Expression<bool>? pointsPurged,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (startedAt != null) 'started_at': startedAt,
      if (endedAt != null) 'ended_at': endedAt,
      if (distanceMeters != null) 'distance_meters': distanceMeters,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
      if (avgSpeedMps != null) 'avg_speed_mps': avgSpeedMps,
      if (maxSpeedMps != null) 'max_speed_mps': maxSpeedMps,
      if (batteryStartPercent != null)
        'battery_start_percent': batteryStartPercent,
      if (batteryEndPercent != null) 'battery_end_percent': batteryEndPercent,
      if (bikeProfileId != null) 'bike_profile_id': bikeProfileId,
      if (nameClock != null) 'name_clock': nameClock,
      if (bikeClock != null) 'bike_clock': bikeClock,
      if (geometryClock != null) 'geometry_clock': geometryClock,
      if (deletedClock != null) 'deleted_clock': deletedClock,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (pointsPurged != null) 'points_purged': pointsPurged,
    });
  }

  TracksCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<DateTime>? startedAt,
    Value<DateTime?>? endedAt,
    Value<double>? distanceMeters,
    Value<int>? durationSeconds,
    Value<double>? avgSpeedMps,
    Value<double>? maxSpeedMps,
    Value<int?>? batteryStartPercent,
    Value<int?>? batteryEndPercent,
    Value<String?>? bikeProfileId,
    Value<String?>? nameClock,
    Value<String?>? bikeClock,
    Value<String?>? geometryClock,
    Value<String?>? deletedClock,
    Value<DateTime?>? deletedAt,
    Value<bool>? pointsPurged,
  }) {
    return TracksCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      avgSpeedMps: avgSpeedMps ?? this.avgSpeedMps,
      maxSpeedMps: maxSpeedMps ?? this.maxSpeedMps,
      batteryStartPercent: batteryStartPercent ?? this.batteryStartPercent,
      batteryEndPercent: batteryEndPercent ?? this.batteryEndPercent,
      bikeProfileId: bikeProfileId ?? this.bikeProfileId,
      nameClock: nameClock ?? this.nameClock,
      bikeClock: bikeClock ?? this.bikeClock,
      geometryClock: geometryClock ?? this.geometryClock,
      deletedClock: deletedClock ?? this.deletedClock,
      deletedAt: deletedAt ?? this.deletedAt,
      pointsPurged: pointsPurged ?? this.pointsPurged,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    if (endedAt.present) {
      map['ended_at'] = Variable<DateTime>(endedAt.value);
    }
    if (distanceMeters.present) {
      map['distance_meters'] = Variable<double>(distanceMeters.value);
    }
    if (durationSeconds.present) {
      map['duration_seconds'] = Variable<int>(durationSeconds.value);
    }
    if (avgSpeedMps.present) {
      map['avg_speed_mps'] = Variable<double>(avgSpeedMps.value);
    }
    if (maxSpeedMps.present) {
      map['max_speed_mps'] = Variable<double>(maxSpeedMps.value);
    }
    if (batteryStartPercent.present) {
      map['battery_start_percent'] = Variable<int>(batteryStartPercent.value);
    }
    if (batteryEndPercent.present) {
      map['battery_end_percent'] = Variable<int>(batteryEndPercent.value);
    }
    if (bikeProfileId.present) {
      map['bike_profile_id'] = Variable<String>(bikeProfileId.value);
    }
    if (nameClock.present) {
      map['name_clock'] = Variable<String>(nameClock.value);
    }
    if (bikeClock.present) {
      map['bike_clock'] = Variable<String>(bikeClock.value);
    }
    if (geometryClock.present) {
      map['geometry_clock'] = Variable<String>(geometryClock.value);
    }
    if (deletedClock.present) {
      map['deleted_clock'] = Variable<String>(deletedClock.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (pointsPurged.present) {
      map['points_purged'] = Variable<bool>(pointsPurged.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TracksCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('distanceMeters: $distanceMeters, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('avgSpeedMps: $avgSpeedMps, ')
          ..write('maxSpeedMps: $maxSpeedMps, ')
          ..write('batteryStartPercent: $batteryStartPercent, ')
          ..write('batteryEndPercent: $batteryEndPercent, ')
          ..write('bikeProfileId: $bikeProfileId, ')
          ..write('nameClock: $nameClock, ')
          ..write('bikeClock: $bikeClock, ')
          ..write('geometryClock: $geometryClock, ')
          ..write('deletedClock: $deletedClock, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('pointsPurged: $pointsPurged')
          ..write(')'))
        .toString();
  }
}

class $TrackPointsTable extends TrackPoints
    with TableInfo<$TrackPointsTable, TrackPoint> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TrackPointsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _trackIdMeta = const VerificationMeta(
    'trackId',
  );
  @override
  late final GeneratedColumn<int> trackId = GeneratedColumn<int>(
    'track_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES tracks (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _timeMeta = const VerificationMeta('time');
  @override
  late final GeneratedColumn<DateTime> time = GeneratedColumn<DateTime>(
    'time',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _latitudeMeta = const VerificationMeta(
    'latitude',
  );
  @override
  late final GeneratedColumn<double> latitude = GeneratedColumn<double>(
    'latitude',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _longitudeMeta = const VerificationMeta(
    'longitude',
  );
  @override
  late final GeneratedColumn<double> longitude = GeneratedColumn<double>(
    'longitude',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _altitudeMeta = const VerificationMeta(
    'altitude',
  );
  @override
  late final GeneratedColumn<double> altitude = GeneratedColumn<double>(
    'altitude',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _speedMpsMeta = const VerificationMeta(
    'speedMps',
  );
  @override
  late final GeneratedColumn<double> speedMps = GeneratedColumn<double>(
    'speed_mps',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _heartRateMeta = const VerificationMeta(
    'heartRate',
  );
  @override
  late final GeneratedColumn<int> heartRate = GeneratedColumn<int>(
    'heart_rate',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cadenceRpmMeta = const VerificationMeta(
    'cadenceRpm',
  );
  @override
  late final GeneratedColumn<double> cadenceRpm = GeneratedColumn<double>(
    'cadence_rpm',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _powerMeta = const VerificationMeta('power');
  @override
  late final GeneratedColumn<int> power = GeneratedColumn<int>(
    'power',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _speedFromSensorMeta = const VerificationMeta(
    'speedFromSensor',
  );
  @override
  late final GeneratedColumn<bool> speedFromSensor = GeneratedColumn<bool>(
    'speed_from_sensor',
    aliasedName,
    true,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("speed_from_sensor" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    trackId,
    time,
    latitude,
    longitude,
    altitude,
    speedMps,
    heartRate,
    cadenceRpm,
    power,
    speedFromSensor,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'track_points';
  @override
  VerificationContext validateIntegrity(
    Insertable<TrackPoint> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('track_id')) {
      context.handle(
        _trackIdMeta,
        trackId.isAcceptableOrUnknown(data['track_id']!, _trackIdMeta),
      );
    } else if (isInserting) {
      context.missing(_trackIdMeta);
    }
    if (data.containsKey('time')) {
      context.handle(
        _timeMeta,
        time.isAcceptableOrUnknown(data['time']!, _timeMeta),
      );
    } else if (isInserting) {
      context.missing(_timeMeta);
    }
    if (data.containsKey('latitude')) {
      context.handle(
        _latitudeMeta,
        latitude.isAcceptableOrUnknown(data['latitude']!, _latitudeMeta),
      );
    } else if (isInserting) {
      context.missing(_latitudeMeta);
    }
    if (data.containsKey('longitude')) {
      context.handle(
        _longitudeMeta,
        longitude.isAcceptableOrUnknown(data['longitude']!, _longitudeMeta),
      );
    } else if (isInserting) {
      context.missing(_longitudeMeta);
    }
    if (data.containsKey('altitude')) {
      context.handle(
        _altitudeMeta,
        altitude.isAcceptableOrUnknown(data['altitude']!, _altitudeMeta),
      );
    }
    if (data.containsKey('speed_mps')) {
      context.handle(
        _speedMpsMeta,
        speedMps.isAcceptableOrUnknown(data['speed_mps']!, _speedMpsMeta),
      );
    }
    if (data.containsKey('heart_rate')) {
      context.handle(
        _heartRateMeta,
        heartRate.isAcceptableOrUnknown(data['heart_rate']!, _heartRateMeta),
      );
    }
    if (data.containsKey('cadence_rpm')) {
      context.handle(
        _cadenceRpmMeta,
        cadenceRpm.isAcceptableOrUnknown(data['cadence_rpm']!, _cadenceRpmMeta),
      );
    }
    if (data.containsKey('power')) {
      context.handle(
        _powerMeta,
        power.isAcceptableOrUnknown(data['power']!, _powerMeta),
      );
    }
    if (data.containsKey('speed_from_sensor')) {
      context.handle(
        _speedFromSensorMeta,
        speedFromSensor.isAcceptableOrUnknown(
          data['speed_from_sensor']!,
          _speedFromSensorMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TrackPoint map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TrackPoint(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      trackId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}track_id'],
      )!,
      time: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}time'],
      )!,
      latitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}latitude'],
      )!,
      longitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}longitude'],
      )!,
      altitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}altitude'],
      ),
      speedMps: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}speed_mps'],
      ),
      heartRate: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}heart_rate'],
      ),
      cadenceRpm: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}cadence_rpm'],
      ),
      power: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}power'],
      ),
      speedFromSensor: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}speed_from_sensor'],
      ),
    );
  }

  @override
  $TrackPointsTable createAlias(String alias) {
    return $TrackPointsTable(attachedDatabase, alias);
  }
}

class TrackPoint extends DataClass implements Insertable<TrackPoint> {
  final int id;
  final int trackId;
  final DateTime time;
  final double latitude;
  final double longitude;
  final double? altitude;
  final double? speedMps;
  final int? heartRate;
  final double? cadenceRpm;
  final int? power;
  final bool? speedFromSensor;
  const TrackPoint({
    required this.id,
    required this.trackId,
    required this.time,
    required this.latitude,
    required this.longitude,
    this.altitude,
    this.speedMps,
    this.heartRate,
    this.cadenceRpm,
    this.power,
    this.speedFromSensor,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['track_id'] = Variable<int>(trackId);
    map['time'] = Variable<DateTime>(time);
    map['latitude'] = Variable<double>(latitude);
    map['longitude'] = Variable<double>(longitude);
    if (!nullToAbsent || altitude != null) {
      map['altitude'] = Variable<double>(altitude);
    }
    if (!nullToAbsent || speedMps != null) {
      map['speed_mps'] = Variable<double>(speedMps);
    }
    if (!nullToAbsent || heartRate != null) {
      map['heart_rate'] = Variable<int>(heartRate);
    }
    if (!nullToAbsent || cadenceRpm != null) {
      map['cadence_rpm'] = Variable<double>(cadenceRpm);
    }
    if (!nullToAbsent || power != null) {
      map['power'] = Variable<int>(power);
    }
    if (!nullToAbsent || speedFromSensor != null) {
      map['speed_from_sensor'] = Variable<bool>(speedFromSensor);
    }
    return map;
  }

  TrackPointsCompanion toCompanion(bool nullToAbsent) {
    return TrackPointsCompanion(
      id: Value(id),
      trackId: Value(trackId),
      time: Value(time),
      latitude: Value(latitude),
      longitude: Value(longitude),
      altitude: altitude == null && nullToAbsent
          ? const Value.absent()
          : Value(altitude),
      speedMps: speedMps == null && nullToAbsent
          ? const Value.absent()
          : Value(speedMps),
      heartRate: heartRate == null && nullToAbsent
          ? const Value.absent()
          : Value(heartRate),
      cadenceRpm: cadenceRpm == null && nullToAbsent
          ? const Value.absent()
          : Value(cadenceRpm),
      power: power == null && nullToAbsent
          ? const Value.absent()
          : Value(power),
      speedFromSensor: speedFromSensor == null && nullToAbsent
          ? const Value.absent()
          : Value(speedFromSensor),
    );
  }

  factory TrackPoint.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TrackPoint(
      id: serializer.fromJson<int>(json['id']),
      trackId: serializer.fromJson<int>(json['trackId']),
      time: serializer.fromJson<DateTime>(json['time']),
      latitude: serializer.fromJson<double>(json['latitude']),
      longitude: serializer.fromJson<double>(json['longitude']),
      altitude: serializer.fromJson<double?>(json['altitude']),
      speedMps: serializer.fromJson<double?>(json['speedMps']),
      heartRate: serializer.fromJson<int?>(json['heartRate']),
      cadenceRpm: serializer.fromJson<double?>(json['cadenceRpm']),
      power: serializer.fromJson<int?>(json['power']),
      speedFromSensor: serializer.fromJson<bool?>(json['speedFromSensor']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'trackId': serializer.toJson<int>(trackId),
      'time': serializer.toJson<DateTime>(time),
      'latitude': serializer.toJson<double>(latitude),
      'longitude': serializer.toJson<double>(longitude),
      'altitude': serializer.toJson<double?>(altitude),
      'speedMps': serializer.toJson<double?>(speedMps),
      'heartRate': serializer.toJson<int?>(heartRate),
      'cadenceRpm': serializer.toJson<double?>(cadenceRpm),
      'power': serializer.toJson<int?>(power),
      'speedFromSensor': serializer.toJson<bool?>(speedFromSensor),
    };
  }

  TrackPoint copyWith({
    int? id,
    int? trackId,
    DateTime? time,
    double? latitude,
    double? longitude,
    Value<double?> altitude = const Value.absent(),
    Value<double?> speedMps = const Value.absent(),
    Value<int?> heartRate = const Value.absent(),
    Value<double?> cadenceRpm = const Value.absent(),
    Value<int?> power = const Value.absent(),
    Value<bool?> speedFromSensor = const Value.absent(),
  }) => TrackPoint(
    id: id ?? this.id,
    trackId: trackId ?? this.trackId,
    time: time ?? this.time,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    altitude: altitude.present ? altitude.value : this.altitude,
    speedMps: speedMps.present ? speedMps.value : this.speedMps,
    heartRate: heartRate.present ? heartRate.value : this.heartRate,
    cadenceRpm: cadenceRpm.present ? cadenceRpm.value : this.cadenceRpm,
    power: power.present ? power.value : this.power,
    speedFromSensor: speedFromSensor.present
        ? speedFromSensor.value
        : this.speedFromSensor,
  );
  TrackPoint copyWithCompanion(TrackPointsCompanion data) {
    return TrackPoint(
      id: data.id.present ? data.id.value : this.id,
      trackId: data.trackId.present ? data.trackId.value : this.trackId,
      time: data.time.present ? data.time.value : this.time,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
      altitude: data.altitude.present ? data.altitude.value : this.altitude,
      speedMps: data.speedMps.present ? data.speedMps.value : this.speedMps,
      heartRate: data.heartRate.present ? data.heartRate.value : this.heartRate,
      cadenceRpm: data.cadenceRpm.present
          ? data.cadenceRpm.value
          : this.cadenceRpm,
      power: data.power.present ? data.power.value : this.power,
      speedFromSensor: data.speedFromSensor.present
          ? data.speedFromSensor.value
          : this.speedFromSensor,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TrackPoint(')
          ..write('id: $id, ')
          ..write('trackId: $trackId, ')
          ..write('time: $time, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('altitude: $altitude, ')
          ..write('speedMps: $speedMps, ')
          ..write('heartRate: $heartRate, ')
          ..write('cadenceRpm: $cadenceRpm, ')
          ..write('power: $power, ')
          ..write('speedFromSensor: $speedFromSensor')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    trackId,
    time,
    latitude,
    longitude,
    altitude,
    speedMps,
    heartRate,
    cadenceRpm,
    power,
    speedFromSensor,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TrackPoint &&
          other.id == this.id &&
          other.trackId == this.trackId &&
          other.time == this.time &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.altitude == this.altitude &&
          other.speedMps == this.speedMps &&
          other.heartRate == this.heartRate &&
          other.cadenceRpm == this.cadenceRpm &&
          other.power == this.power &&
          other.speedFromSensor == this.speedFromSensor);
}

class TrackPointsCompanion extends UpdateCompanion<TrackPoint> {
  final Value<int> id;
  final Value<int> trackId;
  final Value<DateTime> time;
  final Value<double> latitude;
  final Value<double> longitude;
  final Value<double?> altitude;
  final Value<double?> speedMps;
  final Value<int?> heartRate;
  final Value<double?> cadenceRpm;
  final Value<int?> power;
  final Value<bool?> speedFromSensor;
  const TrackPointsCompanion({
    this.id = const Value.absent(),
    this.trackId = const Value.absent(),
    this.time = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.altitude = const Value.absent(),
    this.speedMps = const Value.absent(),
    this.heartRate = const Value.absent(),
    this.cadenceRpm = const Value.absent(),
    this.power = const Value.absent(),
    this.speedFromSensor = const Value.absent(),
  });
  TrackPointsCompanion.insert({
    this.id = const Value.absent(),
    required int trackId,
    required DateTime time,
    required double latitude,
    required double longitude,
    this.altitude = const Value.absent(),
    this.speedMps = const Value.absent(),
    this.heartRate = const Value.absent(),
    this.cadenceRpm = const Value.absent(),
    this.power = const Value.absent(),
    this.speedFromSensor = const Value.absent(),
  }) : trackId = Value(trackId),
       time = Value(time),
       latitude = Value(latitude),
       longitude = Value(longitude);
  static Insertable<TrackPoint> custom({
    Expression<int>? id,
    Expression<int>? trackId,
    Expression<DateTime>? time,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<double>? altitude,
    Expression<double>? speedMps,
    Expression<int>? heartRate,
    Expression<double>? cadenceRpm,
    Expression<int>? power,
    Expression<bool>? speedFromSensor,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (trackId != null) 'track_id': trackId,
      if (time != null) 'time': time,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (altitude != null) 'altitude': altitude,
      if (speedMps != null) 'speed_mps': speedMps,
      if (heartRate != null) 'heart_rate': heartRate,
      if (cadenceRpm != null) 'cadence_rpm': cadenceRpm,
      if (power != null) 'power': power,
      if (speedFromSensor != null) 'speed_from_sensor': speedFromSensor,
    });
  }

  TrackPointsCompanion copyWith({
    Value<int>? id,
    Value<int>? trackId,
    Value<DateTime>? time,
    Value<double>? latitude,
    Value<double>? longitude,
    Value<double?>? altitude,
    Value<double?>? speedMps,
    Value<int?>? heartRate,
    Value<double?>? cadenceRpm,
    Value<int?>? power,
    Value<bool?>? speedFromSensor,
  }) {
    return TrackPointsCompanion(
      id: id ?? this.id,
      trackId: trackId ?? this.trackId,
      time: time ?? this.time,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      altitude: altitude ?? this.altitude,
      speedMps: speedMps ?? this.speedMps,
      heartRate: heartRate ?? this.heartRate,
      cadenceRpm: cadenceRpm ?? this.cadenceRpm,
      power: power ?? this.power,
      speedFromSensor: speedFromSensor ?? this.speedFromSensor,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (trackId.present) {
      map['track_id'] = Variable<int>(trackId.value);
    }
    if (time.present) {
      map['time'] = Variable<DateTime>(time.value);
    }
    if (latitude.present) {
      map['latitude'] = Variable<double>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<double>(longitude.value);
    }
    if (altitude.present) {
      map['altitude'] = Variable<double>(altitude.value);
    }
    if (speedMps.present) {
      map['speed_mps'] = Variable<double>(speedMps.value);
    }
    if (heartRate.present) {
      map['heart_rate'] = Variable<int>(heartRate.value);
    }
    if (cadenceRpm.present) {
      map['cadence_rpm'] = Variable<double>(cadenceRpm.value);
    }
    if (power.present) {
      map['power'] = Variable<int>(power.value);
    }
    if (speedFromSensor.present) {
      map['speed_from_sensor'] = Variable<bool>(speedFromSensor.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TrackPointsCompanion(')
          ..write('id: $id, ')
          ..write('trackId: $trackId, ')
          ..write('time: $time, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('altitude: $altitude, ')
          ..write('speedMps: $speedMps, ')
          ..write('heartRate: $heartRate, ')
          ..write('cadenceRpm: $cadenceRpm, ')
          ..write('power: $power, ')
          ..write('speedFromSensor: $speedFromSensor')
          ..write(')'))
        .toString();
  }
}

class $SyncRemoteFilesTable extends SyncRemoteFiles
    with TableInfo<$SyncRemoteFilesTable, SyncRemoteFile> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncRemoteFilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _etagMeta = const VerificationMeta('etag');
  @override
  late final GeneratedColumn<String> etag = GeneratedColumn<String>(
    'etag',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _metaMeta = const VerificationMeta('meta');
  @override
  late final GeneratedColumn<String> meta = GeneratedColumn<String>(
    'meta',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [path, etag, meta];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_remote_files';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncRemoteFile> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('etag')) {
      context.handle(
        _etagMeta,
        etag.isAcceptableOrUnknown(data['etag']!, _etagMeta),
      );
    }
    if (data.containsKey('meta')) {
      context.handle(
        _metaMeta,
        meta.isAcceptableOrUnknown(data['meta']!, _metaMeta),
      );
    } else if (isInserting) {
      context.missing(_metaMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {path};
  @override
  SyncRemoteFile map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncRemoteFile(
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      etag: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}etag'],
      ),
      meta: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}meta'],
      )!,
    );
  }

  @override
  $SyncRemoteFilesTable createAlias(String alias) {
    return $SyncRemoteFilesTable(attachedDatabase, alias);
  }
}

class SyncRemoteFile extends DataClass implements Insertable<SyncRemoteFile> {
  final String path;
  final String? etag;
  final String meta;
  const SyncRemoteFile({required this.path, this.etag, required this.meta});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['path'] = Variable<String>(path);
    if (!nullToAbsent || etag != null) {
      map['etag'] = Variable<String>(etag);
    }
    map['meta'] = Variable<String>(meta);
    return map;
  }

  SyncRemoteFilesCompanion toCompanion(bool nullToAbsent) {
    return SyncRemoteFilesCompanion(
      path: Value(path),
      etag: etag == null && nullToAbsent ? const Value.absent() : Value(etag),
      meta: Value(meta),
    );
  }

  factory SyncRemoteFile.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncRemoteFile(
      path: serializer.fromJson<String>(json['path']),
      etag: serializer.fromJson<String?>(json['etag']),
      meta: serializer.fromJson<String>(json['meta']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'path': serializer.toJson<String>(path),
      'etag': serializer.toJson<String?>(etag),
      'meta': serializer.toJson<String>(meta),
    };
  }

  SyncRemoteFile copyWith({
    String? path,
    Value<String?> etag = const Value.absent(),
    String? meta,
  }) => SyncRemoteFile(
    path: path ?? this.path,
    etag: etag.present ? etag.value : this.etag,
    meta: meta ?? this.meta,
  );
  SyncRemoteFile copyWithCompanion(SyncRemoteFilesCompanion data) {
    return SyncRemoteFile(
      path: data.path.present ? data.path.value : this.path,
      etag: data.etag.present ? data.etag.value : this.etag,
      meta: data.meta.present ? data.meta.value : this.meta,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncRemoteFile(')
          ..write('path: $path, ')
          ..write('etag: $etag, ')
          ..write('meta: $meta')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(path, etag, meta);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncRemoteFile &&
          other.path == this.path &&
          other.etag == this.etag &&
          other.meta == this.meta);
}

class SyncRemoteFilesCompanion extends UpdateCompanion<SyncRemoteFile> {
  final Value<String> path;
  final Value<String?> etag;
  final Value<String> meta;
  final Value<int> rowid;
  const SyncRemoteFilesCompanion({
    this.path = const Value.absent(),
    this.etag = const Value.absent(),
    this.meta = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncRemoteFilesCompanion.insert({
    required String path,
    this.etag = const Value.absent(),
    required String meta,
    this.rowid = const Value.absent(),
  }) : path = Value(path),
       meta = Value(meta);
  static Insertable<SyncRemoteFile> custom({
    Expression<String>? path,
    Expression<String>? etag,
    Expression<String>? meta,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (path != null) 'path': path,
      if (etag != null) 'etag': etag,
      if (meta != null) 'meta': meta,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncRemoteFilesCompanion copyWith({
    Value<String>? path,
    Value<String?>? etag,
    Value<String>? meta,
    Value<int>? rowid,
  }) {
    return SyncRemoteFilesCompanion(
      path: path ?? this.path,
      etag: etag ?? this.etag,
      meta: meta ?? this.meta,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (etag.present) {
      map['etag'] = Variable<String>(etag.value);
    }
    if (meta.present) {
      map['meta'] = Variable<String>(meta.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncRemoteFilesCompanion(')
          ..write('path: $path, ')
          ..write('etag: $etag, ')
          ..write('meta: $meta, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncMetaTable extends SyncMeta
    with TableInfo<$SyncMetaTable, SyncMetaData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncMetaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_meta';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncMetaData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SyncMetaData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncMetaData(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $SyncMetaTable createAlias(String alias) {
    return $SyncMetaTable(attachedDatabase, alias);
  }
}

class SyncMetaData extends DataClass implements Insertable<SyncMetaData> {
  final String key;
  final String value;
  const SyncMetaData({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SyncMetaCompanion toCompanion(bool nullToAbsent) {
    return SyncMetaCompanion(key: Value(key), value: Value(value));
  }

  factory SyncMetaData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncMetaData(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  SyncMetaData copyWith({String? key, String? value}) =>
      SyncMetaData(key: key ?? this.key, value: value ?? this.value);
  SyncMetaData copyWithCompanion(SyncMetaCompanion data) {
    return SyncMetaData(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncMetaData(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncMetaData &&
          other.key == this.key &&
          other.value == this.value);
}

class SyncMetaCompanion extends UpdateCompanion<SyncMetaData> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SyncMetaCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncMetaCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<SyncMetaData> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncMetaCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SyncMetaCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncMetaCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $TracksTable tracks = $TracksTable(this);
  late final $TrackPointsTable trackPoints = $TrackPointsTable(this);
  late final $SyncRemoteFilesTable syncRemoteFiles = $SyncRemoteFilesTable(
    this,
  );
  late final $SyncMetaTable syncMeta = $SyncMetaTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    tracks,
    trackPoints,
    syncRemoteFiles,
    syncMeta,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'tracks',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('track_points', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$TracksTableCreateCompanionBuilder =
    TracksCompanion Function({
      Value<int> id,
      Value<String> name,
      required DateTime startedAt,
      Value<DateTime?> endedAt,
      Value<double> distanceMeters,
      Value<int> durationSeconds,
      Value<double> avgSpeedMps,
      Value<double> maxSpeedMps,
      Value<int?> batteryStartPercent,
      Value<int?> batteryEndPercent,
      Value<String?> bikeProfileId,
      Value<String?> nameClock,
      Value<String?> bikeClock,
      Value<String?> geometryClock,
      Value<String?> deletedClock,
      Value<DateTime?> deletedAt,
      Value<bool> pointsPurged,
    });
typedef $$TracksTableUpdateCompanionBuilder =
    TracksCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<DateTime> startedAt,
      Value<DateTime?> endedAt,
      Value<double> distanceMeters,
      Value<int> durationSeconds,
      Value<double> avgSpeedMps,
      Value<double> maxSpeedMps,
      Value<int?> batteryStartPercent,
      Value<int?> batteryEndPercent,
      Value<String?> bikeProfileId,
      Value<String?> nameClock,
      Value<String?> bikeClock,
      Value<String?> geometryClock,
      Value<String?> deletedClock,
      Value<DateTime?> deletedAt,
      Value<bool> pointsPurged,
    });

final class $$TracksTableReferences
    extends BaseReferences<_$AppDatabase, $TracksTable, Track> {
  $$TracksTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$TrackPointsTable, List<TrackPoint>>
  _trackPointsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.trackPoints,
    aliasName: $_aliasNameGenerator(db.tracks.id, db.trackPoints.trackId),
  );

  $$TrackPointsTableProcessedTableManager get trackPointsRefs {
    final manager = $$TrackPointsTableTableManager(
      $_db,
      $_db.trackPoints,
    ).filter((f) => f.trackId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_trackPointsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$TracksTableFilterComposer
    extends Composer<_$AppDatabase, $TracksTable> {
  $$TracksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get endedAt => $composableBuilder(
    column: $table.endedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get distanceMeters => $composableBuilder(
    column: $table.distanceMeters,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get avgSpeedMps => $composableBuilder(
    column: $table.avgSpeedMps,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get maxSpeedMps => $composableBuilder(
    column: $table.maxSpeedMps,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get batteryStartPercent => $composableBuilder(
    column: $table.batteryStartPercent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get batteryEndPercent => $composableBuilder(
    column: $table.batteryEndPercent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bikeProfileId => $composableBuilder(
    column: $table.bikeProfileId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nameClock => $composableBuilder(
    column: $table.nameClock,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bikeClock => $composableBuilder(
    column: $table.bikeClock,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get geometryClock => $composableBuilder(
    column: $table.geometryClock,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deletedClock => $composableBuilder(
    column: $table.deletedClock,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get pointsPurged => $composableBuilder(
    column: $table.pointsPurged,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> trackPointsRefs(
    Expression<bool> Function($$TrackPointsTableFilterComposer f) f,
  ) {
    final $$TrackPointsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.trackPoints,
      getReferencedColumn: (t) => t.trackId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TrackPointsTableFilterComposer(
            $db: $db,
            $table: $db.trackPoints,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TracksTableOrderingComposer
    extends Composer<_$AppDatabase, $TracksTable> {
  $$TracksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get endedAt => $composableBuilder(
    column: $table.endedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get distanceMeters => $composableBuilder(
    column: $table.distanceMeters,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get avgSpeedMps => $composableBuilder(
    column: $table.avgSpeedMps,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get maxSpeedMps => $composableBuilder(
    column: $table.maxSpeedMps,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get batteryStartPercent => $composableBuilder(
    column: $table.batteryStartPercent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get batteryEndPercent => $composableBuilder(
    column: $table.batteryEndPercent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bikeProfileId => $composableBuilder(
    column: $table.bikeProfileId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nameClock => $composableBuilder(
    column: $table.nameClock,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bikeClock => $composableBuilder(
    column: $table.bikeClock,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get geometryClock => $composableBuilder(
    column: $table.geometryClock,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deletedClock => $composableBuilder(
    column: $table.deletedClock,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get pointsPurged => $composableBuilder(
    column: $table.pointsPurged,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TracksTableAnnotationComposer
    extends Composer<_$AppDatabase, $TracksTable> {
  $$TracksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get endedAt =>
      $composableBuilder(column: $table.endedAt, builder: (column) => column);

  GeneratedColumn<double> get distanceMeters => $composableBuilder(
    column: $table.distanceMeters,
    builder: (column) => column,
  );

  GeneratedColumn<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<double> get avgSpeedMps => $composableBuilder(
    column: $table.avgSpeedMps,
    builder: (column) => column,
  );

  GeneratedColumn<double> get maxSpeedMps => $composableBuilder(
    column: $table.maxSpeedMps,
    builder: (column) => column,
  );

  GeneratedColumn<int> get batteryStartPercent => $composableBuilder(
    column: $table.batteryStartPercent,
    builder: (column) => column,
  );

  GeneratedColumn<int> get batteryEndPercent => $composableBuilder(
    column: $table.batteryEndPercent,
    builder: (column) => column,
  );

  GeneratedColumn<String> get bikeProfileId => $composableBuilder(
    column: $table.bikeProfileId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get nameClock =>
      $composableBuilder(column: $table.nameClock, builder: (column) => column);

  GeneratedColumn<String> get bikeClock =>
      $composableBuilder(column: $table.bikeClock, builder: (column) => column);

  GeneratedColumn<String> get geometryClock => $composableBuilder(
    column: $table.geometryClock,
    builder: (column) => column,
  );

  GeneratedColumn<String> get deletedClock => $composableBuilder(
    column: $table.deletedClock,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<bool> get pointsPurged => $composableBuilder(
    column: $table.pointsPurged,
    builder: (column) => column,
  );

  Expression<T> trackPointsRefs<T extends Object>(
    Expression<T> Function($$TrackPointsTableAnnotationComposer a) f,
  ) {
    final $$TrackPointsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.trackPoints,
      getReferencedColumn: (t) => t.trackId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TrackPointsTableAnnotationComposer(
            $db: $db,
            $table: $db.trackPoints,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TracksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TracksTable,
          Track,
          $$TracksTableFilterComposer,
          $$TracksTableOrderingComposer,
          $$TracksTableAnnotationComposer,
          $$TracksTableCreateCompanionBuilder,
          $$TracksTableUpdateCompanionBuilder,
          (Track, $$TracksTableReferences),
          Track,
          PrefetchHooks Function({bool trackPointsRefs})
        > {
  $$TracksTableTableManager(_$AppDatabase db, $TracksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TracksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TracksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TracksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<DateTime> startedAt = const Value.absent(),
                Value<DateTime?> endedAt = const Value.absent(),
                Value<double> distanceMeters = const Value.absent(),
                Value<int> durationSeconds = const Value.absent(),
                Value<double> avgSpeedMps = const Value.absent(),
                Value<double> maxSpeedMps = const Value.absent(),
                Value<int?> batteryStartPercent = const Value.absent(),
                Value<int?> batteryEndPercent = const Value.absent(),
                Value<String?> bikeProfileId = const Value.absent(),
                Value<String?> nameClock = const Value.absent(),
                Value<String?> bikeClock = const Value.absent(),
                Value<String?> geometryClock = const Value.absent(),
                Value<String?> deletedClock = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<bool> pointsPurged = const Value.absent(),
              }) => TracksCompanion(
                id: id,
                name: name,
                startedAt: startedAt,
                endedAt: endedAt,
                distanceMeters: distanceMeters,
                durationSeconds: durationSeconds,
                avgSpeedMps: avgSpeedMps,
                maxSpeedMps: maxSpeedMps,
                batteryStartPercent: batteryStartPercent,
                batteryEndPercent: batteryEndPercent,
                bikeProfileId: bikeProfileId,
                nameClock: nameClock,
                bikeClock: bikeClock,
                geometryClock: geometryClock,
                deletedClock: deletedClock,
                deletedAt: deletedAt,
                pointsPurged: pointsPurged,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                required DateTime startedAt,
                Value<DateTime?> endedAt = const Value.absent(),
                Value<double> distanceMeters = const Value.absent(),
                Value<int> durationSeconds = const Value.absent(),
                Value<double> avgSpeedMps = const Value.absent(),
                Value<double> maxSpeedMps = const Value.absent(),
                Value<int?> batteryStartPercent = const Value.absent(),
                Value<int?> batteryEndPercent = const Value.absent(),
                Value<String?> bikeProfileId = const Value.absent(),
                Value<String?> nameClock = const Value.absent(),
                Value<String?> bikeClock = const Value.absent(),
                Value<String?> geometryClock = const Value.absent(),
                Value<String?> deletedClock = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<bool> pointsPurged = const Value.absent(),
              }) => TracksCompanion.insert(
                id: id,
                name: name,
                startedAt: startedAt,
                endedAt: endedAt,
                distanceMeters: distanceMeters,
                durationSeconds: durationSeconds,
                avgSpeedMps: avgSpeedMps,
                maxSpeedMps: maxSpeedMps,
                batteryStartPercent: batteryStartPercent,
                batteryEndPercent: batteryEndPercent,
                bikeProfileId: bikeProfileId,
                nameClock: nameClock,
                bikeClock: bikeClock,
                geometryClock: geometryClock,
                deletedClock: deletedClock,
                deletedAt: deletedAt,
                pointsPurged: pointsPurged,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$TracksTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({trackPointsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (trackPointsRefs) db.trackPoints],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (trackPointsRefs)
                    await $_getPrefetchedData<Track, $TracksTable, TrackPoint>(
                      currentTable: table,
                      referencedTable: $$TracksTableReferences
                          ._trackPointsRefsTable(db),
                      managerFromTypedResult: (p0) => $$TracksTableReferences(
                        db,
                        table,
                        p0,
                      ).trackPointsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.trackId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$TracksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TracksTable,
      Track,
      $$TracksTableFilterComposer,
      $$TracksTableOrderingComposer,
      $$TracksTableAnnotationComposer,
      $$TracksTableCreateCompanionBuilder,
      $$TracksTableUpdateCompanionBuilder,
      (Track, $$TracksTableReferences),
      Track,
      PrefetchHooks Function({bool trackPointsRefs})
    >;
typedef $$TrackPointsTableCreateCompanionBuilder =
    TrackPointsCompanion Function({
      Value<int> id,
      required int trackId,
      required DateTime time,
      required double latitude,
      required double longitude,
      Value<double?> altitude,
      Value<double?> speedMps,
      Value<int?> heartRate,
      Value<double?> cadenceRpm,
      Value<int?> power,
      Value<bool?> speedFromSensor,
    });
typedef $$TrackPointsTableUpdateCompanionBuilder =
    TrackPointsCompanion Function({
      Value<int> id,
      Value<int> trackId,
      Value<DateTime> time,
      Value<double> latitude,
      Value<double> longitude,
      Value<double?> altitude,
      Value<double?> speedMps,
      Value<int?> heartRate,
      Value<double?> cadenceRpm,
      Value<int?> power,
      Value<bool?> speedFromSensor,
    });

final class $$TrackPointsTableReferences
    extends BaseReferences<_$AppDatabase, $TrackPointsTable, TrackPoint> {
  $$TrackPointsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $TracksTable _trackIdTable(_$AppDatabase db) => db.tracks.createAlias(
    $_aliasNameGenerator(db.trackPoints.trackId, db.tracks.id),
  );

  $$TracksTableProcessedTableManager get trackId {
    final $_column = $_itemColumn<int>('track_id')!;

    final manager = $$TracksTableTableManager(
      $_db,
      $_db.tracks,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_trackIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$TrackPointsTableFilterComposer
    extends Composer<_$AppDatabase, $TrackPointsTable> {
  $$TrackPointsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get time => $composableBuilder(
    column: $table.time,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get altitude => $composableBuilder(
    column: $table.altitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get speedMps => $composableBuilder(
    column: $table.speedMps,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get heartRate => $composableBuilder(
    column: $table.heartRate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get cadenceRpm => $composableBuilder(
    column: $table.cadenceRpm,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get power => $composableBuilder(
    column: $table.power,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get speedFromSensor => $composableBuilder(
    column: $table.speedFromSensor,
    builder: (column) => ColumnFilters(column),
  );

  $$TracksTableFilterComposer get trackId {
    final $$TracksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.trackId,
      referencedTable: $db.tracks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TracksTableFilterComposer(
            $db: $db,
            $table: $db.tracks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TrackPointsTableOrderingComposer
    extends Composer<_$AppDatabase, $TrackPointsTable> {
  $$TrackPointsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get time => $composableBuilder(
    column: $table.time,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get altitude => $composableBuilder(
    column: $table.altitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get speedMps => $composableBuilder(
    column: $table.speedMps,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get heartRate => $composableBuilder(
    column: $table.heartRate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get cadenceRpm => $composableBuilder(
    column: $table.cadenceRpm,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get power => $composableBuilder(
    column: $table.power,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get speedFromSensor => $composableBuilder(
    column: $table.speedFromSensor,
    builder: (column) => ColumnOrderings(column),
  );

  $$TracksTableOrderingComposer get trackId {
    final $$TracksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.trackId,
      referencedTable: $db.tracks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TracksTableOrderingComposer(
            $db: $db,
            $table: $db.tracks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TrackPointsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TrackPointsTable> {
  $$TrackPointsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get time =>
      $composableBuilder(column: $table.time, builder: (column) => column);

  GeneratedColumn<double> get latitude =>
      $composableBuilder(column: $table.latitude, builder: (column) => column);

  GeneratedColumn<double> get longitude =>
      $composableBuilder(column: $table.longitude, builder: (column) => column);

  GeneratedColumn<double> get altitude =>
      $composableBuilder(column: $table.altitude, builder: (column) => column);

  GeneratedColumn<double> get speedMps =>
      $composableBuilder(column: $table.speedMps, builder: (column) => column);

  GeneratedColumn<int> get heartRate =>
      $composableBuilder(column: $table.heartRate, builder: (column) => column);

  GeneratedColumn<double> get cadenceRpm => $composableBuilder(
    column: $table.cadenceRpm,
    builder: (column) => column,
  );

  GeneratedColumn<int> get power =>
      $composableBuilder(column: $table.power, builder: (column) => column);

  GeneratedColumn<bool> get speedFromSensor => $composableBuilder(
    column: $table.speedFromSensor,
    builder: (column) => column,
  );

  $$TracksTableAnnotationComposer get trackId {
    final $$TracksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.trackId,
      referencedTable: $db.tracks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TracksTableAnnotationComposer(
            $db: $db,
            $table: $db.tracks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TrackPointsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TrackPointsTable,
          TrackPoint,
          $$TrackPointsTableFilterComposer,
          $$TrackPointsTableOrderingComposer,
          $$TrackPointsTableAnnotationComposer,
          $$TrackPointsTableCreateCompanionBuilder,
          $$TrackPointsTableUpdateCompanionBuilder,
          (TrackPoint, $$TrackPointsTableReferences),
          TrackPoint,
          PrefetchHooks Function({bool trackId})
        > {
  $$TrackPointsTableTableManager(_$AppDatabase db, $TrackPointsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TrackPointsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TrackPointsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TrackPointsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> trackId = const Value.absent(),
                Value<DateTime> time = const Value.absent(),
                Value<double> latitude = const Value.absent(),
                Value<double> longitude = const Value.absent(),
                Value<double?> altitude = const Value.absent(),
                Value<double?> speedMps = const Value.absent(),
                Value<int?> heartRate = const Value.absent(),
                Value<double?> cadenceRpm = const Value.absent(),
                Value<int?> power = const Value.absent(),
                Value<bool?> speedFromSensor = const Value.absent(),
              }) => TrackPointsCompanion(
                id: id,
                trackId: trackId,
                time: time,
                latitude: latitude,
                longitude: longitude,
                altitude: altitude,
                speedMps: speedMps,
                heartRate: heartRate,
                cadenceRpm: cadenceRpm,
                power: power,
                speedFromSensor: speedFromSensor,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int trackId,
                required DateTime time,
                required double latitude,
                required double longitude,
                Value<double?> altitude = const Value.absent(),
                Value<double?> speedMps = const Value.absent(),
                Value<int?> heartRate = const Value.absent(),
                Value<double?> cadenceRpm = const Value.absent(),
                Value<int?> power = const Value.absent(),
                Value<bool?> speedFromSensor = const Value.absent(),
              }) => TrackPointsCompanion.insert(
                id: id,
                trackId: trackId,
                time: time,
                latitude: latitude,
                longitude: longitude,
                altitude: altitude,
                speedMps: speedMps,
                heartRate: heartRate,
                cadenceRpm: cadenceRpm,
                power: power,
                speedFromSensor: speedFromSensor,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$TrackPointsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({trackId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (trackId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.trackId,
                                referencedTable: $$TrackPointsTableReferences
                                    ._trackIdTable(db),
                                referencedColumn: $$TrackPointsTableReferences
                                    ._trackIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$TrackPointsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TrackPointsTable,
      TrackPoint,
      $$TrackPointsTableFilterComposer,
      $$TrackPointsTableOrderingComposer,
      $$TrackPointsTableAnnotationComposer,
      $$TrackPointsTableCreateCompanionBuilder,
      $$TrackPointsTableUpdateCompanionBuilder,
      (TrackPoint, $$TrackPointsTableReferences),
      TrackPoint,
      PrefetchHooks Function({bool trackId})
    >;
typedef $$SyncRemoteFilesTableCreateCompanionBuilder =
    SyncRemoteFilesCompanion Function({
      required String path,
      Value<String?> etag,
      required String meta,
      Value<int> rowid,
    });
typedef $$SyncRemoteFilesTableUpdateCompanionBuilder =
    SyncRemoteFilesCompanion Function({
      Value<String> path,
      Value<String?> etag,
      Value<String> meta,
      Value<int> rowid,
    });

class $$SyncRemoteFilesTableFilterComposer
    extends Composer<_$AppDatabase, $SyncRemoteFilesTable> {
  $$SyncRemoteFilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get etag => $composableBuilder(
    column: $table.etag,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get meta => $composableBuilder(
    column: $table.meta,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncRemoteFilesTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncRemoteFilesTable> {
  $$SyncRemoteFilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get etag => $composableBuilder(
    column: $table.etag,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get meta => $composableBuilder(
    column: $table.meta,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncRemoteFilesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncRemoteFilesTable> {
  $$SyncRemoteFilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<String> get etag =>
      $composableBuilder(column: $table.etag, builder: (column) => column);

  GeneratedColumn<String> get meta =>
      $composableBuilder(column: $table.meta, builder: (column) => column);
}

class $$SyncRemoteFilesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncRemoteFilesTable,
          SyncRemoteFile,
          $$SyncRemoteFilesTableFilterComposer,
          $$SyncRemoteFilesTableOrderingComposer,
          $$SyncRemoteFilesTableAnnotationComposer,
          $$SyncRemoteFilesTableCreateCompanionBuilder,
          $$SyncRemoteFilesTableUpdateCompanionBuilder,
          (
            SyncRemoteFile,
            BaseReferences<
              _$AppDatabase,
              $SyncRemoteFilesTable,
              SyncRemoteFile
            >,
          ),
          SyncRemoteFile,
          PrefetchHooks Function()
        > {
  $$SyncRemoteFilesTableTableManager(
    _$AppDatabase db,
    $SyncRemoteFilesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncRemoteFilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncRemoteFilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncRemoteFilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> path = const Value.absent(),
                Value<String?> etag = const Value.absent(),
                Value<String> meta = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncRemoteFilesCompanion(
                path: path,
                etag: etag,
                meta: meta,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String path,
                Value<String?> etag = const Value.absent(),
                required String meta,
                Value<int> rowid = const Value.absent(),
              }) => SyncRemoteFilesCompanion.insert(
                path: path,
                etag: etag,
                meta: meta,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncRemoteFilesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncRemoteFilesTable,
      SyncRemoteFile,
      $$SyncRemoteFilesTableFilterComposer,
      $$SyncRemoteFilesTableOrderingComposer,
      $$SyncRemoteFilesTableAnnotationComposer,
      $$SyncRemoteFilesTableCreateCompanionBuilder,
      $$SyncRemoteFilesTableUpdateCompanionBuilder,
      (
        SyncRemoteFile,
        BaseReferences<_$AppDatabase, $SyncRemoteFilesTable, SyncRemoteFile>,
      ),
      SyncRemoteFile,
      PrefetchHooks Function()
    >;
typedef $$SyncMetaTableCreateCompanionBuilder =
    SyncMetaCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$SyncMetaTableUpdateCompanionBuilder =
    SyncMetaCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$SyncMetaTableFilterComposer
    extends Composer<_$AppDatabase, $SyncMetaTable> {
  $$SyncMetaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncMetaTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncMetaTable> {
  $$SyncMetaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncMetaTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncMetaTable> {
  $$SyncMetaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SyncMetaTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncMetaTable,
          SyncMetaData,
          $$SyncMetaTableFilterComposer,
          $$SyncMetaTableOrderingComposer,
          $$SyncMetaTableAnnotationComposer,
          $$SyncMetaTableCreateCompanionBuilder,
          $$SyncMetaTableUpdateCompanionBuilder,
          (
            SyncMetaData,
            BaseReferences<_$AppDatabase, $SyncMetaTable, SyncMetaData>,
          ),
          SyncMetaData,
          PrefetchHooks Function()
        > {
  $$SyncMetaTableTableManager(_$AppDatabase db, $SyncMetaTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncMetaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncMetaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncMetaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncMetaCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => SyncMetaCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncMetaTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncMetaTable,
      SyncMetaData,
      $$SyncMetaTableFilterComposer,
      $$SyncMetaTableOrderingComposer,
      $$SyncMetaTableAnnotationComposer,
      $$SyncMetaTableCreateCompanionBuilder,
      $$SyncMetaTableUpdateCompanionBuilder,
      (
        SyncMetaData,
        BaseReferences<_$AppDatabase, $SyncMetaTable, SyncMetaData>,
      ),
      SyncMetaData,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$TracksTableTableManager get tracks =>
      $$TracksTableTableManager(_db, _db.tracks);
  $$TrackPointsTableTableManager get trackPoints =>
      $$TrackPointsTableTableManager(_db, _db.trackPoints);
  $$SyncRemoteFilesTableTableManager get syncRemoteFiles =>
      $$SyncRemoteFilesTableTableManager(_db, _db.syncRemoteFiles);
  $$SyncMetaTableTableManager get syncMeta =>
      $$SyncMetaTableTableManager(_db, _db.syncMeta);
}
