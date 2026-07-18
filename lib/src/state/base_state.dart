import 'package:equatable/equatable.dart';

import '../errors/failures.dart';

/// Sealed state for all `SmartCubit`/`SmartBloc` instances.
///
/// Four variants, exhaustively matchable with native Dart 3 patterns:
///
/// ```dart
/// switch (state) {
///   InitialState()                       => const SizedBox(),
///   LoadingState(:final previousData)    => previousData == null
///       ? const CircularProgressIndicator()
///       : StaleDataView(previousData),
///   DataState(:final data)               => DataView(data), // data is T, never null
///   ErrorState(:final failure)           => ErrorView(failure.message),
/// }
/// ```
///
/// Unlike a status-enum state, the type system guarantees:
/// - [DataState.data] is a non-nullable `T` — no `data as T` casts, no runtime
///   surprises when a success state has no payload.
/// - [LoadingState] and [ErrorState] carry the previous data explicitly
///   ([LoadingState.previousData], [ErrorState.previousData]) so refresh and
///   error UIs can keep showing stale content.
///
/// Every variant also carries [mutating] — `true` while a `SmartCubit.mutate`
/// call is in flight — so submit buttons can disable without the main data
/// state leaving the screen.
sealed class BaseState<T> extends Equatable {
  /// Whether a mutation (side-effect operation) is currently in flight.
  ///
  /// Orthogonal to the variant: a list can stay [DataState] while a delete
  /// request runs with `mutating: true`.
  final bool mutating;

  const BaseState({this.mutating = false});

  // ── Factories ──────────────────────────────────────────────────

  /// Nothing has happened yet.
  const factory BaseState.initial({bool mutating}) = InitialState<T>;

  /// A query is in flight. Pass [previous] to keep stale data visible.
  const factory BaseState.loading({T? previous, bool mutating}) = LoadingState<T>;

  /// Data is available. [data] is non-nullable by construction.
  const factory BaseState.data(T data, {bool mutating}) = DataState<T>;

  /// A query failed. Pass [previous] to keep stale data visible.
  const factory BaseState.error(Failure failure, {T? previous, bool mutating}) = ErrorState<T>;

  // ── Variant checks ─────────────────────────────────────────────

  bool get isInitial => this is InitialState<T>;
  bool get isLoading => this is LoadingState<T>;
  bool get isData => this is DataState<T>;
  bool get isError => this is ErrorState<T>;

  /// Alias for [isData] (v1 name).
  bool get isSuccess => isData;

  /// Alias for [isError] (v1 name).
  bool get isFailure => isError;

  /// Alias for [mutating].
  bool get isMutating => mutating;

  /// Loading while previous data is still visible — pull-to-refresh UIs.
  bool get isRefreshing => this is LoadingState<T> && dataOrNull != null;

  // ── Data access ────────────────────────────────────────────────

  /// The best available data: current for [DataState], previous for
  /// [LoadingState]/[ErrorState], `null` for [InitialState].
  T? get dataOrNull => switch (this) {
        DataState<T>(:final data) => data,
        LoadingState<T>(:final previousData) => previousData,
        ErrorState<T>(:final previousData) => previousData,
        InitialState<T>() => null,
      };

  /// Nullable view of [dataOrNull]. [DataState] narrows this to non-null [T].
  T? get data => dataOrNull;

  bool get hasData => dataOrNull != null;

  /// The failure, when this is [ErrorState].
  Failure? get failureOrNull =>
      switch (this) { ErrorState<T>(:final failure) => failure, _ => null };

  /// Shortcut for `failureOrNull?.message`.
  String? get errorMessage => failureOrNull?.message;

  /// Whether the available data is an empty `Iterable`/`Map`.
  bool get isEmptyData {
    final d = dataOrNull;
    if (d is Iterable) return d.isEmpty;
    if (d is Map) return d.isEmpty;
    return false;
  }

  // ── Transitions ────────────────────────────────────────────────

  /// A loading state that keeps this state's data as [LoadingState.previousData].
  BaseState<T> toLoading() => LoadingState<T>(previous: dataOrNull, mutating: mutating);

  /// An error state that keeps this state's data as [ErrorState.previousData].
  BaseState<T> toError(Failure failure) =>
      ErrorState<T>(failure, previous: dataOrNull, mutating: mutating);

  /// The same variant with [mutating] replaced.
  BaseState<T> withMutating(bool value) {
    if (value == mutating) return this;
    return switch (this) {
      InitialState<T>() => InitialState<T>(mutating: value),
      LoadingState<T>(:final previousData) =>
        LoadingState<T>(previous: previousData, mutating: value),
      DataState<T>(:final data) => DataState<T>(data, mutating: value),
      ErrorState<T>(:final failure, :final previousData) =>
        ErrorState<T>(failure, previous: previousData, mutating: value),
    };
  }

  /// Maps the payload type, preserving variant, previous data and [mutating].
  BaseState<R> mapData<R>(R Function(T data) mapper) {
    R? mapNullable(T? value) => value == null ? null : mapper(value);
    return switch (this) {
      InitialState<T>() => InitialState<R>(mutating: mutating),
      LoadingState<T>(:final previousData) =>
        LoadingState<R>(previous: mapNullable(previousData), mutating: mutating),
      DataState<T>(:final data) => DataState<R>(mapper(data), mutating: mutating),
      ErrorState<T>(:final failure, :final previousData) =>
        ErrorState<R>(failure, previous: mapNullable(previousData), mutating: mutating),
    };
  }

  // ── Functional matching (sugar over native switch) ─────────────

  /// Exhaustive match. [empty] (optional) intercepts [DataState] whose payload
  /// is an empty `Iterable`/`Map` — the stored state is never rewritten.
  R when<R>({
    required R Function() initial,
    required R Function(T? previous) loading,
    required R Function(T data) data,
    required R Function(Failure failure, T? previous) error,
    R Function()? empty,
  }) {
    return switch (this) {
      InitialState<T>() => initial(),
      LoadingState<T>(:final previousData) => loading(previousData),
      DataState<T>(data: final d) =>
        (empty != null && isEmptyData) ? empty() : data(d),
      ErrorState<T>(:final failure, :final previousData) => error(failure, previousData),
    };
  }

  /// Non-exhaustive match; unhandled variants fall through to [orElse].
  R maybeWhen<R>({
    R Function()? initial,
    R Function(T? previous)? loading,
    R Function(T data)? data,
    R Function(Failure failure, T? previous)? error,
    R Function()? empty,
    required R Function() orElse,
  }) {
    return switch (this) {
      InitialState<T>() => initial != null ? initial() : orElse(),
      LoadingState<T>(:final previousData) =>
        loading != null ? loading(previousData) : orElse(),
      DataState<T>(data: final d) => (empty != null && isEmptyData)
          ? empty()
          : (data != null ? data(d) : orElse()),
      ErrorState<T>(:final failure, :final previousData) =>
        error != null ? error(failure, previousData) : orElse(),
    };
  }
}

/// Nothing has happened yet.
final class InitialState<T> extends BaseState<T> {
  const InitialState({super.mutating});

  @override
  List<Object?> get props => [mutating];

  @override
  String toString() => 'InitialState<$T>(mutating: $mutating)';
}

/// A query is in flight, optionally with stale data still visible.
final class LoadingState<T> extends BaseState<T> {
  /// Data from before this load started (e.g. during pull-to-refresh).
  final T? previousData;

  const LoadingState({T? previous, super.mutating}) : previousData = previous;

  @override
  List<Object?> get props => [previousData, mutating];

  @override
  String toString() =>
      'LoadingState<$T>(hasPrevious: ${previousData != null}, mutating: $mutating)';
}

/// Data is available.
final class DataState<T> extends BaseState<T> {
  /// The payload — non-nullable by construction.
  @override
  final T data;

  const DataState(this.data, {super.mutating});

  @override
  T get dataOrNull => data;

  @override
  List<Object?> get props => [data, mutating];

  @override
  String toString() => 'DataState<$T>($data, mutating: $mutating)';
}

/// A query failed, optionally with stale data still visible.
final class ErrorState<T> extends BaseState<T> {
  final Failure failure;

  /// Data from before the failing load started.
  final T? previousData;

  const ErrorState(this.failure, {T? previous, super.mutating}) : previousData = previous;

  @override
  List<Object?> get props => [failure, previousData, mutating];

  @override
  String toString() =>
      'ErrorState<$T>($failure, hasPrevious: ${previousData != null}, mutating: $mutating)';
}
