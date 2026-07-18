import 'package:flutter_test/flutter_test.dart';
import 'package:smart_bloc/smart_bloc.dart';

class CounterCubit extends SmartCubit<int> {
  CounterCubit() : super(const BaseState.data(0));
}

void main() {
  setUp(BlocManager.disposeAll);
  tearDown(() {
    BlocManager.disposeAll();
    BlocManager.clearFactory();
  });

  group('acquire / release', () {
    test('shares one instance per type and closes at zero leases', () {
      final a = BlocManager.acquire<CounterCubit>(create: CounterCubit.new);
      final b = BlocManager.acquire<CounterCubit>(create: CounterCubit.new);

      expect(identical(a.bloc, b.bloc), isTrue);

      a.release();
      expect(a.bloc.isClosed, isFalse); // still leased by b

      b.release();
      expect(b.bloc.isClosed, isTrue);
      expect(BlocManager.debugSnapshot, isEmpty);
    });

    test('release is idempotent — double release cannot underflow', () {
      final a = BlocManager.acquire<CounterCubit>(create: CounterCubit.new);
      final b = BlocManager.acquire<CounterCubit>(create: CounterCubit.new);

      a.release();
      a.release(); // v1 would decrement again and close b's instance
      a.release();

      expect(b.bloc.isClosed, isFalse);
      expect(a.isReleased, isTrue);
      b.release();
      expect(b.bloc.isClosed, isTrue);
    });

    test('scope keys hold independent instances (family)', () {
      final tab1 = BlocManager.acquire<CounterCubit>(key: 'tab1', create: CounterCubit.new);
      final tab2 = BlocManager.acquire<CounterCubit>(key: 'tab2', create: CounterCubit.new);

      expect(identical(tab1.bloc, tab2.bloc), isFalse);

      tab1.release();
      expect(tab1.bloc.isClosed, isTrue);
      expect(tab2.bloc.isClosed, isFalse);
      tab2.release();
    });

    test('uses the registered DI factory when no create is given', () {
      BlocManager.setFactory(<T extends BlocBase<Object?>>() {
        if (T == CounterCubit) return CounterCubit() as T;
        throw StateError('unknown type $T');
      });

      final lease = BlocManager.acquire<CounterCubit>();
      expect(lease.bloc.state.data, 0);
      lease.release();
    });
  });

  group('generation safety (REGRESSION v1)', () {
    test('externally closed instance is replaced; stale leases are inert', () async {
      final l1 = BlocManager.acquire<CounterCubit>(create: CounterCubit.new);
      final l2 = BlocManager.acquire<CounterCubit>(create: CounterCubit.new);

      await l1.bloc.close(); // closed outside the manager

      // Next acquire replaces the dead instance with a new generation.
      final l3 = BlocManager.acquire<CounterCubit>(create: CounterCubit.new);
      expect(identical(l3.bloc, l1.bloc), isFalse);
      expect(l3.bloc.isClosed, isFalse);

      // v1: these releases decremented the NEW instance's count and closed it
      // while still in use.
      l1.release();
      l2.release();
      expect(l3.bloc.isClosed, isFalse);

      l3.release();
      expect(l3.bloc.isClosed, isTrue);
    });

    test('disposeAll makes all outstanding leases inert', () {
      final l1 = BlocManager.acquire<CounterCubit>(create: CounterCubit.new);
      BlocManager.disposeAll();
      expect(l1.bloc.isClosed, isTrue);

      final l2 = BlocManager.acquire<CounterCubit>(create: CounterCubit.new);
      l1.release(); // stale generation — must not touch l2's instance
      expect(l2.bloc.isClosed, isFalse);
      l2.release();
    });
  });

  group('peek', () {
    test('returns the live instance without leasing', () {
      expect(BlocManager.peek<CounterCubit>(), isNull);

      final lease = BlocManager.acquire<CounterCubit>(create: CounterCubit.new);
      expect(identical(BlocManager.peek<CounterCubit>(), lease.bloc), isTrue);

      lease.release();
      expect(BlocManager.peek<CounterCubit>(), isNull);
    });
  });
}
