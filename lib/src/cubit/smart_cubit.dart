import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/exec.dart';
import '../effects/messenger.dart';
import '../errors/failures.dart';
import '../errors/result.dart';
import '../state/base_state.dart';

/// Base Cubit with typed [BaseState], safe async execution, one-shot UI
/// messages, and stale-result protection — no code generation required.
///
/// ```dart
/// class PostCubit extends SmartCubit<List<Post>> {
///   PostCubit(this._repo);
///   final PostRepository _repo;
///
///   Future<void> load() => query(action: _repo.getAll);
///
///   Future<void> delete(int id) => mutate(
///     action: () => _repo.delete(id),                          // Result<void> — no casts
///     apply: (posts, _) => [...posts]..removeWhere((p) => p.id == id),
///     successMessage: 'Post deleted',
///   );
/// }
/// ```
abstract class SmartCubit<T> extends Cubit<BaseState<T>>
    with
        UiMessenger<BaseState<T>>,
        BlocSubscriptions<BaseState<T>>,
        SmartExec<T> {
  SmartCubit([BaseState<T>? initialState]) : super(initialState ?? BaseState<T>.initial());

  /// Emits [newState] unless the cubit is closed.
  void safeEmit(BaseState<T> newState) {
    if (!isClosed) emit(newState);
  }

  bool _blocked() => isClosed;

  /// Fetches this cubit's data.
  ///
  /// Emits `loading → data | error`. Each call supersedes any in-flight query:
  /// a stale response completing late is **dropped**, never emitted over newer
  /// data. The action is remembered so [refresh] can re-run it.
  ///
  /// - [keepPreviousData] (default `true`) keeps current data visible during
  ///   the reload ([LoadingState.previousData]).
  /// - [silent] skips the loading emission entirely (background revalidation).
  Future<T?> query({
    required Future<Result<T>> Function() action,
    bool keepPreviousData = true,
    bool silent = false,
    void Function(T data)? onSuccess,
    void Function(Failure failure)? onFailure,
  }) {
    return execQuery(
      write: safeEmit,
      blocked: _blocked,
      action: action,
      keepPreviousData: keepPreviousData,
      silent: silent,
      onSuccess: onSuccess,
      onFailure: onFailure,
    );
  }

  /// [query] with an explicit mapping from the raw API type [R] to [T].
  ///
  /// The mapping is type-checked — there is no implicit `as T` cast anywhere.
  Future<T?> queryWith<R>({
    required Future<Result<R>> Function() action,
    required T Function(R raw) map,
    bool keepPreviousData = true,
    bool silent = false,
    void Function(T data)? onSuccess,
    void Function(Failure failure)? onFailure,
  }) {
    return query(
      action: () async => (await action()).map(map),
      keepPreviousData: keepPreviousData,
      silent: silent,
      onSuccess: onSuccess,
      onFailure: onFailure,
    );
  }

  /// Runs a side-effect operation (create/update/delete).
  ///
  /// Design rules (all fixing classic status-state bugs):
  /// - The result type [R] is independent of [T] — `mutate<void>` needs no
  ///   casts and cannot corrupt the data state.
  /// - Failures **keep the current data on screen** and surface as a one-shot
  ///   [UiMessenger.uiMessages] error instead of replacing the state.
  /// - While in flight, `state.mutating` is `true` (disable submit buttons).
  /// - [mode] defaults to [ExecMode.droppable]: double-taps are ignored.
  ///
  /// Use [apply] to update the data optimistically-safely from the result:
  /// it runs only when data exists, with a non-null `current`.
  Future<R?> mutate<R>({
    required Future<Result<R>> Function() action,
    String? successMessage,
    String? Function(Failure failure)? errorMessage,
    T Function(T current, R result)? apply,
    void Function(R result)? onSuccess,
    void Function(Failure failure)? onFailure,
    ExecMode mode = ExecMode.droppable,
    bool trackMutating = true,
  }) {
    return execMutate(
      write: safeEmit,
      blocked: _blocked,
      action: action,
      successMessage: successMessage,
      errorMessage: errorMessage,
      apply: apply,
      onSuccess: onSuccess,
      onFailure: onFailure,
      mode: mode,
      trackMutating: trackMutating,
    );
  }

  /// Re-runs the most recent [query]/[queryWith] action, keeping previous
  /// data visible. No-op when nothing has been queried yet.
  Future<void> refresh() async {
    final action = lastQuery;
    if (action == null) return;
    await execQuery(write: safeEmit, blocked: _blocked, action: action);
  }

  /// Whether [refresh] has a remembered query to re-run.
  bool get canRefresh => lastQuery != null;

  /// Replaces the data, keeping the current `mutating` flag.
  void setData(T data) => safeEmit(DataState<T>(data, mutating: state.mutating));

  /// Transforms the current data in place; no-op when no data is available.
  /// Useful for optimistic updates.
  void updateData(T Function(T current) update) {
    final current = state.dataOrNull;
    if (current != null) setData(update(current));
  }

  /// Cancels pending results and returns to [InitialState].
  void reset() {
    cancelPending();
    safeEmit(BaseState<T>.initial());
  }
}
