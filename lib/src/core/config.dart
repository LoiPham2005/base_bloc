import '../errors/failures.dart';

/// Global, pure-Dart configuration for smart_bloc's core layer.
///
/// Widget-level defaults (loading/error builders, snackbars) live in
/// `SmartBlocDefaults` in the widgets layer.
class SmartBlocConfig {
  SmartBlocConfig._();

  /// Converts an uncaught error thrown inside a `query`/`mutate` action into a
  /// [Failure].
  ///
  /// The default returns the error unchanged when it is already a [Failure],
  /// otherwise wraps it in [UnknownFailure]. Override to translate your own
  /// exception types (Dio errors, platform exceptions, ...):
  ///
  /// ```dart
  /// SmartBlocConfig.failureMapper = (error, stack) => switch (error) {
  ///   DioException(:final response?) =>
  ///     ServerFailure(message: 'HTTP ${response.statusCode}', statusCode: response.statusCode),
  ///   Failure() => error,
  ///   _ => UnknownFailure.from(error, stack),
  /// };
  /// ```
  static Failure Function(Object error, StackTrace stackTrace) failureMapper =
      defaultFailureMapper;

  /// Observability hook invoked (before [failureMapper]) whenever an action
  /// throws instead of returning a `Result.failure`.
  ///
  /// Wire this to Crashlytics/Sentry so programming errors that get converted
  /// into failure states never disappear silently.
  static void Function(Object error, StackTrace stackTrace)? onUncaughtError;

  /// The default [failureMapper].
  static Failure defaultFailureMapper(Object error, StackTrace stackTrace) {
    if (error is Failure) return error;
    return UnknownFailure.from(error, stackTrace);
  }
}
