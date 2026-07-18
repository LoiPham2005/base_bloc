import 'package:equatable/equatable.dart';

/// Abstract base class for domain failures.
///
/// All failure types should extend this.
///
/// ```dart
/// class UserFailure extends Failure {
///   const UserFailure({required super.message});
/// }
/// ```
abstract class Failure extends Equatable {
  /// Human-readable error message for display or logging.
  final String message;

  /// Optional machine-readable error code (e.g. `'NOT_FOUND'`, `'UNAUTHORIZED'`).
  final String? code;

  /// HTTP status code if applicable.
  final int? statusCode;

  /// The original thrown object, when this failure wraps an exception.
  ///
  /// Excluded from equality.
  final Object? cause;

  /// Stack trace captured where [cause] was thrown. Excluded from equality.
  final StackTrace? stackTrace;

  const Failure({
    required this.message,
    this.code,
    this.statusCode,
    this.cause,
    this.stackTrace,
  });

  @override
  List<Object?> get props => [message, code, statusCode];

  @override
  String toString() => message;
}

// ── Network ────────────────────────────────────────────────────────────────

/// No network connection.
class NetworkFailure extends Failure {
  const NetworkFailure({super.message = 'No internet connection', super.code = 'NETWORK_ERROR'});
}

/// Request timed out.
class TimeoutFailure extends Failure {
  const TimeoutFailure({super.message = 'Request timed out', super.code = 'TIMEOUT'});
}

/// Request was explicitly cancelled.
class CancelledFailure extends Failure {
  const CancelledFailure({super.message = 'Request cancelled', super.code = 'CANCELLED'});
}

// ── Server ─────────────────────────────────────────────────────────────────

/// Server-side error (5xx).
class ServerFailure extends Failure {
  /// Set when server is under maintenance.
  final DateTime? maintenanceEndTime;

  /// Set when server is rate-limiting; indicates when to retry.
  final Duration? retryAfter;

  const ServerFailure({
    super.message = 'Server error',
    super.code,
    super.statusCode,
    this.maintenanceEndTime,
    this.retryAfter,
  });

  bool get isMaintenance => maintenanceEndTime != null;
  bool get isRateLimited => retryAfter != null;

  @override
  List<Object?> get props => [...super.props, maintenanceEndTime, retryAfter];
}

// ── Auth ───────────────────────────────────────────────────────────────────

/// Authentication or authorisation error.
class AuthFailure extends Failure {
  final AuthFailureType type;

  const AuthFailure({
    required super.message,
    this.type = AuthFailureType.unauthenticated,
    super.code,
    super.statusCode,
  });

  bool get needsReLogin => type != AuthFailureType.unauthorized;

  @override
  List<Object?> get props => [...super.props, type];
}

/// Subtypes for [AuthFailure].
enum AuthFailureType {
  unauthenticated, // 401
  unauthorized, // 403
  tokenExpired,
  refreshFailed,
}

// ── Data ───────────────────────────────────────────────────────────────────

/// Data/validation error (4xx).
class DataFailure extends Failure {
  final DataFailureType type;

  /// Per-field validation errors.
  final Map<String, String>? fieldErrors;

  /// Global (non-field) validation errors.
  final List<String>? globalErrors;

  const DataFailure({
    required super.message,
    this.type = DataFailureType.unknown,
    this.fieldErrors,
    this.globalErrors,
    super.code,
    super.statusCode,
  });

  /// Returns the first available error message.
  String get firstError {
    if (fieldErrors?.isNotEmpty == true) return fieldErrors!.values.first;
    if (globalErrors?.isNotEmpty == true) return globalErrors!.first;
    return message;
  }

  /// Returns the error message for a specific field, if any.
  String? fieldError(String field) => fieldErrors?[field];

  @override
  List<Object?> get props => [...super.props, type, fieldErrors, globalErrors];
}

/// Subtypes for [DataFailure].
enum DataFailureType {
  notFound, // 404
  validation, // 400, 422
  conflict, // 409
  unknown,
}

// ── Unknown ────────────────────────────────────────────────────────────────

/// Catchall for unexpected errors.
class UnknownFailure extends Failure {
  const UnknownFailure({
    super.message = 'An unexpected error occurred',
    super.code = 'UNKNOWN',
    super.cause,
    super.stackTrace,
  });

  /// Wraps a caught [error], preserving it as [cause].
  factory UnknownFailure.from(Object error, [StackTrace? stackTrace]) =>
      UnknownFailure(message: error.toString(), cause: error, stackTrace: stackTrace);
}

// ── Extension ──────────────────────────────────────────────────────────────

/// Convenience extensions on [Failure].
extension FailureX on Failure {
  bool get isNetwork => this is NetworkFailure || this is TimeoutFailure;
  bool get isAuth => this is AuthFailure;
  bool get isServer => this is ServerFailure;
  bool get isCancelled => this is CancelledFailure;

  /// Whether this failure warrants an automatic retry.
  bool get isRetryable {
    return switch (this) {
      NetworkFailure() || TimeoutFailure() => true,
      ServerFailure(:final isRateLimited, :final statusCode) =>
        isRateLimited || (statusCode ?? 0) >= 500,
      _ => false,
    };
  }

  /// Whether the user should be redirected to login.
  bool get needsReLogin {
    return switch (this) {
      AuthFailure(:final needsReLogin) => needsReLogin,
      _ => false,
    };
  }

  /// Suggested retry delay, if applicable.
  Duration? get retryAfter {
    return switch (this) {
      ServerFailure(:final retryAfter) => retryAfter,
      NetworkFailure() || TimeoutFailure() => const Duration(seconds: 3),
      _ => null,
    };
  }
}
