# smart_bloc

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![style: flutter_lints](https://img.shields.io/badge/style-flutter__lints-4BC0F5.svg)](https://pub.dev/packages/flutter_lints)

A powerful, **codegen-free** BLoC/Cubit layer for Flutter. It keeps the parts of
BLoC that scale (explicit state, testability, `flutter_bloc` tooling) and adds
the ergonomics people reach for Riverpod's generator to get — typed async state,
auto-dispose, `family`-style scoping, safe mutations — **without `build_runner`**.

```dart
class PostCubit extends SmartCubit<List<Post>> {
  PostCubit(this._repo);
  final PostRepository _repo;

  Future<void> load() => query(action: _repo.getAll);

  Future<void> delete(int id) => mutate<int>(
        action: () => _repo.delete(id),
        apply: (posts, id) => posts.where((p) => p.id != id).toList(),
        successMessage: 'Post deleted',
      );
}
```

```dart
AutoStateBuilder<PostCubit, List<Post>>(
  create: () => PostCubit(repo),
  onInit: (c) => c.load(),
  listenMessages: true,                       // one-shot snackbars
  data: (context, posts) => PostListView(posts),
  // loading / error / empty come from SmartBlocDefaults — override per-call if needed
)
```

That is a full screen: loading spinner, error view with retry, empty state,
delete-with-undo-safe list mutation, and a "Post deleted" snackbar — no state
classes, no `build_runner`, no manual `dispose`.

---

## Why this over Riverpod + codegen?

| | smart_bloc | riverpod + riverpod_generator |
|---|---|---|
| Build step | **None** — pure Dart/Flutter | `build_runner watch` always running |
| Async state | `BaseState<T>` sealed union, **data is non-nullable** in `DataState` | `AsyncValue<T>` |
| Auto-dispose | `BlocManager` leases (ref-counted) | `@riverpod` autoDispose |
| Scoped/param instances | `scopeKey` (`family` without codegen) | `family` (codegen) |
| Mutations | first-class `mutate()` — data stays on screen, errors are one-shot | manual `AsyncNotifier` + `ref.listen` |
| One-shot effects | `UiMessage` / `Effect` streams (snackbars/nav that don't replay) | manual `ref.listen` plumbing |
| Tooling | full `flutter_bloc` + `bloc` devtools/observer | Riverpod devtools |

If your team already thinks in blocs, or you simply don't want a code generator
in the loop, smart_bloc gives you the modern feature set on top of the mature
`flutter_bloc` runtime.

> It is a **layer on `flutter_bloc`, not a replacement** — every `BlocProvider`,
> `context.read`, observer and devtool keeps working.

---

## Installation

```yaml
dependencies:
  smart_bloc: ^0.2.0
```

```dart
import 'package:smart_bloc/smart_bloc.dart'; // re-exports flutter_bloc too
```

---

## Core concepts

### `BaseState<T>` — a sealed union, not a status enum

Four variants; the type system guarantees data is present when it says it is:

```dart
sealed class BaseState<T> {}
class InitialState<T> // nothing yet
class LoadingState<T> // .previousData (keep stale data during refresh)
class DataState<T>    // .data is a NON-NULLABLE T
class ErrorState<T>   // .failure + .previousData
```

Match with native Dart 3 patterns (exhaustive, no `data as T` casts):

```dart
switch (state) {
  InitialState()                    => const SizedBox(),
  LoadingState(:final previousData) => previousData == null
      ? const CircularProgressIndicator()
      : StaleList(previousData),
  DataState(:final data)            => PostList(data),   // data is List<Post>, never null
  ErrorState(:final failure)        => ErrorView(failure.message),
}
```

…or the `when`/`maybeWhen` sugar:

```dart
state.when(
  initial: () => const SizedBox(),
  loading: (previous) => const Spinner(),
  data:    (posts) => PostList(posts),
  error:   (failure, previous) => ErrorView(failure.message),
  empty:   () => const Text('No posts'), // optional: intercepts empty List/Map
);
```

Handy accessors: `state.dataOrNull`, `hasData`, `isLoading`, `isRefreshing`
(loading **with** previous data), `isMutating`, `failureOrNull`, `errorMessage`.

### `SmartCubit<T>` — query & mutate

**`query`** produces the screen's data. Each call supersedes the previous one and
**a stale response that finishes late is dropped**, so fast-typing search boxes
and rapid refreshes never flicker old data back:

```dart
Future<void> search(String term) =>
    query(action: () => repo.search(term)); // latest wins automatically
```

**`mutate<R>`** runs a side effect. It is deliberately different from a query:

- its result type `R` is independent of `T` — `mutate<void>` needs no casts and
  **cannot corrupt the data state** (this was a real crash in v1);
- on failure the current data **stays on screen**; the error is delivered as a
  one-shot message, not by replacing the state;
- `state.mutating` is `true` while it runs, so you can disable a submit button
  in place;
- double-taps are ignored by default (`ExecMode.droppable`); switch to
  `restartable` (latest wins) or `concurrent` as needed.

```dart
Future<void> save(Draft draft) => mutate<Post>(
      action: () => repo.save(draft),
      apply: (posts, saved) => [...posts, saved], // update data from the result
      successMessage: 'Saved',
      errorMessage: (f) => f.isNetwork ? 'You are offline' : f.message,
    );
```

Other helpers: `refresh()` (re-run the last query), `setData`, `updateData`
(optimistic), `reset`, `cancelPending`, and `listenTo(otherBloc, ...)` for
auto-cancelled cross-bloc composition.

### One-shot effects — snackbars & navigation that don't replay

State-based snackbars have two classic bugs: the **same** error twice shows only
one snackbar (equal states aren't re-emitted), and rebuilding a screen replays an
old "Saved!". smart_bloc separates *events* from *state*:

```dart
// In a cubit: mutate(successMessage: ...) emits automatically, or do it manually:
emitSuccessMessage('Copied to clipboard');
emitErrorMessage('Something went wrong');
```

```dart
// In the tree — identical consecutive messages both show:
UiMessageListener<PostCubit>(child: PostListPage())
// AutoStateBuilder(listenMessages: true) wires this for you.
```

For navigation/dialogs use a typed effect channel:

```dart
class AuthCubit extends SmartCubit<User> with BlocEffects<BaseState<User>, AuthEffect> {
  Future<void> signIn() => mutate(action: repo.signIn, onSuccess: (_) => emitEffect(GoHome()));
}

EffectListener<AuthCubit, AuthEffect>(
  onEffect: (context, e) => switch (e) { GoHome() => context.go('/home') },
  child: const LoginForm(),
)
```

### `BlocManager` — auto-dispose & family, no codegen

Widgets lease instances; the instance closes when the **last** lease is released.
`scopeKey` gives you independent instances of one type (Riverpod's `family`):

```dart
AutoBlocProvider<AuthCubit>(create: () => AuthCubit(repo), child: AppShell())

AutoStateBuilder<TabCubit, TabData>(
  scopeKey: 'tab-$id',                 // one cubit per tab, auto-closed
  create: () => TabCubit(id),
  onInit: (c) => c.load(),
  data: (context, data) => TabView(data),
)
```

Manual leases when you need them (idempotent, generation-safe — double-release
and external close can't corrupt the ref-count, a v1 bug):

```dart
final lease = BlocManager.acquire<CartCubit>(create: CartCubit.new);
lease.bloc.addItem(item);
lease.release();
```

Register a DI factory once and drop the inline `create`:

```dart
BlocManager.setFactory(<T extends BlocBase<Object?>>() => getIt<T>());
final auth = BlocManager.acquire<AuthCubit>(); // from GetIt
```

### `Result<T>` & `Failure`

Type-safe errors without exceptions. `Result.guard` turns a throwing call into a
`Result` (like `AsyncValue.guard`):

```dart
Future<Result<User>> getUser(String id) => Result.guard(() => api.fetchUser(id));

result.fold(onSuccess: (u) => ..., onFailure: (f) => ...);
result.map(...).flatMap(...).getOrElse(() => User.guest());
```

Structured `Failure` hierarchy (`NetworkFailure`, `TimeoutFailure`,
`ServerFailure`, `AuthFailure`, `DataFailure`, `UnknownFailure`) with helpers like
`failure.isRetryable`, `failure.needsReLogin`, `failure.retryAfter`. Translate
your own exceptions globally:

```dart
SmartBlocConfig.failureMapper = (error, stack) => switch (error) {
  DioException(:final response?) =>
    ServerFailure(message: 'HTTP ${response.statusCode}', statusCode: response.statusCode),
  Failure() => error,
  _ => UnknownFailure.from(error, stack),
};
SmartBlocConfig.onUncaughtError =
    (error, stack) => FirebaseCrashlytics.instance.recordError(error, stack);
```

---

## Widgets at a glance

| Widget | Use |
|---|---|
| `AutoStateBuilder<C, T>` | Full screen for a `SmartCubit` — data UI + default loading/error/empty/refresh |
| `AutoBlocBuilder<B, S>` | Lease + `BlocBuilder`, `bloc` passed to the builder |
| `AutoBlocConsumer` / `AutoBlocListener` / `AutoBlocSelector` | Lease + the matching `flutter_bloc` widget |
| `AutoBlocProvider<B>` | Lease + provide to descendants, no UI |
| `MultiAutoBlocProvider` | Nest providers without deep indentation |
| `UiMessageListener<B>` / `EffectListener<B, E>` | Present one-shot messages / typed effects |

Customize every default once via `SmartBlocDefaults` (`loading`, `error`,
`empty`, `initial`, `showMessage`).

---

## Event-based `SmartBloc`

Prefer events? `SmartBloc<E, T>` is fully generic (state is `BaseState<T>`, not
`Object?`) with the same `query`/`mutate`:

```dart
class PostBloc extends SmartBloc<PostEvent, List<Post>> {
  PostBloc(this._repo) {
    on<LoadPosts>((e, emit) => query(emit, action: _repo.getAll));
    on<DeletePost>((e, emit) => mutate<int>(
          emit,
          action: () => _repo.delete(e.id),
          apply: (posts, id) => posts.where((p) => p.id != id).toList(),
          successMessage: 'Deleted',
        ));
  }
  final PostRepository _repo;
}
```

---

## Migrating from 0.1.x

- `BaseCubit`/`BaseBloc` → `SmartCubit`/`SmartBloc`.
- `execute(...)` splits into `query(...)` (fetch) and `mutate(...)` (side effect).
- `BaseState.success/loaded/empty` + `BaseStatus` → sealed `DataState`/etc.;
  emptiness is a UI concern (`when(empty:)`, `AutoStateBuilder.empty`).
- `BlocManager.get`/`release` → `acquire()` returning a `BlocLease`.
- `BlocListeners.snackBar` → `UiMessageListener` / one-shot messages.

See [CHANGELOG.md](CHANGELOG.md) for the full list, including the v1 correctness
bugs this release fixes.

---

## License

[MIT](LICENSE) © 2026 smart_bloc contributors
