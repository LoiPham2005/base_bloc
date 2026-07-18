import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../manager/bloc_manager.dart';

/// Shared lease lifecycle for all `AutoBloc*` widgets:
///
/// - `initState` — acquires a [BlocLease] from [BlocManager] (creating the
///   instance on first use) and calls `onInit`.
/// - `didUpdateWidget` — when `scopeKey` changes, the old lease is released
///   and a new one acquired (v1 kept the stale instance and corrupted the
///   ref-count of the new key).
/// - `dispose` — calls `onDispose` and releases the lease; the instance closes
///   automatically when its last lease is gone.
mixin _LeaseStateMixin<W extends StatefulWidget, B extends BlocBase<Object?>> on State<W> {
  String? get scopeKey;
  B Function()? get create;
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
    _lease = BlocManager.acquire<B>(key: scopeKey, create: create);
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
///   onInit: (auth) => auth.checkSession(),
///   child: const AppShell(),
/// )
/// ```
class AutoBlocProvider<B extends BlocBase<Object?>> extends StatefulWidget {
  final Widget child;

  /// Scope key — multiple independent instances of the same type (family).
  final String? scopeKey;

  /// Inline factory; omit to use the [BlocManager.setFactory] DI factory.
  final B Function()? create;

  /// Called once per leased instance, right after acquisition.
  final void Function(B bloc)? onInit;

  /// Called right before the lease is released.
  final void Function(B bloc)? onDispose;

  const AutoBlocProvider({
    super.key,
    required this.child,
    this.scopeKey,
    this.create,
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
///   onInit: (c) => c.load(),
///   builder: (context, cubit, state) => Text('${state.data ?? 0}'),
/// )
/// ```
class AutoBlocBuilder<B extends BlocBase<S>, S> extends StatefulWidget {
  final Widget Function(BuildContext context, B bloc, S state) builder;
  final BlocBuilderCondition<S>? buildWhen;
  final String? scopeKey;
  final B Function()? create;
  final void Function(B bloc)? onInit;
  final void Function(B bloc)? onDispose;

  const AutoBlocBuilder({
    super.key,
    required this.builder,
    this.buildWhen,
    this.scopeKey,
    this.create,
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
  final void Function(B bloc)? onInit;
  final void Function(B bloc)? onDispose;

  const AutoBlocListener({
    super.key,
    required this.listener,
    required this.child,
    this.listenWhen,
    this.scopeKey,
    this.create,
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
  final void Function(B bloc)? onInit;
  final void Function(B bloc)? onDispose;

  const AutoBlocSelector({
    super.key,
    required this.selector,
    required this.builder,
    this.scopeKey,
    this.create,
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
