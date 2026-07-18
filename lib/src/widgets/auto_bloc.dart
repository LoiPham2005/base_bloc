import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../manager/bloc_manager.dart';

/// Shared lease lifecycle for all `AutoBloc*` widgets.
///
/// ## Two tiers of callbacks
///
/// - **Per instance** — `onCreate` / `onClose` run *once* for the underlying
///   bloc, no matter how many widgets share it or how often they remount.
///   Put your initial `load()` in `onCreate`: it will not double-fire when the
///   instance is shared or kept warm by `keepAlive`.
/// - **Per widget** — `onInit` / `onDispose` run every time *this* widget mounts
///   and unmounts. Use them for widget-scoped side effects (analytics, focus).
///
/// ## `scopeKey` and `create`
///
/// The instance is keyed by type **plus** `scopeKey`. `create` only runs on the
/// first acquisition of a given key — **changing the `create` closure does not
/// recreate the instance**. To get a fresh instance per argument (Riverpod
/// `family`), vary `scopeKey` (e.g. `scopeKey: 'product-$id'`), not `create`.
///
/// `didUpdateWidget` releases the old lease and acquires a new one when
/// `scopeKey` changes.
mixin _LeaseStateMixin<W extends StatefulWidget, B extends BlocBase<Object?>> on State<W> {
  String? get scopeKey;
  B Function()? get create;
  Duration? get keepAlive;
  void Function(B bloc)? get onCreateCallback;
  void Function(B bloc)? get onCloseCallback;
  void Function(B bloc)? get onInitCallback;
  void Function(B bloc)? get onDisposeCallback;

  late BlocLease<B> _lease;

  /// The leased instance.
  B get bloc => _lease.bloc;

  @override
  void initState() {
    super.initState();
    _acquire();
  }

  void _acquire() {
    _lease = BlocManager.acquire<B>(
      key: scopeKey,
      create: create,
      keepAlive: keepAlive,
      onCreate: onCreateCallback,
      onClose: onCloseCallback,
    );
    onInitCallback?.call(bloc);
  }

  /// Call from `didUpdateWidget` with the previous widget's scope key.
  void swapLeaseIfNeeded(String? oldScopeKey) {
    if (oldScopeKey == scopeKey) return;
    onDisposeCallback?.call(bloc);
    _lease.release();
    _acquire();
  }

  @override
  void dispose() {
    onDisposeCallback?.call(bloc);
    _lease.release();
    super.dispose();
  }
}

// ──────────────────────────────────────────────────────────────────────────
// AutoBlocProvider
// ──────────────────────────────────────────────────────────────────────────

/// Acquires [B] from [BlocManager] and provides it to descendants, without
/// building UI itself. The instance is shared with every other widget leasing
/// the same type+scope and closes when the last lease is released.
///
/// ```dart
/// AutoBlocProvider<AuthCubit>(
///   onCreate: (auth) => auth.checkSession(), // once per instance
///   child: const AppShell(),
/// )
/// ```
class AutoBlocProvider<B extends BlocBase<Object?>> extends StatefulWidget {
  final Widget child;

  /// Scope key — multiple independent instances of the same type (family).
  ///
  /// Vary this to get one instance per argument; do **not** rely on changing
  /// [create], which only runs on first acquisition of a given key.
  final String? scopeKey;

  /// Inline factory; omit to use the [BlocManager.setFactory] DI factory.
  /// Only runs on first acquisition of this type+[scopeKey].
  final B Function()? create;

  /// Keeps the instance warm this long after the last lease is released, so a
  /// quick remount reuses it instead of re-creating.
  final Duration? keepAlive;

  /// Runs once, when the instance is first created (not on shared/warm reuse).
  final void Function(B bloc)? onCreate;

  /// Runs once, right before the instance is closed.
  final void Function(B bloc)? onClose;

  /// Runs every time this widget mounts (per widget, not per instance).
  final void Function(B bloc)? onInit;

  /// Runs every time this widget unmounts (per widget, not per instance).
  final void Function(B bloc)? onDispose;

  const AutoBlocProvider({
    super.key,
    required this.child,
    this.scopeKey,
    this.create,
    this.keepAlive,
    this.onCreate,
    this.onClose,
    this.onInit,
    this.onDispose,
  });

  @override
  State<AutoBlocProvider<B>> createState() => _AutoBlocProviderState<B>();
}

class _AutoBlocProviderState<B extends BlocBase<Object?>>
    extends State<AutoBlocProvider<B>> with _LeaseStateMixin<AutoBlocProvider<B>, B> {
  @override
  String? get scopeKey => widget.scopeKey;
  @override
  B Function()? get create => widget.create;
  @override
  Duration? get keepAlive => widget.keepAlive;
  @override
  void Function(B)? get onCreateCallback => widget.onCreate;
  @override
  void Function(B)? get onCloseCallback => widget.onClose;
  @override
  void Function(B)? get onInitCallback => widget.onInit;
  @override
  void Function(B)? get onDisposeCallback => widget.onDispose;

  @override
  void didUpdateWidget(AutoBlocProvider<B> oldWidget) {
    super.didUpdateWidget(oldWidget);
    swapLeaseIfNeeded(oldWidget.scopeKey);
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<B>.value(value: bloc, child: widget.child);
  }
}

// ──────────────────────────────────────────────────────────────────────────
// AutoBlocBuilder
// ──────────────────────────────────────────────────────────────────────────

/// [AutoBlocProvider] + `BlocBuilder` in one widget; the [builder] receives
/// the leased `bloc` directly.
///
/// ```dart
/// AutoBlocBuilder<CounterCubit, BaseState<int>>(
///   onCreate: (c) => c.load(),
///   builder: (context, cubit, state) => Text('${state.data ?? 0}'),
/// )
/// ```
class AutoBlocBuilder<B extends BlocBase<S>, S> extends StatefulWidget {
  final Widget Function(BuildContext context, B bloc, S state) builder;
  final BlocBuilderCondition<S>? buildWhen;
  final String? scopeKey;
  final B Function()? create;
  final Duration? keepAlive;
  final void Function(B bloc)? onCreate;
  final void Function(B bloc)? onClose;
  final void Function(B bloc)? onInit;
  final void Function(B bloc)? onDispose;

  const AutoBlocBuilder({
    super.key,
    required this.builder,
    this.buildWhen,
    this.scopeKey,
    this.create,
    this.keepAlive,
    this.onCreate,
    this.onClose,
    this.onInit,
    this.onDispose,
  });

  @override
  State<AutoBlocBuilder<B, S>> createState() => _AutoBlocBuilderState<B, S>();
}

class _AutoBlocBuilderState<B extends BlocBase<S>, S>
    extends State<AutoBlocBuilder<B, S>> with _LeaseStateMixin<AutoBlocBuilder<B, S>, B> {
  @override
  String? get scopeKey => widget.scopeKey;
  @override
  B Function()? get create => widget.create;
  @override
  Duration? get keepAlive => widget.keepAlive;
  @override
  void Function(B)? get onCreateCallback => widget.onCreate;
  @override
  void Function(B)? get onCloseCallback => widget.onClose;
  @override
  void Function(B)? get onInitCallback => widget.onInit;
  @override
  void Function(B)? get onDisposeCallback => widget.onDispose;

  @override
  void didUpdateWidget(AutoBlocBuilder<B, S> oldWidget) {
    super.didUpdateWidget(oldWidget);
    swapLeaseIfNeeded(oldWidget.scopeKey);
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<B>.value(
      value: bloc,
      child: BlocBuilder<B, S>(
        bloc: bloc,
        buildWhen: widget.buildWhen,
        builder: (context, state) => widget.builder(context, bloc, state),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// AutoBlocListener
// ──────────────────────────────────────────────────────────────────────────

/// [AutoBlocProvider] + `BlocListener` in one widget (state side-effects only,
/// no rebuilds). For one-shot snackbars/navigation prefer `UiMessageListener`
/// or `EffectListener` — state listeners never fire twice for two identical
/// consecutive states, because equal states are not re-emitted.
class AutoBlocListener<B extends BlocBase<S>, S> extends StatefulWidget {
  final void Function(BuildContext context, B bloc, S state) listener;
  final BlocListenerCondition<S>? listenWhen;
  final Widget child;
  final String? scopeKey;
  final B Function()? create;
  final Duration? keepAlive;
  final void Function(B bloc)? onCreate;
  final void Function(B bloc)? onClose;
  final void Function(B bloc)? onInit;
  final void Function(B bloc)? onDispose;

  const AutoBlocListener({
    super.key,
    required this.listener,
    required this.child,
    this.listenWhen,
    this.scopeKey,
    this.create,
    this.keepAlive,
    this.onCreate,
    this.onClose,
    this.onInit,
    this.onDispose,
  });

  @override
  State<AutoBlocListener<B, S>> createState() => _AutoBlocListenerState<B, S>();
}

class _AutoBlocListenerState<B extends BlocBase<S>, S>
    extends State<AutoBlocListener<B, S>> with _LeaseStateMixin<AutoBlocListener<B, S>, B> {
  @override
  String? get scopeKey => widget.scopeKey;
  @override
  B Function()? get create => widget.create;
  @override
  Duration? get keepAlive => widget.keepAlive;
  @override
  void Function(B)? get onCreateCallback => widget.onCreate;
  @override
  void Function(B)? get onCloseCallback => widget.onClose;
  @override
  void Function(B)? get onInitCallback => widget.onInit;
  @override
  void Function(B)? get onDisposeCallback => widget.onDispose;

  @override
  void didUpdateWidget(AutoBlocListener<B, S> oldWidget) {
    super.didUpdateWidget(oldWidget);
    swapLeaseIfNeeded(oldWidget.scopeKey);
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<B>.value(
      value: bloc,
      child: BlocListener<B, S>(
        bloc: bloc,
        listenWhen: widget.listenWhen,
        listener: (context, state) => widget.listener(context, bloc, state),
        child: widget.child,
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// AutoBlocConsumer
// ──────────────────────────────────────────────────────────────────────────

/// [AutoBlocBuilder] + [AutoBlocListener] combined.
class AutoBlocConsumer<B extends BlocBase<S>, S> extends StatefulWidget {
  final Widget Function(BuildContext context, B bloc, S state) builder;
  final void Function(BuildContext context, B bloc, S state) listener;
  final BlocBuilderCondition<S>? buildWhen;
  final BlocListenerCondition<S>? listenWhen;
  final String? scopeKey;
  final B Function()? create;
  final Duration? keepAlive;
  final void Function(B bloc)? onCreate;
  final void Function(B bloc)? onClose;
  final void Function(B bloc)? onInit;
  final void Function(B bloc)? onDispose;

  const AutoBlocConsumer({
    super.key,
    required this.builder,
    required this.listener,
    this.buildWhen,
    this.listenWhen,
    this.scopeKey,
    this.create,
    this.keepAlive,
    this.onCreate,
    this.onClose,
    this.onInit,
    this.onDispose,
  });

  @override
  State<AutoBlocConsumer<B, S>> createState() => _AutoBlocConsumerState<B, S>();
}

class _AutoBlocConsumerState<B extends BlocBase<S>, S>
    extends State<AutoBlocConsumer<B, S>> with _LeaseStateMixin<AutoBlocConsumer<B, S>, B> {
  @override
  String? get scopeKey => widget.scopeKey;
  @override
  B Function()? get create => widget.create;
  @override
  Duration? get keepAlive => widget.keepAlive;
  @override
  void Function(B)? get onCreateCallback => widget.onCreate;
  @override
  void Function(B)? get onCloseCallback => widget.onClose;
  @override
  void Function(B)? get onInitCallback => widget.onInit;
  @override
  void Function(B)? get onDisposeCallback => widget.onDispose;

  @override
  void didUpdateWidget(AutoBlocConsumer<B, S> oldWidget) {
    super.didUpdateWidget(oldWidget);
    swapLeaseIfNeeded(oldWidget.scopeKey);
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<B>.value(
      value: bloc,
      child: BlocConsumer<B, S>(
        bloc: bloc,
        buildWhen: widget.buildWhen,
        listenWhen: widget.listenWhen,
        builder: (context, state) => widget.builder(context, bloc, state),
        listener: (context, state) => widget.listener(context, bloc, state),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// AutoBlocSelector
// ──────────────────────────────────────────────────────────────────────────

/// [AutoBlocProvider] + `BlocSelector`: rebuilds only when the selected value
/// changes (compared with `==` — give [V] value semantics).
///
/// ```dart
/// AutoBlocSelector<CartCubit, BaseState<Cart>, int>(
///   selector: (state) => state.data?.itemCount ?? 0,
///   builder: (context, count) => Badge(label: Text('$count')),
/// )
/// ```
class AutoBlocSelector<B extends BlocBase<S>, S, V> extends StatefulWidget {
  final V Function(S state) selector;
  final Widget Function(BuildContext context, V value) builder;
  final String? scopeKey;
  final B Function()? create;
  final Duration? keepAlive;
  final void Function(B bloc)? onCreate;
  final void Function(B bloc)? onClose;
  final void Function(B bloc)? onInit;
  final void Function(B bloc)? onDispose;

  const AutoBlocSelector({
    super.key,
    required this.selector,
    required this.builder,
    this.scopeKey,
    this.create,
    this.keepAlive,
    this.onCreate,
    this.onClose,
    this.onInit,
    this.onDispose,
  });

  @override
  State<AutoBlocSelector<B, S, V>> createState() => _AutoBlocSelectorState<B, S, V>();
}

class _AutoBlocSelectorState<B extends BlocBase<S>, S, V>
    extends State<AutoBlocSelector<B, S, V>>
    with _LeaseStateMixin<AutoBlocSelector<B, S, V>, B> {
  @override
  String? get scopeKey => widget.scopeKey;
  @override
  B Function()? get create => widget.create;
  @override
  Duration? get keepAlive => widget.keepAlive;
  @override
  void Function(B)? get onCreateCallback => widget.onCreate;
  @override
  void Function(B)? get onCloseCallback => widget.onClose;
  @override
  void Function(B)? get onInitCallback => widget.onInit;
  @override
  void Function(B)? get onDisposeCallback => widget.onDispose;

  @override
  void didUpdateWidget(AutoBlocSelector<B, S, V> oldWidget) {
    super.didUpdateWidget(oldWidget);
    swapLeaseIfNeeded(oldWidget.scopeKey);
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<B>.value(
      value: bloc,
      child: BlocSelector<B, S, V>(
        bloc: bloc,
        selector: widget.selector,
        builder: widget.builder,
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// MultiAutoBlocProvider
// ──────────────────────────────────────────────────────────────────────────

/// Nests multiple provider-style widgets without deep indentation, preserving
/// each provider's generic type.
///
/// ```dart
/// MultiAutoBlocProvider(
///   providers: [
///     (child) => AutoBlocProvider<AuthCubit>(child: child),
///     (child) => AutoBlocProvider<SettingsCubit>(child: child),
///   ],
///   child: const AppShell(),
/// )
/// ```
class MultiAutoBlocProvider extends StatelessWidget {
  /// Applied so that the **first** entry becomes the outermost widget.
  final List<Widget Function(Widget child)> providers;
  final Widget child;

  const MultiAutoBlocProvider({super.key, required this.providers, required this.child});

  @override
  Widget build(BuildContext context) {
    Widget result = child;
    for (final wrap in providers.reversed) {
      result = wrap(result);
    }
    return result;
  }
}
