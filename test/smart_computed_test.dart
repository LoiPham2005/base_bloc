import 'package:flutter_test/flutter_test.dart';
import 'package:smart_bloc/smart_bloc.dart';

class CounterCubit extends SmartCubit<int> {
  CounterCubit([int initial = 0]) : super(BaseState.data(initial));
}

void main() {
  setUp(() {
    SmartBlocConfig.failureMapper = SmartBlocConfig.defaultFailureMapper;
    SmartBlocConfig.onUncaughtError = null;
  });

  test('computes immediately from sources', () {
    final a = CounterCubit(3);
    final doubled = SmartComputed<int>(sources: [a], compute: () => (a.state.data ?? 0) * 2);

    expect(doubled.state.data, 6);
    doubled.close();
    a.close();
  });

  test('recomputes when any source changes', () async {
    final a = CounterCubit(1);
    final b = CounterCubit(2);
    final sum = SmartComputed<int>(
      sources: [a, b],
      compute: () => (a.state.data ?? 0) + (b.state.data ?? 0),
    );

    expect(sum.state.data, 3);

    a.setData(10);
    await pumpEventQueue();
    expect(sum.state.data, 12);

    b.setData(20);
    await pumpEventQueue();
    expect(sum.state.data, 30);

    await sum.close();
    await a.close();
    await b.close();
  });

  test('equal recomputes are not re-emitted', () async {
    final a = CounterCubit(2);
    final parity = SmartComputed<bool>(
      sources: [a],
      compute: () => (a.state.data ?? 0).isEven,
    );
    final emissions = <BaseState<bool>>[];
    final sub = parity.stream.listen(emissions.add);

    a.setData(4); // still even → computed value unchanged
    await pumpEventQueue();
    expect(emissions, isEmpty); // no re-emit for an equal result

    a.setData(5); // now odd → changes
    await pumpEventQueue();
    expect(emissions, [const DataState<bool>(false)]);

    await sub.cancel();
    await parity.close();
    await a.close();
  });

  test('throwing compute becomes ErrorState', () async {
    final a = CounterCubit(1);
    final risky = SmartComputed<int>(
      sources: [a],
      compute: () {
        final v = a.state.data ?? 0;
        if (v == 0) throw StateError('zero');
        return 100 ~/ v;
      },
    );
    expect(risky.state.data, 100);

    a.setData(0);
    await pumpEventQueue();
    expect(risky.state, isA<ErrorState<int>>());
    expect(risky.state.failureOrNull, isA<UnknownFailure>());

    await risky.close();
    await a.close();
  });

  test('stops recomputing after close (subscriptions cancelled)', () async {
    final a = CounterCubit(1);
    final derived = SmartComputed<int>(sources: [a], compute: () => a.state.data ?? 0);

    await derived.close();
    a.setData(999); // must not throw emit-after-close
    await pumpEventQueue();
    expect(derived.isClosed, isTrue);
    await a.close();
  });
}
