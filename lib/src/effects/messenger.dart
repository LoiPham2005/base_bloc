import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'ui_message.dart';

/// One-shot [UiMessage] channel for a bloc/cubit, separate from state.
///
/// State is a *value* (deduplicated, replayed to new subscribers); UI feedback
/// like snackbars and toasts is an *event* (fire once, never replay, identical
/// events may repeat). Mixing the two into state causes the classic bugs:
/// a repeated identical error shows no second snackbar, and rebuilding a page
/// replays an old "Saved!" toast. This mixin keeps them apart.
///
/// `SmartCubit`/`SmartBloc` mix this in; pair with `UiMessageListener` in the
/// widget tree. Closed automatically with the bloc.
mixin UiMessenger<S> on BlocBase<S> {
  final StreamController<UiMessage> _messages = StreamController<UiMessage>.broadcast();

  /// One-shot UI messages emitted by this bloc. Broadcast; no replay.
  Stream<UiMessage> get uiMessages => _messages.stream;

  /// Emits a one-shot [UiMessage]. Silently ignored after [close].
  void emitMessage(UiMessage message) {
    if (!_messages.isClosed) _messages.add(message);
  }

  /// Shortcut for [emitMessage] with [UiMessage.success].
  void emitSuccessMessage(String text) => emitMessage(UiMessage.success(text));

  /// Shortcut for [emitMessage] with [UiMessage.error].
  void emitErrorMessage(String text) => emitMessage(UiMessage.error(text));

  @override
  Future<void> close() {
    _messages.close();
    return super.close();
  }
}

/// Typed one-shot effect channel for domain-specific effects (navigation,
/// dialogs, haptics, ...) beyond simple messages.
///
/// ```dart
/// sealed class AuthEffect {}
/// class GoHome extends AuthEffect {}
///
/// class AuthCubit extends SmartCubit<User> with BlocEffects<BaseState<User>, AuthEffect> {
///   Future<void> signIn() => mutate(
///     action: () => repo.signIn(),
///     onSuccess: (_) => emitEffect(GoHome()),
///   );
/// }
/// ```
///
/// Consume with `EffectListener<AuthCubit, AuthEffect>`.
mixin BlocEffects<S, E> on BlocBase<S> {
  final StreamController<E> _effects = StreamController<E>.broadcast();

  /// One-shot effects emitted by this bloc. Broadcast; no replay.
  Stream<E> get effects => _effects.stream;

  /// Emits a one-shot effect. Silently ignored after [close].
  void emitEffect(E effect) {
    if (!_effects.isClosed) _effects.add(effect);
  }

  @override
  Future<void> close() {
    _effects.close();
    return super.close();
  }
}
