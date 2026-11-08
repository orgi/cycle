import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/chain_log.dart';

/// Persists the [ChainLog]. Behind an interface so tests inject a fake.
abstract class ChainLogStore {
  Future<ChainLog> load();
  Future<void> save(ChainLog log);
}

/// Next to the bike profiles in the preferences (not the ride DB): like them
/// it's small, and it syncs with them.
class SharedPrefsChainLogStore implements ChainLogStore {
  static const _key = 'bike.chains';

  /// Never throws: an unreadable log is an empty one.
  @override
  Future<ChainLog> load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      return raw == null ? ChainLog.empty : ChainLog.fromJson(jsonDecode(raw));
    } catch (_) {
      return ChainLog.empty;
    }
  }

  @override
  Future<void> save(ChainLog log) async =>
      (await SharedPreferences.getInstance())
          .setString(_key, jsonEncode(log.toJson()));
}

class MemoryChainLogStore implements ChainLogStore {
  MemoryChainLogStore([this.log = ChainLog.empty]);

  ChainLog log;

  @override
  Future<ChainLog> load() async => log;

  @override
  Future<void> save(ChainLog log) async => this.log = log;
}
