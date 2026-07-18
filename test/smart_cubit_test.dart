import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_bloc/smart_bloc.dart';

class TestCubit extends SmartCubit<List<int>> {
  TestCubit([super.initialState]);
}

void main() {
  late TestCubit cubit;

  setUp(() {
    cubit = TestCubit();
    SmartBlocConfig.failureMapper = SmartBlocConfig.defaultFailureMapper;
    SmartBlocConfig.onUncaughtError = null;
  });

  tearDown(() => cubit.close());

  group('query', () {
    test('emits loading then data', () async {
      final states = <BaseState<List<int>>>[];
      final sub = cubit.stream.listen(states.add);

      await cubit.query(action: () async => const Result.success([1, 2]));
      await pumpEventQueue(); // let the stream deliver the final emit

      expect(states, [
        const LoadingState<List<int>>(),
        const DataState<List<int>>([1, 2]),
      ]);
      await sub.cancel();
    });

    test('emits error keeping previous data', () async {
      await cubit.query(action: () async => const Result.success([1]));
      await cubit.query(action: () async => const Result.failure(NetworkFailure()));

      expect(cubit.state, isA<ErrorState<List<int>>>());
      expect(cubit.state.dataOrNull, [1]); // stale data still visible
      expect(cubit.state.failureOrNull, const NetworkFailure());
    });

    test('keeps previous data during reload by default', () async {
      await cubit.query(action: () async => const Result.success([1]));
      final gate = Completer<Result<List<int>>>();
      final pending = cubit.query(action: () => gate.future);

      expect(cubit.state, isA<LoadingState<List<int>>>());
      expect(cubit.state.dataOrNull, [1]);
      expect(cubit.state.isRefreshing, isTrue);

      gate.complete(const Result.success([2]));
      await pending;
      expect(cubit.state.dataOrNull, [2]);
    });

    test('REGRESSION v1: stale response never overwrites newer data', () async {
      final slow = Completer<Result<List<int>>>();
      final fast = Completer<Result<List<int>>>();

      final first = cubit.query(action: () => slow.future);
      final second = cubit.query(action: () => fast.future);

      fast.complete(const Result.success([2]));
      await second;
      expect(cubit.state.dataOrNull, [2]);

      slow.complete(const Result.success([1])); // finishes late
      expect(await first, isNull); // dropped
      expect(cubit.state.dataOrNull, [2]); // v1 would show [1]
    });

    test('silent query skips the loading emission', () async {
      await cubit.query(action: () async => const Result.success([1]));
      final states = <BaseState<List<int>>>[];
      final sub = cubit.stream.listen(states.add);

      await cubit.query(
        action: () async => const Result.success([9]),
        silent: true,
      );
      await pumpEventQueue(); // let the stream deliver the emit

      expect(states, [const DataState<List<int>>([9])]);
      await sub.cancel();
    });

    test('thrown errors become ErrorState via failureMapper and hit the hook',
        () async {
      Object? seen;
      SmartBlocConfig.onUncaughtError = (error, _) => seen = error;

      await cubit.query(action: () async => throw StateError('boom'));

      expect(cubit.state, isA<ErrorState<List<int>>>());
      final failure = cubit.state.failureOrNull!;
      expect(failure, isA<UnknownFailure>());
      expect(failure.cause, isA<StateError>());
      expect(seen, isA<StateError>());
    });

    test('refresh re-runs the last query keeping previous data', () async {
      var calls = 0;
      await cubit.query(action: () async {
        calls++;
        return Result.success([calls]);
      });
      await cubit.refresh();

      expect(calls, 2);
      expect(cubit.state.dataOrNull, [2]);
      expect(cubit.canRefresh, isTrue);
    });

    test('refresh is a no-op before any query', () async {
      expect(cubit.canRefresh, isFalse);
      await cubit.refresh();
      expect(cubit.state, isA<InitialState<List<int>>>());
    });

    test('queryWith maps raw API type without casts', () async {
      await cubit.queryWith<String>(
        action: () async => const Result.success('1,2,3'),
        map: (raw) => raw.split(',').map(int.parse).toList(),
      );
      expect(cubit.state.dataOrNull, [1, 2, 3]);
    });
  });

  group('mutate', () {
    test('REGRESSION v1: void mutation succeeds without corrupting state',
        () async {
      await cubit.query(action: () async => const Result.success([1, 2, 3]));

      final messages = <UiMessage>[];
      final sub = cubit.uiMessages.listen(messages.add);
      var successRan = false;

      await cubit.mutate<void>(
        action: () async => const Result<void>.success(null),
        successMessage: 'Deleted',
        onSuccess: (_) => successRan = true,
      );
      await Future<void>.delayed(Duration.zero);

      // v1 turned this into ErrorState("type 'Null' is not a subtype ...")
      expect(cubit.state, const DataState<List<int>>([1, 2, 3]));
      expect(successRan, isTrue);
      expect(messages, [const UiMessage.success('Deleted')]);
      await sub.cancel();
    });

    test('failure keeps data on screen and emits a one-shot error message',
        () async {
      await cubit.query(action: () async => const Result.success([1]));
      final messages = <UiMessage>[];
      final sub = cubit.uiMessages.listen(messages.add);

      await cubit.mutate<void>(
        action: () async => const Result.failure(ServerFailure()),
      );
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state, const DataState<List<int>>([1])); // not ErrorState
      expect(messages.single.isError, isTrue);
      expect(messages.single.failure, const ServerFailure());
      await sub.cancel();
    });

    test('identical consecutive error messages are both delivered', () async {
      await cubit.query(action: () async => const Result.success([1]));
      final messages = <UiMessage>[];
      final sub = cubit.uiMessages.listen(messages.add);

      await cubit.mutate<void>(
        action: () async => const Result.failure(ServerFailure()),
      );
      await cubit.mutate<void>(
        action: () async => const Result.failure(ServerFailure()),
      );
      await Future<void>.delayed(Duration.zero);

      expect(messages, hasLength(2)); // state-based listeners showed only one
      await sub.cancel();
    });

    test('tracks mutating flag through the data state', () async {
      await cubit.query(action: () async => const Result.success([1]));
      final gate = Completer<Result<void>>();

      final pending = cubit.mutate<void>(action: () => gate.future);
      expect(cubit.state.isMutating, isTrue);
      expect(cubit.state.dataOrNull, [1]); // data stays on screen
      expect(cubit.hasMutationInFlight, isTrue);

      gate.complete(const Result<void>.success(null));
      await pending;
      expect(cubit.state.isMutating, isFalse);
      expect(cubit.hasMutationInFlight, isFalse);
    });

    test('droppable mode ignores double-taps', () async {
      await cubit.query(action: () async => const Result.success([1]));
      final gate = Completer<Result<int>>();
      var calls = 0;

      final first = cubit.mutate<int>(action: () {
        calls++;
        return gate.future;
      });
      final second = cubit.mutate<int>(action: () async {
        calls++;
        return const Result.success(2);
      });

      expect(await second, isNull); // dropped immediately
      gate.complete(const Result.success(1));
      expect(await first, 1);
      expect(calls, 1);
    });

    test('restartable mode drops the stale result', () async {
      await cubit.query(action: () async => const Result.success([0]));
      final slow = Completer<Result<int>>();

      final first = cubit.mutate<int>(
        action: () => slow.future,
        apply: (current, result) => [...current, result],
        mode: ExecMode.restartable,
      );
      final second = cubit.mutate<int>(
        action: () async => const Result.success(2),
        apply: (current, result) => [...current, result],
        mode: ExecMode.restartable,
      );

      await second;
      expect(cubit.state.dataOrNull, [0, 2]);

      slow.complete(const Result.success(1));
      expect(await first, isNull);
      expect(cubit.state.dataOrNull, [0, 2]); // stale apply skipped
    });

    test('apply updates data from the mutation result', () async {
      await cubit.query(action: () async => const Result.success([1, 2, 3]));

      await cubit.mutate<int>(
        action: () async => const Result.success(2),
        apply: (current, removedId) =>
            current.where((e) => e != removedId).toList(),
      );

      expect(cubit.state.dataOrNull, [1, 3]);
    });
  });

  group('helpers', () {
    test('setData / updateData', () async {
      cubit.setData([5]);
      expect(cubit.state, const DataState<List<int>>([5]));
      cubit.updateData((current) => [...current, 6]);
      expect(cubit.state.dataOrNull, [5, 6]);
    });

    test('updateData is a no-op without data', () {
      cubit.updateData((current) => [...current, 1]);
      expect(cubit.state, isA<InitialState<List<int>>>());
    });

    test('reset cancels pending work and returns to initial', () async {
      final gate = Completer<Result<List<int>>>();
      final pending = cubit.query(action: () => gate.future);

      cubit.reset();
      gate.complete(const Result.success([1]));
      expect(await pending, isNull);
      expect(cubit.state, isA<InitialState<List<int>>>());
    });

    test('emissions after close are silently dropped', () async {
      final gate = Completer<Result<List<int>>>();
      final pending = cubit.query(action: () => gate.future);

      await cubit.close();
      gate.complete(const Result.success([1]));
      expect(await pending, isNull); // no StateError from emit-after-close
    });

    test('listenTo reacts to another bloc and auto-cancels on close', () async {
      final source = TestCubit();
      final seen = <List<int>?>[];
      cubit.listenTo<BaseState<List<int>>>(source, (s) => seen.add(s.dataOrNull));

      source.setData([1]);
      await Future<void>.delayed(Duration.zero);
      expect(seen, [
        [1]
      ]);

      await cubit.close();
      source.setData([2]);
      await Future<void>.delayed(Duration.zero);
      expect(seen, hasLength(1)); // subscription cancelled with the cubit
      await source.close();
    });
  });
}
