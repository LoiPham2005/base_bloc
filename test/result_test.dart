import 'package:flutter_test/flutter_test.dart';
import 'package:smart_bloc/smart_bloc.dart';

void main() {
  group('Result', () {
    test('fold dispatches by variant', () {
      expect(
        const Result<int>.success(1).fold(onSuccess: (d) => 'ok$d', onFailure: (_) => 'err'),
        'ok1',
      );
      expect(
        const Result<int>.failure(NetworkFailure())
            .fold(onSuccess: (d) => 'ok', onFailure: (f) => f.code),
        'NETWORK_ERROR',
      );
    });

    test('map / flatMap chain on success and pass failures through', () {
      expect(const Result<int>.success(2).map((d) => d * 2).dataOrNull, 4);
      expect(
        const Result<int>.failure(TimeoutFailure()).map((d) => d * 2).failureOrNull,
        const TimeoutFailure(),
      );
      expect(
        const Result<int>.success(2)
            .flatMap((d) => d > 0 ? Result.success('$d') : const Result.failure(ServerFailure()))
            .dataOrNull,
        '2',
      );
    });

    test('getOrElse / getOrThrow', () {
      expect(const Result<int>.success(3).getOrElse(() => 0), 3);
      expect(const Result<int>.failure(ServerFailure()).getOrElse(() => 0), 0);
      expect(
        () => const Result<int>.failure(ServerFailure()).getOrThrow(),
        throwsA(isA<ServerFailure>()),
      );
    });

    test('guard wraps thrown errors via SmartBlocConfig.failureMapper', () async {
      final ok = await Result.guard(() async => 5);
      expect(ok.dataOrNull, 5);

      final thrown = await Result.guard<int>(() async => throw StateError('x'));
      expect(thrown.failureOrNull, isA<UnknownFailure>());
      expect(thrown.failureOrNull!.cause, isA<StateError>());

      final passthrough =
          await Result.guard<int>(() async => throw const NetworkFailure());
      expect(passthrough.failureOrNull, const NetworkFailure());
    });

    test('list and future extensions', () async {
      expect(
        const Result<List<int>>.success([1, 2, 3]).mapItems((e) => e * 2).dataOrNull,
        [2, 4, 6],
      );
      expect(
        const Result<List<int>>.success([1, 2, 3]).where((e) => e.isOdd).dataOrNull,
        [1, 3],
      );
      final mapped = await Future.value(const Result<int>.success(1)).thenMap((d) => d + 1);
      expect(mapped.dataOrNull, 2);
    });
  });

  group('Failure', () {
    test('equality ignores cause/stackTrace', () {
      final a = UnknownFailure.from(StateError('x'), StackTrace.current);
      final b = UnknownFailure(message: a.message);
      expect(a, b);
    });

    test('isRetryable / needsReLogin / retryAfter heuristics', () {
      expect(const NetworkFailure().isRetryable, isTrue);
      expect(const ServerFailure(statusCode: 503).isRetryable, isTrue);
      expect(const ServerFailure(statusCode: 404).isRetryable, isFalse);
      expect(
        const AuthFailure(message: 'expired', type: AuthFailureType.tokenExpired).needsReLogin,
        isTrue,
      );
      expect(
        const AuthFailure(message: 'forbidden', type: AuthFailureType.unauthorized).needsReLogin,
        isFalse,
      );
      expect(const TimeoutFailure().retryAfter, const Duration(seconds: 3));
    });
  });
}
