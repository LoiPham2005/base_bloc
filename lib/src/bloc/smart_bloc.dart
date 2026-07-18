import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/exec.dart';
import '../effects/messenger.dart';
import '../errors/failures.dart';
import '../errors/result.dart';
import '../state/base_state.dart';

/// Optional Equatable base class for events used with [SmartBloc].
abstract class BaseEvent extends Equatable {
  const BaseEvent();

  @override
  List<Object?> get props => [];
}

/// Event-based counterpart of `SmartCubit` — fully generic over the event
/// type [E] **and** the data type [T] (state is `BaseState<T>`, never
/// `Object?`).
///
/// ```dart
/// sealed class PostEvent extends BaseEvent {}
/// class LoadPosts extends PostEvent {}
/// class DeletePost extends PostEvent {
///   final int id;
///   DeletePost(this.id);
///   @override
///   List<Object?> get props => [id];
/// }
///
/// class PostBloc extends SmartBloc<PostEvent, List<Post>> {
///   PostBloc(this._repo) {
///     on<LoadPosts>((event, emit) => query(emit, action: _repo.getAll));
///     on<DeletePost>((event, emit) => mutate(
///       emit,
///       action: () => _repo.delete(event.id),
///       apply: (posts, _) => [...posts]..removeWhere((p) => p.id == event.id),
///       successMessage: 'Post deleted',
///     ));
///   }
///   final PostRepository _repo;
/// }
/// ```
///
/// Combine with `bloc_concurrency` transformers on `on<E>` for event-level
/// concurrency control; [query]/[mutate] additionally drop stale results the
/// same way `SmartCubit` does.
abstract class SmartBloc<E, T> extends Bloc<E, BaseState<T>>
    with
        UiMessenger<BaseState<T>>,
        BlocSubscriptions<BaseState<T>>,
        SmartExec<T> {
  SmartBloc([BaseState<T>? initialState]) : super(initialState ?? BaseState<T>.initial());

  StateWriter<T> _writer(Emitter<BaseState<T>> emit) =>
      (s) {
        if (!emit.isDone) emit(s);
      };

  bool Function() _blocked(Emitter<BaseState<T>> emit) => () => emit.isDone || isClosed;

  /// Fetches this bloc's data — see `SmartCubit.query` for semantics.
  /// [emit] must be the emitter of the running event handler.
  Future<T?> query(
    Emitter<BaseState<T>> emit, {
    required Future<Result<T>> Function() action,
    bool keepPreviousData = true,
    bool silent = false,
    void Function(T data)? onSuccess,
    void Function(Failure failure)? onFailure,
  }) {
    return execQuery(
      write: _writer(emit),
      blocked: _blocked(emit),
      action: action,
      keepPreviousData: keepPreviousData,
      silent: silent,
      onSuccess: onSuccess,
      onFailure: onFailure,
    );
  }

  /// [query] with an explicit mapping from the raw API type [R] to [T].
  Future<T?> queryWith<R>(
    Emitter<BaseState<T>> emit, {
    required Future<Result<R>> Function() action,
    required T Function(R raw) map,
    bool keepPreviousData = true,
    bool silent = false,
    void Function(T data)? onSuccess,
    void Function(Failure failure)? onFailure,
  }) {
    return query(
      emit,
      action: () async => (await action()).map(map),
      keepPreviousData: keepPreviousData,
      silent: silent,
      onSuccess: onSuccess,
      onFailure: onFailure,
    );
  }

  /// Runs a side-effect operation — see `SmartCubit.mutate` for semantics.
  /// [emit] must be the emitter of the running event handler.
  Future<R?> mutate<R>(
    Emitter<BaseState<T>> emit, {
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
      write: _writer(emit),
      blocked: _blocked(emit),
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
}
