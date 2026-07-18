# Changelog

## 0.2.0

Ground-up rewrite. Breaking release.

### Fixed (v1 defects)

- **`execute<void>` mutation corrupted state**: `Result<void>` success hit
  `rawData as T`, threw `TypeError`, and was swallowed into a failure state —
  the official README/example flow reported an error for a successful server
  call and never ran `onSuccess`. Mutations no longer touch the data type at
  all (`mutate<R>` is independent of `T`).
- **`when()` crashed on data-less success** (`data as T`). `DataState.data`
  is non-nullable by construction; the crash is unrepresentable now.
- **Broken cancellation**: concurrent `execute` calls shared one
  `_currentOperation` completer — the second call overwrote the first's
  tracking, staleness checks read the wrong completer, and query mode had no
  stale-response protection at all. Replaced with per-call sequence tokens:
  the latest query wins, stale responses are dropped.
- **`BlocManager` ref-count desync**: an instance closed externally reset the
  count while old holders still called `release`, closing the replacement
  instance under active users. Leases are generation-tagged; stale releases
  are inert no-ops.
- **`AutoBloc*` ignored `scopeKey` changes** (no `didUpdateWidget`): the old
  instance leaked and the new key's ref-count was corrupted. Leases now swap
  on scope change.
- **Repeated identical snackbars never showed**: state-based listeners can't
  fire twice for identical consecutive errors (equal states are not
  re-emitted). One-shot `UiMessage`/effect streams replace them.
- `BaseBloc` was typed `BaseState<Object?>` — now `SmartBloc<E, T>` is fully
  generic.
- Empty-list success no longer silently rewrites state to a data-less
  `empty` status; emptiness is a UI concern (`when(empty:)`,
  `AutoStateBuilder.empty`).

### Added

- Sealed `BaseState<T>`: `InitialState` / `LoadingState(previousData)` /
  `DataState(data)` / `ErrorState(failure, previousData)`, `mutating` flag,
  native switch + `when`/`maybeWhen` sugar, `mapData`, `toLoading`/`toError`.
- `SmartCubit<T>` / `SmartBloc<E, T>`: `query` / `queryWith` / `mutate` with
  `ExecMode` (droppable/restartable/concurrent), `refresh()`, `setData`,
  `updateData`, `reset`, `cancelPending`, `listenTo` (cross-bloc
  composition), typed `Failure` callbacks.
- One-shot effects: `UiMessenger.uiMessages` (+ `UiMessage`), typed
  `BlocEffects<S, E>`, `UiMessageListener`, `EffectListener`.
- `BlocManager.acquire` → `BlocLease` (idempotent, generation-tagged
  release), `peek`, `disposeAll`, `debugSnapshot`.
- `AutoStateBuilder<C, T>` — data-first screen builder with global
  `SmartBlocDefaults` (loading/error/empty/initial/snackbar) and automatic
  stale-data + progress overlay during refresh.
- `Result.guard`, `SmartBlocConfig.failureMapper`,
  `SmartBlocConfig.onUncaughtError`; `Failure.cause`/`stackTrace`.

### Removed / renamed

- `BaseCubit`/`BaseBloc` → `SmartCubit`/`SmartBloc` (`execute` →
  `query`/`mutate`).
- `BaseStatus`, `BaseState.success/loaded/empty` factories, `displayMessage`,
  `BlocListeners`, and the raw `BlocManager.get/getWith/release/recreate`
  API (use `acquire`/leases; `setFactory` remains).
- `flutter_bloc` constraint widened to `>=8.1.0 <10.0.0`.

## 0.1.0

* Initial release.
* `BaseState<T>` — unified state with `when`/`maybeWhen` pattern matching.
* `BaseStatus` — 5-value enum covering initial/loading/success/empty/failure.
* `BaseBloc` / `BaseCubit` — auto loading → success/failure with `execute()`.
* `BlocManager` — ref-counted lifecycle with DI-agnostic factory pattern.
* `AutoBlocBuilder`, `AutoBlocListener`, `AutoBlocConsumer`, `AutoBlocSelector`, `AutoBlocProvider`, `MultiAutoBlocProvider` — auto-managed widget suite.
* `BlocListeners` — pre-built `snackBar`, `onError`, `onSuccess` helpers.
* `Result<T>` sealed class — type-safe error handling.
* `Failure` hierarchy — `NetworkFailure`, `TimeoutFailure`, `ServerFailure`, `AuthFailure`, `DataFailure`, `UnknownFailure`.
