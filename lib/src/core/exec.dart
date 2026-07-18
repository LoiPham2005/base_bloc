import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../effects/messenger.dart';
import '../effects/ui_message.dart';
import '../errors/failures.dart';
import '../errors/result.dart';
import '../state/base_state.dart';
import 'config.dart';

/// Concurrency strategy for [SmartExec.execMutate].
enum ExecMode {
  /// New calls are ignored while one is in flight (double-tap protection).
  droppable,

  /// Every call runs; only the **latest** call's result is applied — earlier
  /// results are dropped when they complete late.
  restartable,

  /// Every call runs and applies its result (last write wins by completion
  /// order). Use only when operations are commutative.
  concurrent,
}

/// Writes a state to the owning bloc, respecting its emit rules.
typedef StateWriter<T> = void Function(BaseState<T> state);

/// Core query/mutation engine shared by `SmartCubit` and `SmartBloc`.
///
/// ## Queries vs mutations
///
/// - **Query** — produces the screen's data ([DataState]) or an [ErrorState].
///   Always *restartable*: each call supersedes the previous one, and a stale
///   response that completes late is dropped instead of overwriting newer data.
/// - **Mutation** — a side effect (create/update/delete). It never replaces
///   the data state with a failure: errors surface as one-shot [UiMessage]s
///   while existing data stays on screen. Progress is tracked via
///   [BaseState.mutating] so submit buttons can disable in place.
///
/// Cancellation here means *dropping stale results*, not aborting I/O; pair
/// with your HTTP client's cancel tokens when the request itself must stop.
mixin SmartExec<T> on BlocBase<BaseState<T>>, UiMessenger<BaseState<T>> {
  int _querySeq = 0;
  int _mutationSeq = 0;
  int _mutationsInFlight = 0;
  Future<Result<T>> Function()? _lastQuery;

  /// The most recent query action, normalized to produce `Result<T>`.
  /// Used by `SmartCubit.refresh()`.
  @protected
  Future<Result<T>> Function()? get lastQuery => _lastQuery;

  /// Whether any mutation is currently in flight.
  bool get hasMutationInFlight => _mutationsInFlight > 0;

  /// Invalidates all in-flight queries and (restartable) mutations: their
  /// results will be dropped when they complete. Does not abort the
  /// underlying I/O.
  void cancelPending() {
    _querySeq++;
    _mutationSeq++;
  }

  /// Runs [action], guarding against thrown errors, and returns its [Result].
  Future<Result<R>> _guarded<R>(Future<Result<R>> Function() action) async {
    try {
      return await action();
    } catch (error, stackTrace) {
      SmartBlocConfig.onUncaughtError?.call(error, stackTrace);
      return Result.failure(SmartBlocConfig.failureMapper(error, stackTrace));
    }
  }

  /// Query engine. See `SmartCubit.query` for the public-facing docs.
  @protected
  Future<T?> execQuery({
    required StateWriter<T> write,
    required bool Function() blocked,
    required Future<Result<T>> Function() action,
    bool keepPreviousData = true,
    bool silent = false,
    void Function(T data)? onSuccess,
    void Function(Failure failure)? onFailure,
  }) async {
    final seq = ++_querySeq;
    _lastQuery = action;

    if (!silent && !blocked()) {
      write(
        keepPreviousData
            ? state.toLoading()
            : LoadingState<T>(mutating: state.mutating),
      );
    }

    final result = await _guarded(action);

    // Superseded by a newer query (or the bloc closed): drop the stale result.
    if (seq != _querySeq || isClosed) return null;

    return result.fold(
      onSuccess: (data) {
        if (!blocked()) write(DataState<T>(data, mutating: state.mutating));
        onSuccess?.call(data);
        return data;
      },
      onFailure: (failure) {
        if (!blocked()) write(state.toError(failure));
        onFailure?.call(failure);
        return null;
      },
    );
  }

  /// Mutation engine. See `SmartCubit.mutate` for the public-facing docs.
  @protected
  Future<R?> execMutate<R>({
    required StateWriter<T> write,
    required bool Function() blocked,
    required Future<Result<R>> Function() action,
    String? successMessage,
    String? Function(Failure failure)? errorMessage,
    T Function(T current, R result)? apply,
    void Function(R result)? onSuccess,
    void Function(Failure failure)? onFailure,
    ExecMode mode = ExecMode.droppable,
    bool trackMutating = true,
  }) async {
    if (mode == ExecMode.droppable && _mutationsInFlight > 0) return null;

    final seq = ++_mutationSeq;
    _mutationsInFlight++;
    if (trackMutating && !blocked()) write(state.withMutating(true));

    Result<R> result;
    try {
      result = await _guarded(action);
    } finally {
      _mutationsInFlight--;
    }

    if (isClosed || (mode == ExecMode.restartable && seq != _mutationSeq)) {
      // Superseded/closed: the newer call (if any) owns the mutating flag.
      return null;
    }

    final stillMutating = _mutationsInFlight > 0;

    return result.fold(
      onSuccess: (value) {
        BaseState<T> next = state.withMutating(stillMutating);
        if (apply != null) {
          final current = state.dataOrNull;
          if (current != null) {
            next = DataState<T>(apply(current, value), mutating: stillMutating);
          }
        }
        if (!blocked()) write(next);
        if (successMessage != null) emitMessage(UiMessage.success(successMessage));
        onSuccess?.call(value);
        return value;
      },
      onFailure: (failure) {
        // Keep the data on screen — mutation failures are messages, not states.
        if (trackMutating && !blocked()) write(state.withMutating(stillMutating));
        final text = errorMessage != null ? errorMessage(failure) : failure.message;
        if (text != null) emitMessage(UiMessage.error(text, failure: failure));
        onFailure?.call(failure);
        return null;
      },
    );
  }
}

/// Auto-cancelled subscriptions to other blocs — lightweight cross-bloc
/// composition (the common case of Riverpod's `ref.listen`).
///
/// ```dart
/// class CartCubit extends SmartCubit<Cart> {
///   CartCubit(AuthCubit auth) {
///     listenTo(auth, (authState) {
///       if (authState.isInitial) reset(); // user signed out
///     });
///   }
/// }
/// ```
mixin BlocSubscriptions<S> on BlocBase<S> {
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  /// Subscribes to [other]'s state stream; cancelled automatically on [close].
  ///
  /// With [fireImmediately], [onState] is also called synchronously with
  /// [other]'s current state.
  StreamSubscription<S2> listenTo<S2>(
    BlocBase<S2> other,
    void Function(S2 state) onState, {
    bool fireImmediately = false,
  }) {
    final subscription = other.stream.listen(onState);
    _subscriptions.add(subscription);
    if (fireImmediately) onState(other.state);
    return subscription;
  }

  @override
  Future<void> close() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    return super.close();
  }
}
