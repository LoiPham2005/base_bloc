import 'package:fake_async/fake_async.dart';
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
    BlocManager.clearOverrides();
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

    test('acquiring an already-live instance needs no factory at all', () {
      final owner = BlocManager.acquire<CounterCubit>(create: CounterCubit.new);

      // A child widget sharing the parent's instance has nothing to create.
      final consumer = BlocManager.acquire<CounterCubit>();
      expect(identical(consumer.bloc, owner.bloc), isTrue);
      expect(BlocManager.debugSnapshot.values.single.refs, 2);

      consumer.release();
      expect(owner.bloc.isClosed, isFalse);
      owner.release();
      expect(owner.bloc.isClosed, isTrue);
    });

    test('throws a clear error when nothing exists and nothing can create', () {
      expect(
        () => BlocManager.acquire<CounterCubit>(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('no live instance'),
          ),
        ),
      );
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

  group('keepAlive', () {
    test('keeps instance warm after last release, closes after the TTL', () {
      fakeAsync((async) {
        final lease = BlocManager.acquire<CounterCubit>(
          create: CounterCubit.new,
          keepAlive: const Duration(minutes: 1),
        );
        final bloc = lease.bloc;

        lease.release();
        expect(bloc.isClosed, isFalse); // warm, not closed
        expect(BlocManager.debugSnapshot['CounterCubit']?.keptWarm, isTrue);

        async.elapse(const Duration(seconds: 59));
        expect(bloc.isClosed, isFalse);

        async.elapse(const Duration(seconds: 2));
        expect(bloc.isClosed, isTrue); // closed after grace period
        expect(BlocManager.debugSnapshot, isEmpty);
      });
    });

    test('re-acquire within the window reuses the warm instance', () {
      fakeAsync((async) {
        final first = BlocManager.acquire<CounterCubit>(
          create: CounterCubit.new,
          keepAlive: const Duration(minutes: 1),
        );
        final bloc = first.bloc;
        first.release();

        async.elapse(const Duration(seconds: 30));
        final again = BlocManager.acquire<CounterCubit>(create: CounterCubit.new);
        expect(identical(again.bloc, bloc), isTrue); // reused, not re-created
        expect(bloc.isClosed, isFalse);

        // Timer was cancelled — instance survives past the original TTL.
        async.elapse(const Duration(minutes: 5));
        expect(bloc.isClosed, isFalse);

        again.release();
        async.elapse(const Duration(minutes: 2));
        expect(bloc.isClosed, isTrue);
      });
    });
  });

  group('onCreate / onClose', () {
    test('onCreate fires once per instance, not per acquire', () {
      var creates = 0;
      final l1 = BlocManager.acquire<CounterCubit>(
        create: CounterCubit.new,
        onCreate: (_) => creates++,
      );
      final l2 = BlocManager.acquire<CounterCubit>(
        create: CounterCubit.new,
        onCreate: (_) => creates++,
      );

      expect(creates, 1); // shared instance → onCreate once
      l1.release();
      l2.release();
    });

    test('onClose fires once, right before the instance closes', () {
      final closed = <int?>[];
      final lease = BlocManager.acquire<CounterCubit>(
        create: () => CounterCubit()..setData(7),
        onClose: (c) => closed.add(c.state.data), // instance still open here
      );

      lease.release();
      expect(closed, [7]);
    });

    test('onClose fires after the keepAlive TTL', () {
      fakeAsync((async) {
        var closes = 0;
        final lease = BlocManager.acquire<CounterCubit>(
          create: CounterCubit.new,
          keepAlive: const Duration(minutes: 1),
          onClose: (_) => closes++,
        );
        lease.release();
        expect(closes, 0); // warm

        async.elapse(const Duration(minutes: 2));
        expect(closes, 1);
      });
    });

    test('disposeAll runs onClose for every instance', () {
      var closes = 0;
      BlocManager.acquire<CounterCubit>(create: CounterCubit.new, onClose: (_) => closes++);
      BlocManager.disposeAll();
      expect(closes, 1);
    });
  });

  group('override', () {
    test('injects a fake regardless of create/DI', () {
      BlocManager.override<CounterCubit>(() => CounterCubit()..setData(99));

      final lease = BlocManager.acquire<CounterCubit>(create: CounterCubit.new);
      expect(lease.bloc.state.data, 99); // fake won, not the real create
      lease.release();

      BlocManager.clearOverrides();
      final real = BlocManager.acquire<CounterCubit>(create: CounterCubit.new);
      expect(real.bloc.state.data, 0);
      real.release();
    });
  });

  group('BlocFamily', () {
    test('one instance per arg, shared within an arg', () {
      final family = BlocFamily<CounterCubit, int>((n) => CounterCubit()..setData(n));

      final l1 = family.acquire(1);
      final l2 = family.acquire(2);
      final l1b = family.acquire(1);

      expect(l1.bloc.state.data, 1);
      expect(l2.bloc.state.data, 2);
      expect(identical(l1.bloc, l2.bloc), isFalse); // different arg → different
      expect(identical(l1.bloc, l1b.bloc), isTrue); // same arg → shared

      l1.release();
      expect(l1.bloc.isClosed, isFalse); // still leased by l1b
      l1b.release();
      expect(l1.bloc.isClosed, isTrue);
      l2.release();
    });

    test('custom keyOf resolves complex args', () {
      final family = BlocFamily<CounterCubit, ({int a, int b})>(
        (arg) => CounterCubit()..setData(arg.a + arg.b),
        keyOf: (arg) => '${arg.a}-${arg.b}',
      );
      final lease = family.acquire((a: 2, b: 3));
      expect(lease.bloc.state.data, 5);
      expect(family.keyFor((a: 2, b: 3)), '2-3');
      lease.release();
    });
  });
}
