import 'package:flutter_bloc/flutter_bloc.dart';

/// A ref-counted handle on a [BlocManager]-owned instance.
///
/// Acquire with [BlocManager.acquire]; call [release] exactly once when done
/// (extra calls are safe no-ops). When the last lease for an instance is
/// released, the instance is closed and evicted.
///
/// Leases are generation-tagged: if the underlying instance is replaced (for
/// example it was closed externally and re-created by a newer acquire), stale
/// leases become inert — releasing them can never close or corrupt the
/// ref-count of the replacement instance. This fixes the classic ref-count
/// desync of raw `get`/`release` pairs.
class BlocLease<T extends BlocBase<Object?>> {
  /// The managed instance.
  final T bloc;

  final String _cacheKey;
  final int _generation;
  bool _released = false;

  BlocLease._(this.bloc, this._cacheKey, this._generation);

  /// Whether [release] has already been called.
  bool get isReleased => _released;

  /// Releases this lease. Idempotent.
  void release() {
    if (_released) return;
    _released = true;
    BlocManager._release(_cacheKey, _generation);
  }
}

class _Entry {
  final BlocBase<Object?> bloc;
  final int generation;
  int refs = 0;

  _Entry(this.bloc, this.generation);
}

/// Ref-counted lifecycle manager for [BlocBase] instances — smart_bloc's
/// answer to Riverpod's `autoDispose`: an instance lives exactly as long as
/// at least one widget (or manual lease) uses it, then closes automatically.
///
/// Scoped instances of the same type — Riverpod `family` — use a `key`:
///
/// ```dart
/// final tab1 = BlocManager.acquire<TabCubit>(key: 'tab1', create: () => TabCubit(1));
/// final tab2 = BlocManager.acquire<TabCubit>(key: 'tab2', create: () => TabCubit(2));
/// tab1.release();
/// tab2.release();
/// ```
///
/// Optionally register a DI factory once at startup so `acquire` can create
/// instances without an inline `create`:
///
/// ```dart
/// BlocManager.setFactory(<T extends BlocBase<Object?>>() => getIt<T>());
/// final auth = BlocManager.acquire<AuthCubit>();
/// ```
class BlocManager {
  BlocManager._();

  static final Map<String, _Entry> _entries = {};
  static int _generationCounter = 0;
  static T Function<T extends BlocBase<Object?>>()? _diFactory;

  /// Registers a DI factory used by [acquire] when no `create` is given.
  static void setFactory(T Function<T extends BlocBase<Object?>>() factory) {
    _diFactory = factory;
  }

  /// Removes a previously registered DI factory (useful in tests).
  static void clearFactory() => _diFactory = null;

  static String _cacheKey<T>(String? key) => key == null ? '$T' : '$T#$key';

  /// Acquires a lease on the shared instance of [T] (per [key] scope),
  /// creating it if absent via [create] or the registered DI factory.
  ///
  /// An instance found closed (closed externally, e.g. by `disposeAll`) is
  /// replaced with a fresh one; leases on the dead instance become inert.
  static BlocLease<T> acquire<T extends BlocBase<Object?>>({
    String? key,
    T Function()? create,
  }) {
    assert(
      create != null || _diFactory != null,
      'BlocManager.acquire<$T>: no `create` given and no DI factory set. '
      'Pass create: () => ..., or call BlocManager.setFactory() at startup.',
    );
    final cacheKey = _cacheKey<T>(key);

    var entry = _entries[cacheKey];
    if (entry == null || entry.bloc.isClosed) {
      final bloc = create != null ? create() : _diFactory!<T>();
      entry = _Entry(bloc, ++_generationCounter);
      _entries[cacheKey] = entry;
    }

    entry.refs++;
    return BlocLease._(entry.bloc as T, cacheKey, entry.generation);
  }

  static void _release(String cacheKey, int generation) {
    final entry = _entries[cacheKey];
    // Stale lease (instance already replaced or evicted): inert by design.
    if (entry == null || entry.generation != generation) return;

    entry.refs--;
    if (entry.refs <= 0) {
      _entries.remove(cacheKey);
      if (!entry.bloc.isClosed) entry.bloc.close();
    }
  }

  /// Returns the live instance of [T] without acquiring a lease, or `null`
  /// if absent or closed.
  static T? peek<T extends BlocBase<Object?>>({String? key}) {
    final entry = _entries[_cacheKey<T>(key)];
    if (entry == null || entry.bloc.isClosed) return null;
    return entry.bloc as T;
  }

  /// Closes and evicts every managed instance (logout / full reset).
  ///
  /// Outstanding leases become inert; widgets still on screen keep their (now
  /// closed) instance until they rebuild, so pair this with a full app
  /// restart/navigation reset (Phoenix pattern).
  static void disposeAll() {
    final entries = List.of(_entries.values);
    _entries.clear();
    for (final entry in entries) {
      if (!entry.bloc.isClosed) entry.bloc.close();
    }
  }

  /// Debug snapshot: cache key → (refs, generation, isClosed).
  static Map<String, ({int refs, int generation, bool isClosed})> get debugSnapshot => {
        for (final MapEntry(:key, :value) in _entries.entries)
          key: (refs: value.refs, generation: value.generation, isClosed: value.bloc.isClosed),
      };
}
