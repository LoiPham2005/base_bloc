import 'package:flutter_test/flutter_test.dart';
import 'package:smart_bloc/smart_bloc.dart';

sealed class CounterEvent extends BaseEvent {}

class Load extends CounterEvent {}

class Remove extends CounterEvent {
  final int value;
  Remove(this.value);
  @override
  List<Object?> get props => [value];
}

class CounterBloc extends SmartBloc<CounterEvent, List<int>> {
  CounterBloc() {
    on<Load>((event, emit) => query(emit, action: () async => const Result.success([1, 2, 3])));
    on<Remove>((event, emit) => mutate<int>(
          emit,
          action: () async => Result.success(event.value),
          apply: (current, removed) => current.where((e) => e != removed).toList(),
          successMessage: 'Removed',
        ));
  }
}

void main() {
  test('SmartBloc is fully generic — state is BaseState<List<int>>, not Object?', () async {
    final bloc = CounterBloc();
    bloc.add(Load());
    await Future<void>.delayed(Duration.zero);

    // No casts: dataOrNull is List<int>?
    final List<int>? data = bloc.state.dataOrNull;
    expect(data, [1, 2, 3]);
    await bloc.close();
  });

  test('mutation via event applies result and emits one-shot message', () async {
    final bloc = CounterBloc();
    final messages = <UiMessage>[];
    final sub = bloc.uiMessages.listen(messages.add);

    bloc.add(Load());
    await Future<void>.delayed(Duration.zero);
    bloc.add(Remove(2));
    await Future<void>.delayed(Duration.zero);

    expect(bloc.state.dataOrNull, [1, 3]);
    expect(messages, [const UiMessage.success('Removed')]);

    await sub.cancel();
    await bloc.close();
  });
}
