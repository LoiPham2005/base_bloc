import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/config.dart';
import '../state/base_state.dart';

/// Derived, read-only state computed from one or more source blocs — smart_bloc's
/// answer to Riverpod's derived providers (`ref.watch` composition).
///
/// `compute` is run once immediately and again whenever ANY source emits. The
/// result is published as a [DataState]; if `compute` throws, it becomes an
/// [ErrorState] (via [SmartBlocConfig.failureMapper]). Equal results are not
/// re-emitted (Equatable), so downstream widgets only rebuild on real changes.
///
/// Dependencies are **explicit** (you list the sources) rather than tracked
/// automatically — this is the deliberate trade-off vs Riverpod's implicit
/// graph: no magic, no build step, but you declare what you depend on.
///
/// Inline:
/// ```dart
/// final total = SmartComputed<int>(
///   sources: [cartCubit],
///   compute: () => cartCubit.state.dataOrNull?.total ?? 0,
/// );
/// ```
///
/// Or as a named type:
/// ```dart
/// class CartTotalCubit extends SmartComputed<int> {
///   CartTotalCubit(CartCubit cart)
///       : super(
///           sources: [cart],
///           compute: () => cart.state.dataOrNull?.total ?? 0,
///         );
/// }
/// ```
class SmartComputed<T> extends Cubit<BaseState<T>> {
  SmartComputed({
    required List<BlocBase<Object?>> sources,
    required T Function() compute,
  })  : _compute = compute,
        super(InitialState<T>()) {
    _recompute();
    _subscriptions = [
      for (final source in sources) source.stream.listen((_) => _recompute()),
    ];
  }

  final T Function() _compute;
  late final List<StreamSubscription<dynamic>> _subscriptions;

  /// Forces a recomputation (rarely needed — sources trigger this automatically).
  void recompute() => _recompute();

  void _recompute() {
    if (isClosed) return;
    try {
      emit(DataState<T>(_compute()));
    } catch (error, stackTrace) {
      SmartBlocConfig.onUncaughtError?.call(error, stackTrace);
      emit(ErrorState<T>(SmartBlocConfig.failureMapper(error, stackTrace)));
    }
  }

  @override
  Future<void> close() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    return super.close();
  }
}
