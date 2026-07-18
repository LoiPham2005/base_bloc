import 'package:flutter_test/flutter_test.dart';
import 'package:smart_bloc/smart_bloc.dart';

void main() {
  group('BaseState variants', () {
    test('factories create the right variants', () {
      expect(const BaseState<int>.initial(), isA<InitialState<int>>());
      expect(const BaseState<int>.loading(), isA<LoadingState<int>>());
      expect(const BaseState<int>.data(1), isA<DataState<int>>());
      expect(
        const BaseState<int>.error(ServerFailure()),
        isA<ErrorState<int>>(),
      );
    });

    test('DataState.data is non-nullable and never a cast', () {
      const state = DataState<int>(5);
      final int value = state.data; // compiles as non-null T
      expect(value, 5);
    });

    test('dataOrNull prefers current data, falls back to previous', () {
      expect(const DataState<int>(5).dataOrNull, 5);
      expect(const LoadingState<int>(previous: 3).dataOrNull, 3);
      expect(
        const ErrorState<int>(ServerFailure(), previous: 7).dataOrNull,
        7,
      );
      expect(const InitialState<int>().dataOrNull, isNull);
      expect(const LoadingState<int>().dataOrNull, isNull);
    });

    test('equality is value-based per variant, including deep collections', () {
      expect(const DataState<int>(1), const DataState<int>(1));
      expect(
        const DataState<List<int>>([1, 2]),
        const DataState<List<int>>([1, 2]),
      );
      expect(const DataState<int>(1), isNot(const DataState<int>(2)));
      expect(
        const DataState<int>(1, mutating: true),
        isNot(const DataState<int>(1)),
      );
      expect(const InitialState<int>(), isNot(const LoadingState<int>()));
    });

    test('status getters', () {
      const loading = LoadingState<int>(previous: 1);
      expect(loading.isLoading, isTrue);
      expect(loading.isRefreshing, isTrue);
      expect(const LoadingState<int>().isRefreshing, isFalse);
      expect(const DataState<int>(1).isData, isTrue);
      expect(const DataState<int>(1).isSuccess, isTrue); // v1 alias
      expect(
        const ErrorState<int>(ServerFailure()).isFailure, // v1 alias
        isTrue,
      );
    });
  });

  group('transitions', () {
    test('toLoading keeps data as previousData', () {
      final next = const DataState<int>(9).toLoading();
      expect(next, isA<LoadingState<int>>());
      expect(next.dataOrNull, 9);
    });

    test('toError keeps data as previousData', () {
      final next = const DataState<int>(9).toError(const NetworkFailure());
      expect(next, isA<ErrorState<int>>());
      expect(next.dataOrNull, 9);
      expect(next.failureOrNull, const NetworkFailure());
    });

    test('withMutating preserves variant and payload', () {
      final mutating = const DataState<int>(4).withMutating(true);
      expect(mutating, const DataState<int>(4, mutating: true));
      expect(mutating.withMutating(false), const DataState<int>(4));
      final loading = const LoadingState<int>(previous: 2).withMutating(true);
      expect(loading.isMutating, isTrue);
      expect(loading.dataOrNull, 2);
    });

    test('mapData converts payload across variants', () {
      expect(
        const DataState<int>(2).mapData((d) => 'v$d'),
        const DataState<String>('v2'),
      );
      expect(
        const LoadingState<int>(previous: 2).mapData((d) => 'v$d').dataOrNull,
        'v2',
      );
      expect(
        const InitialState<int>().mapData((d) => 'v$d'),
        isA<InitialState<String>>(),
      );
    });
  });

  group('when / maybeWhen', () {
    test('when matches every variant with typed payloads', () {
      String describe(BaseState<int> s) => s.when(
            initial: () => 'initial',
            loading: (prev) => 'loading:$prev',
            data: (d) => 'data:$d',
            error: (f, prev) => 'error:${f.message}:$prev',
          );
      expect(describe(const InitialState()), 'initial');
      expect(describe(const LoadingState(previous: 1)), 'loading:1');
      expect(describe(const DataState(2)), 'data:2');
      expect(
        describe(const ErrorState(ServerFailure(), previous: 3)),
        'error:Server error:3',
      );
    });

    test('when(empty:) intercepts blank collections without rewriting state', () {
      const state = DataState<List<int>>([]);
      final label = state.when(
        initial: () => 'initial',
        loading: (_) => 'loading',
        data: (d) => 'data',
        error: (_, __) => 'error',
        empty: () => 'empty',
      );
      expect(label, 'empty');
      expect(state.dataOrNull, isEmpty); // typed empty list preserved
      // Without the empty handler the data branch runs.
      final noEmpty = state.when(
        initial: () => 'initial',
        loading: (_) => 'loading',
        data: (d) => 'data:${d.length}',
        error: (_, __) => 'error',
      );
      expect(noEmpty, 'data:0');
    });

    test('maybeWhen falls back to orElse', () {
      expect(
        const DataState<int>(1).maybeWhen(orElse: () => 'other'),
        'other',
      );
      expect(
        const DataState<int>(1).maybeWhen(data: (d) => 'd$d', orElse: () => 'x'),
        'd1',
      );
    });
  });
}
