import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_bloc/smart_bloc.dart';

class FeedCubit extends SmartPaginatedCubit<int> {}

void main() {
  late FeedCubit cubit;

  setUp(() => cubit = FeedCubit());
  tearDown(() => cubit.close());

  test('loadFirst replaces the list and tracks hasMore', () async {
    await cubit.loadFirst(() async => const Result.success(Page([1, 2])));

    expect(cubit.state.data, [1, 2]);
    expect(cubit.hasMore, isTrue);
  });

  test('loadMore appends the next page', () async {
    await cubit.loadFirst(() async => const Result.success(Page([1, 2])));
    await cubit.loadMore(() async => const Result.success(Page([3, 4])));

    expect(cubit.state.data, [1, 2, 3, 4]);
    expect(cubit.hasMore, isTrue);
  });

  test('stops at the last page and ignores further loadMore', () async {
    await cubit.loadFirst(() async => const Result.success(Page([1, 2])));
    await cubit.loadMore(() async => const Result.success(Page.last([3])));

    expect(cubit.state.data, [1, 2, 3]);
    expect(cubit.hasMore, isFalse);

    var called = false;
    await cubit.loadMore(() async {
      called = true;
      return const Result.success(Page([9]));
    });
    expect(called, isFalse); // no-op once hasMore is false
    expect(cubit.state.data, [1, 2, 3]);
  });

  test('loadMore sets mutating and keeps the list on screen', () async {
    await cubit.loadFirst(() async => const Result.success(Page([1])));
    final gate = Completer<Result<Page<int>>>();

    final pending = cubit.loadMore(() => gate.future);
    expect(cubit.isLoadingMore, isTrue);
    expect(cubit.state.isMutating, isTrue);
    expect(cubit.state.data, [1]); // existing items stay visible

    gate.complete(const Result.success(Page([2])));
    await pending;
    expect(cubit.state.data, [1, 2]);
    expect(cubit.state.isMutating, isFalse);
    expect(cubit.isLoadingMore, isFalse);
  });

  test('loadMore failure keeps the list and emits a one-shot message', () async {
    await cubit.loadFirst(() async => const Result.success(Page([1, 2])));
    final messages = <UiMessage>[];
    final sub = cubit.uiMessages.listen(messages.add);

    await cubit.loadMore(() async => const Result.failure(NetworkFailure()));
    await pumpEventQueue();

    expect(cubit.state.data, [1, 2]); // not wiped
    expect(cubit.state, isA<DataState<List<int>>>());
    expect(messages.single.isError, isTrue);
    expect(cubit.hasMore, isTrue); // unchanged on failure

    await sub.cancel();
  });

  test('loadMore is a no-op before any data', () async {
    var called = false;
    await cubit.loadMore(() async {
      called = true;
      return const Result.success(Page([1]));
    });
    expect(called, isFalse);
    expect(cubit.state, isA<InitialState<List<int>>>());
  });

  test('reset restores pagination flags', () async {
    await cubit.loadFirst(() async => const Result.success(Page.last([1])));
    expect(cubit.hasMore, isFalse);

    cubit.reset();
    expect(cubit.hasMore, isTrue);
    expect(cubit.state, isA<InitialState<List<int>>>());
  });
}
