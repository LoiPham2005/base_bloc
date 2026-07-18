import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubit/smart_cubit.dart';
import '../errors/failures.dart';
import '../manager/bloc_manager.dart';
import '../state/base_state.dart';
import 'defaults.dart';
import 'effect_listener.dart';

/// The batteries-included screen builder for a [SmartCubit]: you write the
/// [data] UI, everything else has sensible, globally configurable defaults.
///
/// ```dart
/// AutoStateBuilder<PostCubit, List<Post>>(
///   create: () => PostCubit(repo),
///   onInit: (c) => c.load(),
///   data: (context, posts) => PostListView(posts),
/// )
/// ```
///
/// Defaults (each overridable inline or via [SmartBlocDefaults]):
/// - **loading** with no previous data → [SmartBlocDefaults.loading];
///   with previous data → the [data] UI under a thin [LinearProgressIndicator]
///   (pull-to-refresh look, for free).
/// - **error** → [SmartBlocDefaults.error] with a Retry button wired to
///   `cubit.refresh()` (override the action with [onRetry]).
/// - **empty** (only when an [empty] builder is given) intercepts data that is
///   an empty `Iterable`/`Map`.
/// - **messages**: set [listenMessages] to also surface the cubit's one-shot
///   `UiMessage`s as snackbars here (leave it off when a `UiMessageListener`
///   already wraps this subtree, or the same cubit is shown twice).
///
/// The cubit is leased from [BlocManager] (created on first use, closed with
/// the last lease) and provided to descendants — `context.read<C>()` works
/// inside [data].
class AutoStateBuilder<C extends SmartCubit<T>, T> extends StatefulWidget {
  /// Builds the UI for available data. Never called with null data.
  final Widget Function(BuildContext context, T data) data;

  /// Loading UI. Default: previous data (if any) under a progress bar,
  /// otherwise [SmartBlocDefaults.loading].
  final Widget Function(BuildContext context, T? previous)? loading;

  /// Error UI. Default: [SmartBlocDefaults.error] with retry.
  final Widget Function(BuildContext context, Failure failure, VoidCallback retry)? error;

  /// When given, replaces [data] for empty `Iterable`/`Map` payloads.
  final Widget Function(BuildContext context)? empty;

  /// UI before anything happened. Default: [SmartBlocDefaults.initial].
  final Widget Function(BuildContext context)? initial;

  /// Retry action for the default error UI. Default: `cubit.refresh()`.
  final VoidCallback? onRetry;

  /// Overlay a [LinearProgressIndicator] on stale data while reloading.
  final bool showRefreshIndicator;

  /// Also present this cubit's one-shot `UiMessage`s from here.
  final bool listenMessages;

  /// Scope key — independent instances of the same cubit type (family).
  final String? scopeKey;

  /// Inline factory; omit to use the [BlocManager.setFactory] DI factory.
  final C Function()? create;

  /// Called once per leased instance — kick off the first load here.
  final void Function(C cubit)? onInit;

  /// Called right before the lease is released.
  final void Function(C cubit)? onDispose;

  const AutoStateBuilder({
    super.key,
    required this.data,
    this.loading,
    this.error,
    this.empty,
    this.initial,
    this.onRetry,
    this.showRefreshIndicator = true,
    this.listenMessages = false,
    this.scopeKey,
    this.create,
    this.onInit,
    this.onDispose,
  });

  @override
  State<AutoStateBuilder<C, T>> createState() => _AutoStateBuilderState<C, T>();
}

class _AutoStateBuilderState<C extends SmartCubit<T>, T>
    extends State<AutoStateBuilder<C, T>> {
  late BlocLease<C> _lease;

  C get cubit => _lease.bloc;

  @override
  void initState() {
    super.initState();
    _acquire();
  }

  void _acquire() {
    _lease = BlocManager.acquire<C>(key: widget.scopeKey, create: widget.create);
    widget.onInit?.call(cubit);
  }

  @override
  void didUpdateWidget(AutoStateBuilder<C, T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scopeKey != widget.scopeKey) {
      widget.onDispose?.call(cubit);
      _lease.release();
      _acquire();
    }
  }

  @override
  void dispose() {
    widget.onDispose?.call(cubit);
    _lease.release();
    super.dispose();
  }

  Widget _dataOrEmpty(BuildContext context, T data) {
    if (widget.empty != null) {
      final isBlank = (data is Iterable && data.isEmpty) || (data is Map && data.isEmpty);
      if (isBlank) return widget.empty!(context);
    }
    return widget.data(context, data);
  }

  Widget _buildState(BuildContext context, BaseState<T> state) {
    return state.when(
      initial: () => (widget.initial ?? SmartBlocDefaults.initial)(context),
      loading: (previous) {
        if (widget.loading != null) return widget.loading!(context, previous);
        if (previous == null) return SmartBlocDefaults.loading(context);
        final stale = _dataOrEmpty(context, previous);
        if (!widget.showRefreshIndicator) return stale;
        return Stack(
          children: [
            stale,
            const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator()),
          ],
        );
      },
      data: (data) => _dataOrEmpty(context, data),
      error: (failure, _) {
        final retry = widget.onRetry ?? cubit.refresh;
        return (widget.error ?? SmartBlocDefaults.error)(context, failure, retry);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget child = BlocBuilder<C, BaseState<T>>(bloc: cubit, builder: _buildState);
    if (widget.listenMessages) {
      child = UiMessageListener<C>(bloc: cubit, child: child);
    }
    return BlocProvider<C>.value(value: cubit, child: child);
  }
}
