import 'package:equatable/equatable.dart';

import '../errors/failures.dart';

/// Kind of a [UiMessage] — drives default styling in `UiMessageListener`.
enum UiMessageKind { success, error, info, warning }

/// A one-shot, fire-and-forget UI notification (snackbar/toast payload).
///
/// Delivered over a broadcast stream (`UiMessenger.uiMessages`), **not** the
/// state. Two consecutive identical messages therefore both arrive — unlike
/// state-based snackbars, which bloc deduplicates because equal states are
/// never re-emitted.
class UiMessage extends Equatable {
  final String text;
  final UiMessageKind kind;

  /// The originating failure, when [kind] is [UiMessageKind.error].
  final Failure? failure;

  const UiMessage(this.text, {this.kind = UiMessageKind.info, this.failure});

  const UiMessage.success(this.text)
      : kind = UiMessageKind.success,
        failure = null;

  const UiMessage.error(this.text, {this.failure}) : kind = UiMessageKind.error;

  const UiMessage.warning(this.text)
      : kind = UiMessageKind.warning,
        failure = null;

  bool get isError => kind == UiMessageKind.error;

  @override
  List<Object?> get props => [text, kind, failure];

  @override
  String toString() => 'UiMessage.${kind.name}($text)';
}
