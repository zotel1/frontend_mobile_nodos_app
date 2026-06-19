// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $UsersTable extends Users with TableInfo<$UsersTable, User> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UsersTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _uuidMeta = const VerificationMeta('uuid');
  @override
  late final GeneratedColumn<String> uuid = GeneratedColumn<String>(
    'uuid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<String> color = GeneratedColumn<String>(
    'color',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceTypeMeta = const VerificationMeta(
    'deviceType',
  );
  @override
  late final GeneratedColumn<String> deviceType = GeneratedColumn<String>(
    'device_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    uuid,
    name,
    color,
    deviceType,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'users';
  @override
  VerificationContext validateIntegrity(
    Insertable<User> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('uuid')) {
      context.handle(
        _uuidMeta,
        uuid.isAcceptableOrUnknown(data['uuid']!, _uuidMeta),
      );
    } else if (isInserting) {
      context.missing(_uuidMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    } else if (isInserting) {
      context.missing(_colorMeta);
    }
    if (data.containsKey('device_type')) {
      context.handle(
        _deviceTypeMeta,
        deviceType.isAcceptableOrUnknown(data['device_type']!, _deviceTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceTypeMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  User map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return User(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      uuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}uuid'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      color: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color'],
      )!,
      deviceType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_type'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $UsersTable createAlias(String alias) {
    return $UsersTable(attachedDatabase, alias);
  }
}

class User extends DataClass implements Insertable<User> {
  final int id;
  final String uuid;
  final String name;
  final String color;
  final String deviceType;
  final DateTime createdAt;
  const User({
    required this.id,
    required this.uuid,
    required this.name,
    required this.color,
    required this.deviceType,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['uuid'] = Variable<String>(uuid);
    map['name'] = Variable<String>(name);
    map['color'] = Variable<String>(color);
    map['device_type'] = Variable<String>(deviceType);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  UsersCompanion toCompanion(bool nullToAbsent) {
    return UsersCompanion(
      id: Value(id),
      uuid: Value(uuid),
      name: Value(name),
      color: Value(color),
      deviceType: Value(deviceType),
      createdAt: Value(createdAt),
    );
  }

  factory User.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return User(
      id: serializer.fromJson<int>(json['id']),
      uuid: serializer.fromJson<String>(json['uuid']),
      name: serializer.fromJson<String>(json['name']),
      color: serializer.fromJson<String>(json['color']),
      deviceType: serializer.fromJson<String>(json['deviceType']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'uuid': serializer.toJson<String>(uuid),
      'name': serializer.toJson<String>(name),
      'color': serializer.toJson<String>(color),
      'deviceType': serializer.toJson<String>(deviceType),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  User copyWith({
    int? id,
    String? uuid,
    String? name,
    String? color,
    String? deviceType,
    DateTime? createdAt,
  }) => User(
    id: id ?? this.id,
    uuid: uuid ?? this.uuid,
    name: name ?? this.name,
    color: color ?? this.color,
    deviceType: deviceType ?? this.deviceType,
    createdAt: createdAt ?? this.createdAt,
  );
  User copyWithCompanion(UsersCompanion data) {
    return User(
      id: data.id.present ? data.id.value : this.id,
      uuid: data.uuid.present ? data.uuid.value : this.uuid,
      name: data.name.present ? data.name.value : this.name,
      color: data.color.present ? data.color.value : this.color,
      deviceType: data.deviceType.present
          ? data.deviceType.value
          : this.deviceType,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('User(')
          ..write('id: $id, ')
          ..write('uuid: $uuid, ')
          ..write('name: $name, ')
          ..write('color: $color, ')
          ..write('deviceType: $deviceType, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, uuid, name, color, deviceType, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is User &&
          other.id == this.id &&
          other.uuid == this.uuid &&
          other.name == this.name &&
          other.color == this.color &&
          other.deviceType == this.deviceType &&
          other.createdAt == this.createdAt);
}

class UsersCompanion extends UpdateCompanion<User> {
  final Value<int> id;
  final Value<String> uuid;
  final Value<String> name;
  final Value<String> color;
  final Value<String> deviceType;
  final Value<DateTime> createdAt;
  const UsersCompanion({
    this.id = const Value.absent(),
    this.uuid = const Value.absent(),
    this.name = const Value.absent(),
    this.color = const Value.absent(),
    this.deviceType = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  UsersCompanion.insert({
    this.id = const Value.absent(),
    required String uuid,
    required String name,
    required String color,
    required String deviceType,
    required DateTime createdAt,
  }) : uuid = Value(uuid),
       name = Value(name),
       color = Value(color),
       deviceType = Value(deviceType),
       createdAt = Value(createdAt);
  static Insertable<User> custom({
    Expression<int>? id,
    Expression<String>? uuid,
    Expression<String>? name,
    Expression<String>? color,
    Expression<String>? deviceType,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (uuid != null) 'uuid': uuid,
      if (name != null) 'name': name,
      if (color != null) 'color': color,
      if (deviceType != null) 'device_type': deviceType,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  UsersCompanion copyWith({
    Value<int>? id,
    Value<String>? uuid,
    Value<String>? name,
    Value<String>? color,
    Value<String>? deviceType,
    Value<DateTime>? createdAt,
  }) {
    return UsersCompanion(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      name: name ?? this.name,
      color: color ?? this.color,
      deviceType: deviceType ?? this.deviceType,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (uuid.present) {
      map['uuid'] = Variable<String>(uuid.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (color.present) {
      map['color'] = Variable<String>(color.value);
    }
    if (deviceType.present) {
      map['device_type'] = Variable<String>(deviceType.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UsersCompanion(')
          ..write('id: $id, ')
          ..write('uuid: $uuid, ')
          ..write('name: $name, ')
          ..write('color: $color, ')
          ..write('deviceType: $deviceType, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $NodesTable extends Nodes with TableInfo<$NodesTable, NodeRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NodesTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _bleAddressMeta = const VerificationMeta(
    'bleAddress',
  );
  @override
  late final GeneratedColumn<String> bleAddress = GeneratedColumn<String>(
    'ble_address',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<String> color = GeneratedColumn<String>(
    'color',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _firstSeenMeta = const VerificationMeta(
    'firstSeen',
  );
  @override
  late final GeneratedColumn<DateTime> firstSeen = GeneratedColumn<DateTime>(
    'first_seen',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastSeenMeta = const VerificationMeta(
    'lastSeen',
  );
  @override
  late final GeneratedColumn<DateTime> lastSeen = GeneratedColumn<DateTime>(
    'last_seen',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastRssiMeta = const VerificationMeta(
    'lastRssi',
  );
  @override
  late final GeneratedColumn<int> lastRssi = GeneratedColumn<int>(
    'last_rssi',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _proximityZoneMeta = const VerificationMeta(
    'proximityZone',
  );
  @override
  late final GeneratedColumn<String> proximityZone = GeneratedColumn<String>(
    'proximity_zone',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rssiHistoryMeta = const VerificationMeta(
    'rssiHistory',
  );
  @override
  late final GeneratedColumn<String> rssiHistory = GeneratedColumn<String>(
    'rssi_history',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    bleAddress,
    name,
    color,
    firstSeen,
    lastSeen,
    lastRssi,
    proximityZone,
    rssiHistory,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'nodes';
  @override
  VerificationContext validateIntegrity(
    Insertable<NodeRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('ble_address')) {
      context.handle(
        _bleAddressMeta,
        bleAddress.isAcceptableOrUnknown(data['ble_address']!, _bleAddressMeta),
      );
    } else if (isInserting) {
      context.missing(_bleAddressMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    }
    if (data.containsKey('first_seen')) {
      context.handle(
        _firstSeenMeta,
        firstSeen.isAcceptableOrUnknown(data['first_seen']!, _firstSeenMeta),
      );
    } else if (isInserting) {
      context.missing(_firstSeenMeta);
    }
    if (data.containsKey('last_seen')) {
      context.handle(
        _lastSeenMeta,
        lastSeen.isAcceptableOrUnknown(data['last_seen']!, _lastSeenMeta),
      );
    } else if (isInserting) {
      context.missing(_lastSeenMeta);
    }
    if (data.containsKey('last_rssi')) {
      context.handle(
        _lastRssiMeta,
        lastRssi.isAcceptableOrUnknown(data['last_rssi']!, _lastRssiMeta),
      );
    }
    if (data.containsKey('proximity_zone')) {
      context.handle(
        _proximityZoneMeta,
        proximityZone.isAcceptableOrUnknown(
          data['proximity_zone']!,
          _proximityZoneMeta,
        ),
      );
    }
    if (data.containsKey('rssi_history')) {
      context.handle(
        _rssiHistoryMeta,
        rssiHistory.isAcceptableOrUnknown(
          data['rssi_history']!,
          _rssiHistoryMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NodeRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NodeRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      bleAddress: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ble_address'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      ),
      color: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color'],
      ),
      firstSeen: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}first_seen'],
      )!,
      lastSeen: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_seen'],
      )!,
      lastRssi: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_rssi'],
      ),
      proximityZone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}proximity_zone'],
      ),
      rssiHistory: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rssi_history'],
      ),
    );
  }

  @override
  $NodesTable createAlias(String alias) {
    return $NodesTable(attachedDatabase, alias);
  }
}

class NodeRow extends DataClass implements Insertable<NodeRow> {
  final int id;
  final String bleAddress;
  final String? name;
  final String? color;
  final DateTime firstSeen;
  final DateTime lastSeen;
  final int? lastRssi;
  final String? proximityZone;
  final String? rssiHistory;
  const NodeRow({
    required this.id,
    required this.bleAddress,
    this.name,
    this.color,
    required this.firstSeen,
    required this.lastSeen,
    this.lastRssi,
    this.proximityZone,
    this.rssiHistory,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['ble_address'] = Variable<String>(bleAddress);
    if (!nullToAbsent || name != null) {
      map['name'] = Variable<String>(name);
    }
    if (!nullToAbsent || color != null) {
      map['color'] = Variable<String>(color);
    }
    map['first_seen'] = Variable<DateTime>(firstSeen);
    map['last_seen'] = Variable<DateTime>(lastSeen);
    if (!nullToAbsent || lastRssi != null) {
      map['last_rssi'] = Variable<int>(lastRssi);
    }
    if (!nullToAbsent || proximityZone != null) {
      map['proximity_zone'] = Variable<String>(proximityZone);
    }
    if (!nullToAbsent || rssiHistory != null) {
      map['rssi_history'] = Variable<String>(rssiHistory);
    }
    return map;
  }

  NodesCompanion toCompanion(bool nullToAbsent) {
    return NodesCompanion(
      id: Value(id),
      bleAddress: Value(bleAddress),
      name: name == null && nullToAbsent ? const Value.absent() : Value(name),
      color: color == null && nullToAbsent
          ? const Value.absent()
          : Value(color),
      firstSeen: Value(firstSeen),
      lastSeen: Value(lastSeen),
      lastRssi: lastRssi == null && nullToAbsent
          ? const Value.absent()
          : Value(lastRssi),
      proximityZone: proximityZone == null && nullToAbsent
          ? const Value.absent()
          : Value(proximityZone),
      rssiHistory: rssiHistory == null && nullToAbsent
          ? const Value.absent()
          : Value(rssiHistory),
    );
  }

  factory NodeRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NodeRow(
      id: serializer.fromJson<int>(json['id']),
      bleAddress: serializer.fromJson<String>(json['bleAddress']),
      name: serializer.fromJson<String?>(json['name']),
      color: serializer.fromJson<String?>(json['color']),
      firstSeen: serializer.fromJson<DateTime>(json['firstSeen']),
      lastSeen: serializer.fromJson<DateTime>(json['lastSeen']),
      lastRssi: serializer.fromJson<int?>(json['lastRssi']),
      proximityZone: serializer.fromJson<String?>(json['proximityZone']),
      rssiHistory: serializer.fromJson<String?>(json['rssiHistory']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'bleAddress': serializer.toJson<String>(bleAddress),
      'name': serializer.toJson<String?>(name),
      'color': serializer.toJson<String?>(color),
      'firstSeen': serializer.toJson<DateTime>(firstSeen),
      'lastSeen': serializer.toJson<DateTime>(lastSeen),
      'lastRssi': serializer.toJson<int?>(lastRssi),
      'proximityZone': serializer.toJson<String?>(proximityZone),
      'rssiHistory': serializer.toJson<String?>(rssiHistory),
    };
  }

  NodeRow copyWith({
    int? id,
    String? bleAddress,
    Value<String?> name = const Value.absent(),
    Value<String?> color = const Value.absent(),
    DateTime? firstSeen,
    DateTime? lastSeen,
    Value<int?> lastRssi = const Value.absent(),
    Value<String?> proximityZone = const Value.absent(),
    Value<String?> rssiHistory = const Value.absent(),
  }) => NodeRow(
    id: id ?? this.id,
    bleAddress: bleAddress ?? this.bleAddress,
    name: name.present ? name.value : this.name,
    color: color.present ? color.value : this.color,
    firstSeen: firstSeen ?? this.firstSeen,
    lastSeen: lastSeen ?? this.lastSeen,
    lastRssi: lastRssi.present ? lastRssi.value : this.lastRssi,
    proximityZone: proximityZone.present
        ? proximityZone.value
        : this.proximityZone,
    rssiHistory: rssiHistory.present ? rssiHistory.value : this.rssiHistory,
  );
  NodeRow copyWithCompanion(NodesCompanion data) {
    return NodeRow(
      id: data.id.present ? data.id.value : this.id,
      bleAddress: data.bleAddress.present
          ? data.bleAddress.value
          : this.bleAddress,
      name: data.name.present ? data.name.value : this.name,
      color: data.color.present ? data.color.value : this.color,
      firstSeen: data.firstSeen.present ? data.firstSeen.value : this.firstSeen,
      lastSeen: data.lastSeen.present ? data.lastSeen.value : this.lastSeen,
      lastRssi: data.lastRssi.present ? data.lastRssi.value : this.lastRssi,
      proximityZone: data.proximityZone.present
          ? data.proximityZone.value
          : this.proximityZone,
      rssiHistory: data.rssiHistory.present
          ? data.rssiHistory.value
          : this.rssiHistory,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NodeRow(')
          ..write('id: $id, ')
          ..write('bleAddress: $bleAddress, ')
          ..write('name: $name, ')
          ..write('color: $color, ')
          ..write('firstSeen: $firstSeen, ')
          ..write('lastSeen: $lastSeen, ')
          ..write('lastRssi: $lastRssi, ')
          ..write('proximityZone: $proximityZone, ')
          ..write('rssiHistory: $rssiHistory')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    bleAddress,
    name,
    color,
    firstSeen,
    lastSeen,
    lastRssi,
    proximityZone,
    rssiHistory,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NodeRow &&
          other.id == this.id &&
          other.bleAddress == this.bleAddress &&
          other.name == this.name &&
          other.color == this.color &&
          other.firstSeen == this.firstSeen &&
          other.lastSeen == this.lastSeen &&
          other.lastRssi == this.lastRssi &&
          other.proximityZone == this.proximityZone &&
          other.rssiHistory == this.rssiHistory);
}

class NodesCompanion extends UpdateCompanion<NodeRow> {
  final Value<int> id;
  final Value<String> bleAddress;
  final Value<String?> name;
  final Value<String?> color;
  final Value<DateTime> firstSeen;
  final Value<DateTime> lastSeen;
  final Value<int?> lastRssi;
  final Value<String?> proximityZone;
  final Value<String?> rssiHistory;
  const NodesCompanion({
    this.id = const Value.absent(),
    this.bleAddress = const Value.absent(),
    this.name = const Value.absent(),
    this.color = const Value.absent(),
    this.firstSeen = const Value.absent(),
    this.lastSeen = const Value.absent(),
    this.lastRssi = const Value.absent(),
    this.proximityZone = const Value.absent(),
    this.rssiHistory = const Value.absent(),
  });
  NodesCompanion.insert({
    this.id = const Value.absent(),
    required String bleAddress,
    this.name = const Value.absent(),
    this.color = const Value.absent(),
    required DateTime firstSeen,
    required DateTime lastSeen,
    this.lastRssi = const Value.absent(),
    this.proximityZone = const Value.absent(),
    this.rssiHistory = const Value.absent(),
  }) : bleAddress = Value(bleAddress),
       firstSeen = Value(firstSeen),
       lastSeen = Value(lastSeen);
  static Insertable<NodeRow> custom({
    Expression<int>? id,
    Expression<String>? bleAddress,
    Expression<String>? name,
    Expression<String>? color,
    Expression<DateTime>? firstSeen,
    Expression<DateTime>? lastSeen,
    Expression<int>? lastRssi,
    Expression<String>? proximityZone,
    Expression<String>? rssiHistory,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (bleAddress != null) 'ble_address': bleAddress,
      if (name != null) 'name': name,
      if (color != null) 'color': color,
      if (firstSeen != null) 'first_seen': firstSeen,
      if (lastSeen != null) 'last_seen': lastSeen,
      if (lastRssi != null) 'last_rssi': lastRssi,
      if (proximityZone != null) 'proximity_zone': proximityZone,
      if (rssiHistory != null) 'rssi_history': rssiHistory,
    });
  }

  NodesCompanion copyWith({
    Value<int>? id,
    Value<String>? bleAddress,
    Value<String?>? name,
    Value<String?>? color,
    Value<DateTime>? firstSeen,
    Value<DateTime>? lastSeen,
    Value<int?>? lastRssi,
    Value<String?>? proximityZone,
    Value<String?>? rssiHistory,
  }) {
    return NodesCompanion(
      id: id ?? this.id,
      bleAddress: bleAddress ?? this.bleAddress,
      name: name ?? this.name,
      color: color ?? this.color,
      firstSeen: firstSeen ?? this.firstSeen,
      lastSeen: lastSeen ?? this.lastSeen,
      lastRssi: lastRssi ?? this.lastRssi,
      proximityZone: proximityZone ?? this.proximityZone,
      rssiHistory: rssiHistory ?? this.rssiHistory,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (bleAddress.present) {
      map['ble_address'] = Variable<String>(bleAddress.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (color.present) {
      map['color'] = Variable<String>(color.value);
    }
    if (firstSeen.present) {
      map['first_seen'] = Variable<DateTime>(firstSeen.value);
    }
    if (lastSeen.present) {
      map['last_seen'] = Variable<DateTime>(lastSeen.value);
    }
    if (lastRssi.present) {
      map['last_rssi'] = Variable<int>(lastRssi.value);
    }
    if (proximityZone.present) {
      map['proximity_zone'] = Variable<String>(proximityZone.value);
    }
    if (rssiHistory.present) {
      map['rssi_history'] = Variable<String>(rssiHistory.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NodesCompanion(')
          ..write('id: $id, ')
          ..write('bleAddress: $bleAddress, ')
          ..write('name: $name, ')
          ..write('color: $color, ')
          ..write('firstSeen: $firstSeen, ')
          ..write('lastSeen: $lastSeen, ')
          ..write('lastRssi: $lastRssi, ')
          ..write('proximityZone: $proximityZone, ')
          ..write('rssiHistory: $rssiHistory')
          ..write(')'))
        .toString();
  }
}

class $ScanSessionsTable extends ScanSessions
    with TableInfo<$ScanSessionsTable, ScanSession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ScanSessionsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _nodesDetectedMeta = const VerificationMeta(
    'nodesDetected',
  );
  @override
  late final GeneratedColumn<int> nodesDetected = GeneratedColumn<int>(
    'nodes_detected',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, startedAt, endedAt, nodesDetected];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'scan_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<ScanSession> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
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
    if (data.containsKey('nodes_detected')) {
      context.handle(
        _nodesDetectedMeta,
        nodesDetected.isAcceptableOrUnknown(
          data['nodes_detected']!,
          _nodesDetectedMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_nodesDetectedMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ScanSession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ScanSession(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}started_at'],
      )!,
      endedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}ended_at'],
      ),
      nodesDetected: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}nodes_detected'],
      )!,
    );
  }

  @override
  $ScanSessionsTable createAlias(String alias) {
    return $ScanSessionsTable(attachedDatabase, alias);
  }
}

class ScanSession extends DataClass implements Insertable<ScanSession> {
  final int id;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int nodesDetected;
  const ScanSession({
    required this.id,
    required this.startedAt,
    this.endedAt,
    required this.nodesDetected,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['started_at'] = Variable<DateTime>(startedAt);
    if (!nullToAbsent || endedAt != null) {
      map['ended_at'] = Variable<DateTime>(endedAt);
    }
    map['nodes_detected'] = Variable<int>(nodesDetected);
    return map;
  }

  ScanSessionsCompanion toCompanion(bool nullToAbsent) {
    return ScanSessionsCompanion(
      id: Value(id),
      startedAt: Value(startedAt),
      endedAt: endedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(endedAt),
      nodesDetected: Value(nodesDetected),
    );
  }

  factory ScanSession.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ScanSession(
      id: serializer.fromJson<int>(json['id']),
      startedAt: serializer.fromJson<DateTime>(json['startedAt']),
      endedAt: serializer.fromJson<DateTime?>(json['endedAt']),
      nodesDetected: serializer.fromJson<int>(json['nodesDetected']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'startedAt': serializer.toJson<DateTime>(startedAt),
      'endedAt': serializer.toJson<DateTime?>(endedAt),
      'nodesDetected': serializer.toJson<int>(nodesDetected),
    };
  }

  ScanSession copyWith({
    int? id,
    DateTime? startedAt,
    Value<DateTime?> endedAt = const Value.absent(),
    int? nodesDetected,
  }) => ScanSession(
    id: id ?? this.id,
    startedAt: startedAt ?? this.startedAt,
    endedAt: endedAt.present ? endedAt.value : this.endedAt,
    nodesDetected: nodesDetected ?? this.nodesDetected,
  );
  ScanSession copyWithCompanion(ScanSessionsCompanion data) {
    return ScanSession(
      id: data.id.present ? data.id.value : this.id,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      endedAt: data.endedAt.present ? data.endedAt.value : this.endedAt,
      nodesDetected: data.nodesDetected.present
          ? data.nodesDetected.value
          : this.nodesDetected,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ScanSession(')
          ..write('id: $id, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('nodesDetected: $nodesDetected')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, startedAt, endedAt, nodesDetected);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScanSession &&
          other.id == this.id &&
          other.startedAt == this.startedAt &&
          other.endedAt == this.endedAt &&
          other.nodesDetected == this.nodesDetected);
}

class ScanSessionsCompanion extends UpdateCompanion<ScanSession> {
  final Value<int> id;
  final Value<DateTime> startedAt;
  final Value<DateTime?> endedAt;
  final Value<int> nodesDetected;
  const ScanSessionsCompanion({
    this.id = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.endedAt = const Value.absent(),
    this.nodesDetected = const Value.absent(),
  });
  ScanSessionsCompanion.insert({
    this.id = const Value.absent(),
    required DateTime startedAt,
    this.endedAt = const Value.absent(),
    required int nodesDetected,
  }) : startedAt = Value(startedAt),
       nodesDetected = Value(nodesDetected);
  static Insertable<ScanSession> custom({
    Expression<int>? id,
    Expression<DateTime>? startedAt,
    Expression<DateTime>? endedAt,
    Expression<int>? nodesDetected,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (startedAt != null) 'started_at': startedAt,
      if (endedAt != null) 'ended_at': endedAt,
      if (nodesDetected != null) 'nodes_detected': nodesDetected,
    });
  }

  ScanSessionsCompanion copyWith({
    Value<int>? id,
    Value<DateTime>? startedAt,
    Value<DateTime?>? endedAt,
    Value<int>? nodesDetected,
  }) {
    return ScanSessionsCompanion(
      id: id ?? this.id,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      nodesDetected: nodesDetected ?? this.nodesDetected,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    if (endedAt.present) {
      map['ended_at'] = Variable<DateTime>(endedAt.value);
    }
    if (nodesDetected.present) {
      map['nodes_detected'] = Variable<int>(nodesDetected.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ScanSessionsCompanion(')
          ..write('id: $id, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('nodesDetected: $nodesDetected')
          ..write(')'))
        .toString();
  }
}

class $ScanSessionNodesTable extends ScanSessionNodes
    with TableInfo<$ScanSessionNodesTable, ScanSessionNode> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ScanSessionNodesTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<int> sessionId = GeneratedColumn<int>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES scan_sessions (id)',
    ),
  );
  static const VerificationMeta _nodeIdMeta = const VerificationMeta('nodeId');
  @override
  late final GeneratedColumn<int> nodeId = GeneratedColumn<int>(
    'node_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES nodes (id)',
    ),
  );
  static const VerificationMeta _rssiMeta = const VerificationMeta('rssi');
  @override
  late final GeneratedColumn<int> rssi = GeneratedColumn<int>(
    'rssi',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, sessionId, nodeId, rssi];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'scan_session_nodes';
  @override
  VerificationContext validateIntegrity(
    Insertable<ScanSessionNode> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('node_id')) {
      context.handle(
        _nodeIdMeta,
        nodeId.isAcceptableOrUnknown(data['node_id']!, _nodeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_nodeIdMeta);
    }
    if (data.containsKey('rssi')) {
      context.handle(
        _rssiMeta,
        rssi.isAcceptableOrUnknown(data['rssi']!, _rssiMeta),
      );
    } else if (isInserting) {
      context.missing(_rssiMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ScanSessionNode map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ScanSessionNode(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}session_id'],
      )!,
      nodeId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}node_id'],
      )!,
      rssi: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rssi'],
      )!,
    );
  }

  @override
  $ScanSessionNodesTable createAlias(String alias) {
    return $ScanSessionNodesTable(attachedDatabase, alias);
  }
}

class ScanSessionNode extends DataClass implements Insertable<ScanSessionNode> {
  final int id;
  final int sessionId;
  final int nodeId;
  final int rssi;
  const ScanSessionNode({
    required this.id,
    required this.sessionId,
    required this.nodeId,
    required this.rssi,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['session_id'] = Variable<int>(sessionId);
    map['node_id'] = Variable<int>(nodeId);
    map['rssi'] = Variable<int>(rssi);
    return map;
  }

  ScanSessionNodesCompanion toCompanion(bool nullToAbsent) {
    return ScanSessionNodesCompanion(
      id: Value(id),
      sessionId: Value(sessionId),
      nodeId: Value(nodeId),
      rssi: Value(rssi),
    );
  }

  factory ScanSessionNode.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ScanSessionNode(
      id: serializer.fromJson<int>(json['id']),
      sessionId: serializer.fromJson<int>(json['sessionId']),
      nodeId: serializer.fromJson<int>(json['nodeId']),
      rssi: serializer.fromJson<int>(json['rssi']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'sessionId': serializer.toJson<int>(sessionId),
      'nodeId': serializer.toJson<int>(nodeId),
      'rssi': serializer.toJson<int>(rssi),
    };
  }

  ScanSessionNode copyWith({int? id, int? sessionId, int? nodeId, int? rssi}) =>
      ScanSessionNode(
        id: id ?? this.id,
        sessionId: sessionId ?? this.sessionId,
        nodeId: nodeId ?? this.nodeId,
        rssi: rssi ?? this.rssi,
      );
  ScanSessionNode copyWithCompanion(ScanSessionNodesCompanion data) {
    return ScanSessionNode(
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      nodeId: data.nodeId.present ? data.nodeId.value : this.nodeId,
      rssi: data.rssi.present ? data.rssi.value : this.rssi,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ScanSessionNode(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('nodeId: $nodeId, ')
          ..write('rssi: $rssi')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, sessionId, nodeId, rssi);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScanSessionNode &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.nodeId == this.nodeId &&
          other.rssi == this.rssi);
}

class ScanSessionNodesCompanion extends UpdateCompanion<ScanSessionNode> {
  final Value<int> id;
  final Value<int> sessionId;
  final Value<int> nodeId;
  final Value<int> rssi;
  const ScanSessionNodesCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.nodeId = const Value.absent(),
    this.rssi = const Value.absent(),
  });
  ScanSessionNodesCompanion.insert({
    this.id = const Value.absent(),
    required int sessionId,
    required int nodeId,
    required int rssi,
  }) : sessionId = Value(sessionId),
       nodeId = Value(nodeId),
       rssi = Value(rssi);
  static Insertable<ScanSessionNode> custom({
    Expression<int>? id,
    Expression<int>? sessionId,
    Expression<int>? nodeId,
    Expression<int>? rssi,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (nodeId != null) 'node_id': nodeId,
      if (rssi != null) 'rssi': rssi,
    });
  }

  ScanSessionNodesCompanion copyWith({
    Value<int>? id,
    Value<int>? sessionId,
    Value<int>? nodeId,
    Value<int>? rssi,
  }) {
    return ScanSessionNodesCompanion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      nodeId: nodeId ?? this.nodeId,
      rssi: rssi ?? this.rssi,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<int>(sessionId.value);
    }
    if (nodeId.present) {
      map['node_id'] = Variable<int>(nodeId.value);
    }
    if (rssi.present) {
      map['rssi'] = Variable<int>(rssi.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ScanSessionNodesCompanion(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('nodeId: $nodeId, ')
          ..write('rssi: $rssi')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $UsersTable users = $UsersTable(this);
  late final $NodesTable nodes = $NodesTable(this);
  late final $ScanSessionsTable scanSessions = $ScanSessionsTable(this);
  late final $ScanSessionNodesTable scanSessionNodes = $ScanSessionNodesTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    users,
    nodes,
    scanSessions,
    scanSessionNodes,
  ];
  @override
  DriftDatabaseOptions get options =>
      const DriftDatabaseOptions(storeDateTimeAsText: true);
}

typedef $$UsersTableCreateCompanionBuilder =
    UsersCompanion Function({
      Value<int> id,
      required String uuid,
      required String name,
      required String color,
      required String deviceType,
      required DateTime createdAt,
    });
typedef $$UsersTableUpdateCompanionBuilder =
    UsersCompanion Function({
      Value<int> id,
      Value<String> uuid,
      Value<String> name,
      Value<String> color,
      Value<String> deviceType,
      Value<DateTime> createdAt,
    });

class $$UsersTableFilterComposer extends Composer<_$AppDatabase, $UsersTable> {
  $$UsersTableFilterComposer({
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

  ColumnFilters<String> get uuid => $composableBuilder(
    column: $table.uuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceType => $composableBuilder(
    column: $table.deviceType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$UsersTableOrderingComposer
    extends Composer<_$AppDatabase, $UsersTable> {
  $$UsersTableOrderingComposer({
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

  ColumnOrderings<String> get uuid => $composableBuilder(
    column: $table.uuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceType => $composableBuilder(
    column: $table.deviceType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$UsersTableAnnotationComposer
    extends Composer<_$AppDatabase, $UsersTable> {
  $$UsersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get uuid =>
      $composableBuilder(column: $table.uuid, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<String> get deviceType => $composableBuilder(
    column: $table.deviceType,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$UsersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $UsersTable,
          User,
          $$UsersTableFilterComposer,
          $$UsersTableOrderingComposer,
          $$UsersTableAnnotationComposer,
          $$UsersTableCreateCompanionBuilder,
          $$UsersTableUpdateCompanionBuilder,
          (User, BaseReferences<_$AppDatabase, $UsersTable, User>),
          User,
          PrefetchHooks Function()
        > {
  $$UsersTableTableManager(_$AppDatabase db, $UsersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UsersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UsersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UsersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> uuid = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> color = const Value.absent(),
                Value<String> deviceType = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => UsersCompanion(
                id: id,
                uuid: uuid,
                name: name,
                color: color,
                deviceType: deviceType,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String uuid,
                required String name,
                required String color,
                required String deviceType,
                required DateTime createdAt,
              }) => UsersCompanion.insert(
                id: id,
                uuid: uuid,
                name: name,
                color: color,
                deviceType: deviceType,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$UsersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $UsersTable,
      User,
      $$UsersTableFilterComposer,
      $$UsersTableOrderingComposer,
      $$UsersTableAnnotationComposer,
      $$UsersTableCreateCompanionBuilder,
      $$UsersTableUpdateCompanionBuilder,
      (User, BaseReferences<_$AppDatabase, $UsersTable, User>),
      User,
      PrefetchHooks Function()
    >;
typedef $$NodesTableCreateCompanionBuilder =
    NodesCompanion Function({
      Value<int> id,
      required String bleAddress,
      Value<String?> name,
      Value<String?> color,
      required DateTime firstSeen,
      required DateTime lastSeen,
      Value<int?> lastRssi,
      Value<String?> proximityZone,
      Value<String?> rssiHistory,
    });
typedef $$NodesTableUpdateCompanionBuilder =
    NodesCompanion Function({
      Value<int> id,
      Value<String> bleAddress,
      Value<String?> name,
      Value<String?> color,
      Value<DateTime> firstSeen,
      Value<DateTime> lastSeen,
      Value<int?> lastRssi,
      Value<String?> proximityZone,
      Value<String?> rssiHistory,
    });

final class $$NodesTableReferences
    extends BaseReferences<_$AppDatabase, $NodesTable, NodeRow> {
  $$NodesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$ScanSessionNodesTable, List<ScanSessionNode>>
  _scanSessionNodesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.scanSessionNodes,
    aliasName: 'nodes__id__scan_session_nodes__node_id',
  );

  $$ScanSessionNodesTableProcessedTableManager get scanSessionNodesRefs {
    final manager = $$ScanSessionNodesTableTableManager(
      $_db,
      $_db.scanSessionNodes,
    ).filter((f) => f.nodeId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _scanSessionNodesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$NodesTableFilterComposer extends Composer<_$AppDatabase, $NodesTable> {
  $$NodesTableFilterComposer({
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

  ColumnFilters<String> get bleAddress => $composableBuilder(
    column: $table.bleAddress,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get firstSeen => $composableBuilder(
    column: $table.firstSeen,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSeen => $composableBuilder(
    column: $table.lastSeen,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastRssi => $composableBuilder(
    column: $table.lastRssi,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get proximityZone => $composableBuilder(
    column: $table.proximityZone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rssiHistory => $composableBuilder(
    column: $table.rssiHistory,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> scanSessionNodesRefs(
    Expression<bool> Function($$ScanSessionNodesTableFilterComposer f) f,
  ) {
    final $$ScanSessionNodesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.scanSessionNodes,
      getReferencedColumn: (t) => t.nodeId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ScanSessionNodesTableFilterComposer(
            $db: $db,
            $table: $db.scanSessionNodes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$NodesTableOrderingComposer
    extends Composer<_$AppDatabase, $NodesTable> {
  $$NodesTableOrderingComposer({
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

  ColumnOrderings<String> get bleAddress => $composableBuilder(
    column: $table.bleAddress,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get firstSeen => $composableBuilder(
    column: $table.firstSeen,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSeen => $composableBuilder(
    column: $table.lastSeen,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastRssi => $composableBuilder(
    column: $table.lastRssi,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get proximityZone => $composableBuilder(
    column: $table.proximityZone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rssiHistory => $composableBuilder(
    column: $table.rssiHistory,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NodesTableAnnotationComposer
    extends Composer<_$AppDatabase, $NodesTable> {
  $$NodesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get bleAddress => $composableBuilder(
    column: $table.bleAddress,
    builder: (column) => column,
  );

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<DateTime> get firstSeen =>
      $composableBuilder(column: $table.firstSeen, builder: (column) => column);

  GeneratedColumn<DateTime> get lastSeen =>
      $composableBuilder(column: $table.lastSeen, builder: (column) => column);

  GeneratedColumn<int> get lastRssi =>
      $composableBuilder(column: $table.lastRssi, builder: (column) => column);

  GeneratedColumn<String> get proximityZone => $composableBuilder(
    column: $table.proximityZone,
    builder: (column) => column,
  );

  GeneratedColumn<String> get rssiHistory => $composableBuilder(
    column: $table.rssiHistory,
    builder: (column) => column,
  );

  Expression<T> scanSessionNodesRefs<T extends Object>(
    Expression<T> Function($$ScanSessionNodesTableAnnotationComposer a) f,
  ) {
    final $$ScanSessionNodesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.scanSessionNodes,
      getReferencedColumn: (t) => t.nodeId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ScanSessionNodesTableAnnotationComposer(
            $db: $db,
            $table: $db.scanSessionNodes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$NodesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $NodesTable,
          NodeRow,
          $$NodesTableFilterComposer,
          $$NodesTableOrderingComposer,
          $$NodesTableAnnotationComposer,
          $$NodesTableCreateCompanionBuilder,
          $$NodesTableUpdateCompanionBuilder,
          (NodeRow, $$NodesTableReferences),
          NodeRow,
          PrefetchHooks Function({bool scanSessionNodesRefs})
        > {
  $$NodesTableTableManager(_$AppDatabase db, $NodesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NodesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NodesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NodesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> bleAddress = const Value.absent(),
                Value<String?> name = const Value.absent(),
                Value<String?> color = const Value.absent(),
                Value<DateTime> firstSeen = const Value.absent(),
                Value<DateTime> lastSeen = const Value.absent(),
                Value<int?> lastRssi = const Value.absent(),
                Value<String?> proximityZone = const Value.absent(),
                Value<String?> rssiHistory = const Value.absent(),
              }) => NodesCompanion(
                id: id,
                bleAddress: bleAddress,
                name: name,
                color: color,
                firstSeen: firstSeen,
                lastSeen: lastSeen,
                lastRssi: lastRssi,
                proximityZone: proximityZone,
                rssiHistory: rssiHistory,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String bleAddress,
                Value<String?> name = const Value.absent(),
                Value<String?> color = const Value.absent(),
                required DateTime firstSeen,
                required DateTime lastSeen,
                Value<int?> lastRssi = const Value.absent(),
                Value<String?> proximityZone = const Value.absent(),
                Value<String?> rssiHistory = const Value.absent(),
              }) => NodesCompanion.insert(
                id: id,
                bleAddress: bleAddress,
                name: name,
                color: color,
                firstSeen: firstSeen,
                lastSeen: lastSeen,
                lastRssi: lastRssi,
                proximityZone: proximityZone,
                rssiHistory: rssiHistory,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$NodesTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({scanSessionNodesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (scanSessionNodesRefs) db.scanSessionNodes,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (scanSessionNodesRefs)
                    await $_getPrefetchedData<
                      NodeRow,
                      $NodesTable,
                      ScanSessionNode
                    >(
                      currentTable: table,
                      referencedTable: $$NodesTableReferences
                          ._scanSessionNodesRefsTable(db),
                      managerFromTypedResult: (p0) => $$NodesTableReferences(
                        db,
                        table,
                        p0,
                      ).scanSessionNodesRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.nodeId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$NodesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $NodesTable,
      NodeRow,
      $$NodesTableFilterComposer,
      $$NodesTableOrderingComposer,
      $$NodesTableAnnotationComposer,
      $$NodesTableCreateCompanionBuilder,
      $$NodesTableUpdateCompanionBuilder,
      (NodeRow, $$NodesTableReferences),
      NodeRow,
      PrefetchHooks Function({bool scanSessionNodesRefs})
    >;
typedef $$ScanSessionsTableCreateCompanionBuilder =
    ScanSessionsCompanion Function({
      Value<int> id,
      required DateTime startedAt,
      Value<DateTime?> endedAt,
      required int nodesDetected,
    });
typedef $$ScanSessionsTableUpdateCompanionBuilder =
    ScanSessionsCompanion Function({
      Value<int> id,
      Value<DateTime> startedAt,
      Value<DateTime?> endedAt,
      Value<int> nodesDetected,
    });

final class $$ScanSessionsTableReferences
    extends BaseReferences<_$AppDatabase, $ScanSessionsTable, ScanSession> {
  $$ScanSessionsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$ScanSessionNodesTable, List<ScanSessionNode>>
  _scanSessionNodesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.scanSessionNodes,
    aliasName: 'scan_sessions__id__scan_session_nodes__session_id',
  );

  $$ScanSessionNodesTableProcessedTableManager get scanSessionNodesRefs {
    final manager = $$ScanSessionNodesTableTableManager(
      $_db,
      $_db.scanSessionNodes,
    ).filter((f) => f.sessionId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _scanSessionNodesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ScanSessionsTableFilterComposer
    extends Composer<_$AppDatabase, $ScanSessionsTable> {
  $$ScanSessionsTableFilterComposer({
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

  ColumnFilters<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get endedAt => $composableBuilder(
    column: $table.endedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get nodesDetected => $composableBuilder(
    column: $table.nodesDetected,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> scanSessionNodesRefs(
    Expression<bool> Function($$ScanSessionNodesTableFilterComposer f) f,
  ) {
    final $$ScanSessionNodesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.scanSessionNodes,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ScanSessionNodesTableFilterComposer(
            $db: $db,
            $table: $db.scanSessionNodes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ScanSessionsTableOrderingComposer
    extends Composer<_$AppDatabase, $ScanSessionsTable> {
  $$ScanSessionsTableOrderingComposer({
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

  ColumnOrderings<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get endedAt => $composableBuilder(
    column: $table.endedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get nodesDetected => $composableBuilder(
    column: $table.nodesDetected,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ScanSessionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ScanSessionsTable> {
  $$ScanSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get endedAt =>
      $composableBuilder(column: $table.endedAt, builder: (column) => column);

  GeneratedColumn<int> get nodesDetected => $composableBuilder(
    column: $table.nodesDetected,
    builder: (column) => column,
  );

  Expression<T> scanSessionNodesRefs<T extends Object>(
    Expression<T> Function($$ScanSessionNodesTableAnnotationComposer a) f,
  ) {
    final $$ScanSessionNodesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.scanSessionNodes,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ScanSessionNodesTableAnnotationComposer(
            $db: $db,
            $table: $db.scanSessionNodes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ScanSessionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ScanSessionsTable,
          ScanSession,
          $$ScanSessionsTableFilterComposer,
          $$ScanSessionsTableOrderingComposer,
          $$ScanSessionsTableAnnotationComposer,
          $$ScanSessionsTableCreateCompanionBuilder,
          $$ScanSessionsTableUpdateCompanionBuilder,
          (ScanSession, $$ScanSessionsTableReferences),
          ScanSession,
          PrefetchHooks Function({bool scanSessionNodesRefs})
        > {
  $$ScanSessionsTableTableManager(_$AppDatabase db, $ScanSessionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ScanSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ScanSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ScanSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<DateTime> startedAt = const Value.absent(),
                Value<DateTime?> endedAt = const Value.absent(),
                Value<int> nodesDetected = const Value.absent(),
              }) => ScanSessionsCompanion(
                id: id,
                startedAt: startedAt,
                endedAt: endedAt,
                nodesDetected: nodesDetected,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required DateTime startedAt,
                Value<DateTime?> endedAt = const Value.absent(),
                required int nodesDetected,
              }) => ScanSessionsCompanion.insert(
                id: id,
                startedAt: startedAt,
                endedAt: endedAt,
                nodesDetected: nodesDetected,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ScanSessionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({scanSessionNodesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (scanSessionNodesRefs) db.scanSessionNodes,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (scanSessionNodesRefs)
                    await $_getPrefetchedData<
                      ScanSession,
                      $ScanSessionsTable,
                      ScanSessionNode
                    >(
                      currentTable: table,
                      referencedTable: $$ScanSessionsTableReferences
                          ._scanSessionNodesRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$ScanSessionsTableReferences(
                            db,
                            table,
                            p0,
                          ).scanSessionNodesRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.sessionId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$ScanSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ScanSessionsTable,
      ScanSession,
      $$ScanSessionsTableFilterComposer,
      $$ScanSessionsTableOrderingComposer,
      $$ScanSessionsTableAnnotationComposer,
      $$ScanSessionsTableCreateCompanionBuilder,
      $$ScanSessionsTableUpdateCompanionBuilder,
      (ScanSession, $$ScanSessionsTableReferences),
      ScanSession,
      PrefetchHooks Function({bool scanSessionNodesRefs})
    >;
typedef $$ScanSessionNodesTableCreateCompanionBuilder =
    ScanSessionNodesCompanion Function({
      Value<int> id,
      required int sessionId,
      required int nodeId,
      required int rssi,
    });
typedef $$ScanSessionNodesTableUpdateCompanionBuilder =
    ScanSessionNodesCompanion Function({
      Value<int> id,
      Value<int> sessionId,
      Value<int> nodeId,
      Value<int> rssi,
    });

final class $$ScanSessionNodesTableReferences
    extends
        BaseReferences<_$AppDatabase, $ScanSessionNodesTable, ScanSessionNode> {
  $$ScanSessionNodesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ScanSessionsTable _sessionIdTable(_$AppDatabase db) => db.scanSessions
      .createAlias('scan_session_nodes__session_id__scan_sessions__id');

  $$ScanSessionsTableProcessedTableManager get sessionId {
    final $_column = $_itemColumn<int>('session_id')!;

    final manager = $$ScanSessionsTableTableManager(
      $_db,
      $_db.scanSessions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $NodesTable _nodeIdTable(_$AppDatabase db) =>
      db.nodes.createAlias('scan_session_nodes__node_id__nodes__id');

  $$NodesTableProcessedTableManager get nodeId {
    final $_column = $_itemColumn<int>('node_id')!;

    final manager = $$NodesTableTableManager(
      $_db,
      $_db.nodes,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_nodeIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ScanSessionNodesTableFilterComposer
    extends Composer<_$AppDatabase, $ScanSessionNodesTable> {
  $$ScanSessionNodesTableFilterComposer({
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

  ColumnFilters<int> get rssi => $composableBuilder(
    column: $table.rssi,
    builder: (column) => ColumnFilters(column),
  );

  $$ScanSessionsTableFilterComposer get sessionId {
    final $$ScanSessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.scanSessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ScanSessionsTableFilterComposer(
            $db: $db,
            $table: $db.scanSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$NodesTableFilterComposer get nodeId {
    final $$NodesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.nodeId,
      referencedTable: $db.nodes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NodesTableFilterComposer(
            $db: $db,
            $table: $db.nodes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ScanSessionNodesTableOrderingComposer
    extends Composer<_$AppDatabase, $ScanSessionNodesTable> {
  $$ScanSessionNodesTableOrderingComposer({
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

  ColumnOrderings<int> get rssi => $composableBuilder(
    column: $table.rssi,
    builder: (column) => ColumnOrderings(column),
  );

  $$ScanSessionsTableOrderingComposer get sessionId {
    final $$ScanSessionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.scanSessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ScanSessionsTableOrderingComposer(
            $db: $db,
            $table: $db.scanSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$NodesTableOrderingComposer get nodeId {
    final $$NodesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.nodeId,
      referencedTable: $db.nodes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NodesTableOrderingComposer(
            $db: $db,
            $table: $db.nodes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ScanSessionNodesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ScanSessionNodesTable> {
  $$ScanSessionNodesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get rssi =>
      $composableBuilder(column: $table.rssi, builder: (column) => column);

  $$ScanSessionsTableAnnotationComposer get sessionId {
    final $$ScanSessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.scanSessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ScanSessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.scanSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$NodesTableAnnotationComposer get nodeId {
    final $$NodesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.nodeId,
      referencedTable: $db.nodes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NodesTableAnnotationComposer(
            $db: $db,
            $table: $db.nodes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ScanSessionNodesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ScanSessionNodesTable,
          ScanSessionNode,
          $$ScanSessionNodesTableFilterComposer,
          $$ScanSessionNodesTableOrderingComposer,
          $$ScanSessionNodesTableAnnotationComposer,
          $$ScanSessionNodesTableCreateCompanionBuilder,
          $$ScanSessionNodesTableUpdateCompanionBuilder,
          (ScanSessionNode, $$ScanSessionNodesTableReferences),
          ScanSessionNode,
          PrefetchHooks Function({bool sessionId, bool nodeId})
        > {
  $$ScanSessionNodesTableTableManager(
    _$AppDatabase db,
    $ScanSessionNodesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ScanSessionNodesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ScanSessionNodesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ScanSessionNodesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> sessionId = const Value.absent(),
                Value<int> nodeId = const Value.absent(),
                Value<int> rssi = const Value.absent(),
              }) => ScanSessionNodesCompanion(
                id: id,
                sessionId: sessionId,
                nodeId: nodeId,
                rssi: rssi,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int sessionId,
                required int nodeId,
                required int rssi,
              }) => ScanSessionNodesCompanion.insert(
                id: id,
                sessionId: sessionId,
                nodeId: nodeId,
                rssi: rssi,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ScanSessionNodesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({sessionId = false, nodeId = false}) {
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
                    if (sessionId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.sessionId,
                                referencedTable:
                                    $$ScanSessionNodesTableReferences
                                        ._sessionIdTable(db),
                                referencedColumn:
                                    $$ScanSessionNodesTableReferences
                                        ._sessionIdTable(db)
                                        .id,
                              )
                              as T;
                    }
                    if (nodeId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.nodeId,
                                referencedTable:
                                    $$ScanSessionNodesTableReferences
                                        ._nodeIdTable(db),
                                referencedColumn:
                                    $$ScanSessionNodesTableReferences
                                        ._nodeIdTable(db)
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

typedef $$ScanSessionNodesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ScanSessionNodesTable,
      ScanSessionNode,
      $$ScanSessionNodesTableFilterComposer,
      $$ScanSessionNodesTableOrderingComposer,
      $$ScanSessionNodesTableAnnotationComposer,
      $$ScanSessionNodesTableCreateCompanionBuilder,
      $$ScanSessionNodesTableUpdateCompanionBuilder,
      (ScanSessionNode, $$ScanSessionNodesTableReferences),
      ScanSessionNode,
      PrefetchHooks Function({bool sessionId, bool nodeId})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$UsersTableTableManager get users =>
      $$UsersTableTableManager(_db, _db.users);
  $$NodesTableTableManager get nodes =>
      $$NodesTableTableManager(_db, _db.nodes);
  $$ScanSessionsTableTableManager get scanSessions =>
      $$ScanSessionsTableTableManager(_db, _db.scanSessions);
  $$ScanSessionNodesTableTableManager get scanSessionNodes =>
      $$ScanSessionNodesTableTableManager(_db, _db.scanSessionNodes);
}
