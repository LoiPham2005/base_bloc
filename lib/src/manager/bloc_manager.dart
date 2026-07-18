import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

/// A ref-counted handle on a [BlocManager]-owned instance.
///
/// Acquire with [BlocManager.acquire]; call [release] exactly once when done
/// (extra calls are safe no-ops). When the last lease for an instance is
/// released, the instance is closed and evicted — unless a `keepAlive` grace
/// period was requested, in which case it lingers (warm) until the timer
/// fires or it is re-acquired.
///
/// Leases are generation-tagged: if the underlying instance is replaced (for
/// example it was closed externally and re-created by a newer acquire), stale
/// leases become inert — releasing them can never close or corrupt the
/// ref-count of the replacement instance.
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
  Duration? keepAlive;
  Timer? disposeTimer;

  /// Runs once, right before this instance is closed. Set by the acquire that
  /// created it; instance-scoped, not widget-scoped.
  void Function(BlocBase<Object?> bloc)? onClose;
  int refs = 0;

  _Entry(this.bloc, this.generation, this.keepAlive);
}

/// Ref-counted lifecycle manager for [BlocBase] instances — smart_bloc's
/// answer to Riverpod's `autoDispose`: an instance lives exactly as long as
/// at least one widget (or manual lease) uses it, then closes automatically.
///
/// Scoped instances of the same type — Riverpod `family` — use a `key` (or the
/// typed `BlocFamily` wrapper):
///
/// ```dart
/// final tab1 = BlocManager.acquire<TabCubit>(key: 'tab1', create: () => TabCubit(1));
/// final tab2 = BlocManager.acquire<TabCubit>(key: 'tab2', create: () => TabCubit(2));
/// tab1.release();
/// tab2.release();
/// ```
///
/// `keepAlive` keeps an instance warm for a grace period after its last lease
/// is released (Riverpod's `keepAlive`), so quick back-navigation reuses it
/// instead of re-fetching:
///
/// ```dart
/// BlocManager.acquire<FeedCubit>(create: FeedCubit.new, keepAlive: const Duration(minutes: 5));
/// ```
///
/// In tests, [override] injects a fake for a type regardless of `create`/DI.
class BlocManager {
  BlocManager._();

  static final Map<String, _Entry> _entries = {};
  static final Map<String, BlocBase<Object?> Function()> _overrides = {};
  static int _generationCounter = 0;
  static T Function<T extends BlocBase<Object?>>()? _diFactory;

  // ── DI setup ──────────────────────────────────────────────────────────────

  /// Registers a DI factory used by [acquire] when no `create` is given.
  static void setFactory(T Function<T extends BlocBase<Object?>>() factory) {
    _diFactory = factory;
  }

  /// Removes a previously registered DI factory (useful in tests).
  static void clearFactory() => _diFactory = null;

  // ── Test overrides ──────────────────────────────────────────────────────────

  /// Overrides how instances of [T] (per [key]) are created — [acquire] will
  /// use [factory] instead of any `create`/DI factory. For tests:
  ///
  /// ```dart
  /// BlocManager.override<AuthCubit>(() => FakeAuthCubit());
  /// ```
  static void override<T extends BlocBase<Object?>>(T Function() factory, {String? key}) {
    _overrides[_cacheKey<T>(key)] = factory;
  }

  /// Clears all [override]s (call in test teardown).
  static void clearOverrides() => _overrides.clear();

  // ── Internals ───────────────────────────────────────────────────────────────

  static String _cacheKey<T>(String? key) => key == null ? '$T' : '$T#$key';

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Acquires a lease on the shared instance of [T] (per [key] scope),
  /// creating it if absent via an [override], [create], or the registered DI
  /// factory (in that precedence).
  ///
  /// [keepAlive], when set, keeps the instance warm for that duration after
  /// its last lease is released, instead of closing immediately.
  ///
  /// A factory ([override], [create] or the DI factory) is only needed when an
  /// instance has to be built. Acquiring an instance that is already live —
  /// a child widget sharing what its parent created — requires none of them.
  ///
  /// [onCreate] runs exactly once — only when this call actually creates a new
  /// instance, never on a shared or warm-reused one (put your initial `load()`
  /// here). [onClose] runs exactly once, right before the instance is closed.
  /// Both are instance-scoped, so keep them free of per-widget/UI state.
  ///
  /// An instance found closed (e.g. by [disposeAll]) is replaced with a fresh
  /// one; leases on the dead instance become inert.
  static BlocLease<T> acquire<T extends BlocBase<Object?>>({
    String? key,
    T Function()? create,
    Duration? keepAlive,
    void Function(T bloc)? onCreate,
    void Function(T bloc)? onClose,
  }) {
    final cacheKey = _cacheKey<T>(key);
    final override = _overrides[cacheKey];

    var entry = _entries[cacheKey];
    var created = false;
    if (entry == null || entry.bloc.isClosed) {
      // A factory is only required when we actually have to build an instance —
      // acquiring an already-live one (e.g. a child widget sharing the instance
      // its parent created) needs nothing.
      if (override == null && create == null && _diFactory == null) {
        throw StateError(
          'BlocManager.acquire<$T>: no live instance for this scope and no way '
          'to create one. Pass create: () => ..., register '
          'BlocManager.setFactory(), or override it in tests.',
        );
      }
      final BlocBase<Object?> bloc = override != null
          ? override()
          : (create != null ? create() : _diFactory!<T>());
      entry = _Entry(bloc, ++_generationCounter, keepAlive);
      if (onClose != null) entry.onClose = (b) => onClose(b as T);
      _entries[cacheKey] = entry;
      created = true;
    } else {
      // Warm re-acquire: cancel any pending keepAlive disposal.
      entry.disposeTimer?.cancel();
      entry.disposeTimer = null;
      if (keepAlive != null) entry.keepAlive = keepAlive;
    }

    entry.refs++;
    final bloc = entry.bloc as T;
    if (created && onCreate != null) onCreate(bloc);
    return BlocLease._(bloc, cacheKey, entry.generation);
  }

  static void _release(String cacheKey, int generation) {
    final entry = _entries[cacheKey];
    // Stale lease (instance already replaced or evicted): inert by design.
    if (entry == null || entry.generation != generation) return;

    entry.refs--;
    if (entry.refs > 0) return;

    final keepAlive = entry.keepAlive;
    if (keepAlive != null && keepAlive > Duration.zero && !entry.bloc.isClosed) {
      entry.disposeTimer?.cancel();
      entry.disposeTimer = Timer(keepAlive, () => _evict(cacheKey, generation));
    } else {
      _evict(cacheKey, generation);
    }
  }

  static void _evict(String cacheKey, int generation) {
    final entry = _entries[cacheKey];
    if (entry == null || entry.generation != generation) return;
    if (entry.refs > 0) return; // re-acquired during the keepAlive window
    entry.disposeTimer?.cancel();
    _entries.remove(cacheKey);
    if (!entry.bloc.isClosed) {
      entry.onClose?.call(entry.bloc);
      entry.bloc.close();
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
      entry.disposeTimer?.cancel();
      if (!entry.bloc.isClosed) {
        entry.onClose?.call(entry.bloc);
        entry.bloc.close();
      }
    }
  }

  // ── Debug ───────────────────────────────────────────────────────────────────

  /// Debug snapshot: cache key → (refs, generation, isClosed, keptWarm).
  static Map<String, ({int refs, int generation, bool isClosed, bool keptWarm})>
      get debugSnapshot => {
            for (final MapEntry(:key, :value) in _entries.entries)
              key: (
                refs: value.refs,
                generation: value.generation,
                isClosed: value.bloc.isClosed,
                keptWarm: value.refs == 0 && value.disposeTimer != null,
              ),
          };
}
