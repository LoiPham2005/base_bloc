import '../core/config.dart';
import 'failures.dart';

/// A discriminated union representing either a success value [T] or a [Failure].
///
/// Inspired by Haskell's `Either` and Rust's `Result`. Uses Dart 3 sealed classes.
///
/// ## Creating
/// ```dart
/// Result<User> result = Result.success(user);
/// Result<User> result = Result.failure(ServerFailure());
/// ```
///
/// ## Consuming
/// ```dart
/// result.fold(
///   onSuccess: (user) => print(user),
///   onFailure: (failure) => print(failure.message),
/// );
///
/// // Or with null-safe accessors
/// final user = result.dataOrNull;
/// final failure = result.failureOrNull;
/// ```
sealed class Result<T> {
  const Result();

  /// Creates a successful [Result] wrapping [data].
  const factory Result.success(T data) = ResultSuccess<T>;

  /// Creates a failed [Result] wrapping a [Failure].
  const factory Result.failure(Failure failure) = ResultFailure<T>;

  /// Runs [action] and captures anything it throws as a [Result.failure],
  /// using [SmartBlocConfig.failureMapper] (mirror of `AsyncValue.guard`).
  ///
  /// ```dart
  /// Future<Result<User>> getUser(String id) =>
  ///     Result.guard(() => api.fetchUser(id));
  /// ```
  static Future<Result<T>> guard<T>(Future<T> Function() action) async {
    try {
      return Result.success(await action());
    } catch (error, stackTrace) {
      SmartBlocConfig.onUncaughtError?.call(error, stackTrace);
      return Result.failure(SmartBlocConfig.failureMapper(error, stackTrace));
    }
  }

  /// Whether this is a [ResultSuccess].
  bool get isSuccess => this is ResultSuccess<T>;

  /// Whether this is a [ResultFailure].
  bool get isFailure => this is ResultFailure<T>;

  /// Returns the value if success, or `null` if failure.
  T? get dataOrNull => fold(onSuccess: (d) => d, onFailure: (_) => null);

  /// Returns [Failure] if failure, or `null` if success.
  Failure? get failureOrNull => fold(onSuccess: (_) => null, onFailure: (f) => f);

  // ── Core ────────────────────────────────────────────────────────

  /// Exhaustive fold — handles both success and failure.
  R fold<R>({
    required R Function(T data) onSuccess,
    required R Function(Failure failure) onFailure,
  }) {
    return switch (this) {
      ResultSuccess(data: final d) => onSuccess(d),
      ResultFailure(failure: final f) => onFailure(f),
    };
  }

  /// Maps the success value; passes failures through unchanged.
  Result<R> map<R>(R Function(T data) transform) {
    return fold(
      onSuccess: (d) => Result.success(transform(d)),
      onFailure: (f) => Result.failure(f),
    );
  }

  /// Chains a fallible transformation on success.
  Result<R> flatMap<R>(Result<R> Function(T data) transform) {
    return fold(onSuccess: transform, onFailure: (f) => Result.failure(f));
  }

  /// Returns the value on success, or the value from [orElse] on failure.
  T getOrElse(T Function() orElse) {
    return fold(onSuccess: (d) => d, onFailure: (_) => orElse());
  }

  /// Returns the value on success, or throws the [Failure] on failure.
  T getOrThrow() {
    return fold(onSuccess: (d) => d, onFailure: (f) => throw f);
  }
}

/// Success variant of [Result].
final class ResultSuccess<T> extends Result<T> {
  final T data;
  const ResultSuccess(this.data);

  @override
  String toString() => 'Result.success($data)';
}

/// Failure variant of [Result].
final class ResultFailure<T> extends Result<T> {
  final Failure failure;
  const ResultFailure(this.failure);

  @override
  String toString() => 'Result.failure($failure)';
}

// ── List Extension ──────────────────────────────────────────────────────────

/// Extensions on [Result] wrapping a [List].
extension ResultListX<T> on Result<List<T>> {
  /// Maps each item in the list on success.
  Result<List<R>> mapItems<R>(R Function(T item) transform) {
    return map((list) => list.map(transform).toList());
  }

  /// Filters list items on success.
  Result<List<T>> where(bool Function(T item) test) {
    return map((list) => list.where(test).toList());
  }
}

// ── Future Extension ────────────────────────────────────────────────────────

/// Extensions on [Future<Result>] for chaining async operations.
extension ResultFutureX<T> on Future<Result<T>> {
  /// Maps a successful result asynchronously.
  Future<Result<R>> thenMap<R>(R Function(T data) transform) async {
    return (await this).map(transform);
  }

  /// Flat-maps a successful result asynchronously.
  Future<Result<R>> thenFlatMap<R>(Result<R> Function(T data) transform) async {
    return (await this).flatMap(transform);
  }
}
