import 'package:flutter/material.dart';

import '../effects/ui_message.dart';
import '../errors/failures.dart';

/// Global widget-layer defaults used by `AutoStateBuilder` and
/// `UiMessageListener` when no inline builder is given.
///
/// Override once at startup to apply your design system everywhere:
///
/// ```dart
/// SmartBlocDefaults.loading = (context) => const Center(child: MyShimmer());
/// SmartBlocDefaults.error = (context, failure, retry) =>
///     MyErrorView(message: failure.message, onRetry: retry);
/// ```
class SmartBlocDefaults {
  SmartBlocDefaults._();

  /// Full-screen loading placeholder (no previous data available).
  static Widget Function(BuildContext context) loading =
      (context) => const Center(child: CircularProgressIndicator());

  /// Full-screen error placeholder with a retry affordance.
  static Widget Function(BuildContext context, Failure failure, VoidCallback retry) error =
      (context, failure, retry) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(failure.message, textAlign: TextAlign.center),
                ),
                const SizedBox(height: 16),
                FilledButton.tonal(onPressed: retry, child: const Text('Retry')),
              ],
            ),
          );

  /// Placeholder for a `DataState` holding an empty `Iterable`/`Map`.
  static Widget Function(BuildContext context) empty =
      (context) => const Center(child: Text('No data'));

  /// Placeholder for `InitialState`.
  static Widget Function(BuildContext context) initial =
      (context) => const SizedBox.shrink();

  /// Presents a one-shot [UiMessage]. Default: themed floating [SnackBar].
  static void Function(BuildContext context, UiMessage message) showMessage =
      (context, message) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (message.kind) {
      UiMessageKind.error => (scheme.error, scheme.onError),
      UiMessageKind.success => (scheme.primaryContainer, scheme.onPrimaryContainer),
      UiMessageKind.warning => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      UiMessageKind.info => (scheme.inverseSurface, scheme.onInverseSurface),
    };
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message.text, style: TextStyle(color: foreground)),
          backgroundColor: background,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
  };
}
