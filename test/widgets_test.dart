import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_bloc/smart_bloc.dart';

class ListCubit extends SmartCubit<List<String>> {
  ListCubit();

  Future<void> load(Future<Result<List<String>>> Function() action) => query(action: action);
}

class LabelCubit extends SmartCubit<String> {
  final String label;
  LabelCubit(this.label) : super(BaseState.data(label));
}

void main() {
  setUp(BlocManager.disposeAll);
  tearDown(BlocManager.disposeAll);

  group('AutoStateBuilder', () {
    testWidgets('default loading, then data', (tester) async {
      final gate = Completer<Result<List<String>>>();

      await tester.pumpWidget(MaterialApp(
        home: AutoStateBuilder<ListCubit, List<String>>(
          create: ListCubit.new,
          onInit: (c) => c.load(() => gate.future),
          data: (context, items) => Column(
            children: [for (final item in items) Text(item)],
          ),
        ),
      ));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      gate.complete(const Result.success(['apple', 'banana']));
      await tester.pumpAndSettle();

      expect(find.text('apple'), findsOneWidget);
      expect(find.text('banana'), findsOneWidget);
    });

    testWidgets('default error UI retries via cubit.refresh', (tester) async {
      var calls = 0;

      await tester.pumpWidget(MaterialApp(
        home: AutoStateBuilder<ListCubit, List<String>>(
          create: ListCubit.new,
          onInit: (c) => c.load(() async {
            calls++;
            return calls == 1
                ? const Result.failure(NetworkFailure())
                : const Result.success(['ok']);
          }),
          data: (context, items) => Text(items.join(',')),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('No internet connection'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('ok'), findsOneWidget);
      expect(calls, 2);
    });

    testWidgets('empty builder intercepts blank collections', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: AutoStateBuilder<ListCubit, List<String>>(
          create: ListCubit.new,
          onInit: (c) => c.load(() async => const Result.success([])),
          data: (context, items) => Text('items:${items.length}'),
          empty: (context) => const Text('nothing here'),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('nothing here'), findsOneWidget);
    });

    testWidgets('stale data stays visible under refresh indicator', (tester) async {
      late ListCubit cubit;

      await tester.pumpWidget(MaterialApp(
        home: AutoStateBuilder<ListCubit, List<String>>(
          create: ListCubit.new,
          onInit: (c) {
            cubit = c;
            c.load(() async => const Result.success(['old']));
          },
          data: (context, items) => Text(items.join(',')),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('old'), findsOneWidget);

      final gate = Completer<Result<List<String>>>();
      unawaited(cubit.load(() => gate.future));
      await tester.pump(); // deliver the loading emit to BlocBuilder
      await tester.pump(); // rebuild + start the indicator's animation frame

      expect(find.text('old'), findsOneWidget); // previous data still shown
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      gate.complete(const Result.success(['new']));
      await tester.pumpAndSettle();
      expect(find.text('new'), findsOneWidget);
    });
  });

  group('AutoBloc lease lifecycle', () {
    testWidgets('REGRESSION v1: scopeKey change swaps the lease cleanly',
        (tester) async {
      Widget page(String scope) => MaterialApp(
            home: AutoBlocBuilder<LabelCubit, BaseState<String>>(
              scopeKey: scope,
              create: () => LabelCubit(scope),
              builder: (context, cubit, state) => Text(state.data ?? '?'),
            ),
          );

      await tester.pumpWidget(page('a'));
      expect(find.text('a'), findsOneWidget);
      final first = BlocManager.peek<LabelCubit>(key: 'a')!;

      await tester.pumpWidget(page('b'));
      expect(find.text('b'), findsOneWidget);

      // v1: old instance leaked under 'a' and 'b' ref-count went negative.
      expect(first.isClosed, isTrue);
      expect(BlocManager.peek<LabelCubit>(key: 'a'), isNull);
      expect(BlocManager.peek<LabelCubit>(key: 'b'), isNotNull);

      final snapshot = BlocManager.debugSnapshot;
      expect(snapshot.length, 1);
      expect(snapshot.values.single.refs, 1);
    });

    testWidgets('instance is shared across widgets and closed with the last one',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Column(
          children: [
            AutoBlocBuilder<LabelCubit, BaseState<String>>(
              create: () => LabelCubit('x'),
              builder: (context, cubit, state) => Text('1:${state.data}'),
            ),
            AutoBlocBuilder<LabelCubit, BaseState<String>>(
              create: () => LabelCubit('x'),
              builder: (context, cubit, state) => Text('2:${state.data}'),
            ),
          ],
        ),
      ));

      expect(BlocManager.debugSnapshot.values.single.refs, 2);
      final cubit = BlocManager.peek<LabelCubit>()!;

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(cubit.isClosed, isTrue);
      expect(BlocManager.debugSnapshot, isEmpty);
    });
  });

  group('UiMessageListener', () {
    testWidgets('delivers identical consecutive messages (REGRESSION v1)',
        (tester) async {
      final received = <UiMessage>[];
      late LabelCubit cubit;

      await tester.pumpWidget(MaterialApp(
        home: AutoBlocProvider<LabelCubit>(
          create: () => LabelCubit('x'),
          onInit: (c) => cubit = c,
          child: Builder(
            builder: (context) => UiMessageListener<LabelCubit>(
              onMessage: (context, message) => received.add(message),
              child: const SizedBox(),
            ),
          ),
        ),
      ));

      cubit.emitErrorMessage('same error');
      cubit.emitErrorMessage('same error');
      await tester.pump();

      expect(received, hasLength(2)); // v1 state-listener showed only one
    });

    testWidgets('default handler shows a themed snackbar', (tester) async {
      late LabelCubit cubit;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AutoBlocProvider<LabelCubit>(
            create: () => LabelCubit('x'),
            onInit: (c) => cubit = c,
            child: Builder(
              builder: (context) => const UiMessageListener<LabelCubit>(
                child: SizedBox(),
              ),
            ),
          ),
        ),
      ));

      cubit.emitSuccessMessage('Saved!');
      await tester.pump(); // deliver stream event
      await tester.pump(); // show snackbar animation frame

      expect(find.text('Saved!'), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
    });
  });
}
