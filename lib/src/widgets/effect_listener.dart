import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../effects/messenger.dart';
import '../effects/ui_message.dart';
import 'defaults.dart';

/// Listens to a bloc's one-shot [UiMessage] stream and presents each message
/// (default: themed snackbar via [SmartBlocDefaults.showMessage]).
///
/// Because messages ride a broadcast stream instead of state, two identical
/// consecutive errors both show — the classic "second snackbar never appears"
/// state-listener bug cannot happen here.
///
/// ```dart
/// UiMessageListener<PostCubit>(
///   child: PostListPage(),
/// )
/// ```
///
/// Resolves the bloc from context (`context.read<B>()`) unless [bloc] is given.
class UiMessageListener<B extends UiMessenger<Object?>> extends StatefulWidget {
  /// Explicit source; defaults to `context.read<B>()`.
  final B? bloc;

  /// Message handler; defaults to [SmartBlocDefaults.showMessage].
  final void Function(BuildContext context, UiMessage message)? onMessage;

  final Widget child;

  const UiMessageListener({super.key, this.bloc, this.onMessage, required this.child});

  @override
  State<UiMessageListener<B>> createState() => _UiMessageListenerState<B>();
}

class _UiMessageListenerState<B extends UiMessenger<Object?>>
    extends State<UiMessageListener<B>> {
  StreamSubscription<UiMessage>? _subscription;
  B? _bloc;

  void _subscribe(B bloc) {
    _bloc = bloc;
    _subscription?.cancel();
    _subscription = bloc.uiMessages.listen((message) {
      if (!mounted) return;
      (widget.onMessage ?? SmartBlocDefaults.showMessage)(context, message);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bloc = widget.bloc ?? context.read<B>();
    if (!identical(bloc, _bloc)) _subscribe(bloc);
  }

  @override
  void didUpdateWidget(UiMessageListener<B> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bloc = widget.bloc ?? context.read<B>();
    if (!identical(bloc, _bloc)) _subscribe(bloc);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Listens to a bloc's typed one-shot [BlocEffects.effects] stream — for
/// navigation, dialogs, and other domain effects.
///
/// ```dart
/// EffectListener<AuthCubit, AuthEffect>(
///   onEffect: (context, effect) => switch (effect) {
///     GoHome() => context.go('/home'),
///   },
///   child: const LoginForm(),
/// )
/// ```
class EffectListener<B extends BlocEffects<Object?, E>, E> extends StatefulWidget {
  /// Explicit source; defaults to `context.read<B>()`.
  final B? bloc;

  final void Function(BuildContext context, E effect) onEffect;

  final Widget child;

  const EffectListener({super.key, this.bloc, required this.onEffect, required this.child});

  @override
  State<EffectListener<B, E>> createState() => _EffectListenerState<B, E>();
}

class _EffectListenerState<B extends BlocEffects<Object?, E>, E>
    extends State<EffectListener<B, E>> {
  StreamSubscription<E>? _subscription;
  B? _bloc;

  void _subscribe(B bloc) {
    _bloc = bloc;
    _subscription?.cancel();
    _subscription = bloc.effects.listen((effect) {
      if (!mounted) return;
      widget.onEffect(context, effect);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bloc = widget.bloc ?? context.read<B>();
    if (!identical(bloc, _bloc)) _subscribe(bloc);
  }

  @override
  void didUpdateWidget(EffectListener<B, E> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bloc = widget.bloc ?? context.read<B>();
    if (!identical(bloc, _bloc)) _subscribe(bloc);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
