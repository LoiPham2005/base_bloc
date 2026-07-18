// Copyright (c) 2026, smart_bloc contributors.
// SPDX-License-Identifier: MIT

/// A powerful, codegen-free BLoC/Cubit layer for Flutter.
///
/// ## Features
/// - `BaseState` — sealed union state (initial/loading/data/error) with
///   non-nullable data by construction and native pattern matching
/// - `SmartCubit` & `SmartBloc` — typed query/mutate with stale-result
///   protection, mutation tracking, and one-shot `UiMessage`s
/// - `BlocManager` — generation-safe, ref-counted lifecycle (autoDispose +
///   family without codegen)
/// - `AutoStateBuilder` — data-first screen builder with global defaults
/// - `AutoBlocBuilder`/`AutoBlocConsumer`/`AutoBlocListener`/`AutoBlocSelector`
///   /`AutoBlocProvider` — lease-managed widget integration
/// - `UiMessageListener` & `EffectListener` — one-shot effects done right
/// - `Result` & `Failure` — typed domain errors without exceptions
///
/// ## Quick start
/// ```dart
/// class CounterCubit extends SmartCubit<int> {
///   CounterCubit() : super(const BaseState.data(0));
///   void increment() => setData((state.data ?? 0) + 1);
/// }
/// ```
library smart_bloc;

// Re-export flutter_bloc for convenience (BlocProvider, context.read, ...).
export 'package:flutter_bloc/flutter_bloc.dart';

export 'src/bloc/smart_bloc.dart';
export 'src/core/config.dart';
export 'src/core/exec.dart' show BlocSubscriptions, ExecMode, SmartExec;
export 'src/cubit/smart_cubit.dart';
export 'src/effects/messenger.dart';
export 'src/effects/ui_message.dart';
export 'src/errors/failures.dart';
export 'src/errors/result.dart';
export 'src/manager/bloc_manager.dart';
export 'src/state/base_state.dart';
export 'src/widgets/auto_bloc.dart';
export 'src/widgets/defaults.dart';
export 'src/widgets/effect_listener.dart';
export 'src/widgets/state_builder.dart';
