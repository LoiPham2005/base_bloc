import 'package:equatable/equatable.dart';

import '../cubit/smart_cubit.dart';
import '../errors/failures.dart';
import '../errors/result.dart';

/// One page of results plus whether more pages exist.
///
/// ```dart
/// return Result.success(Page(items, hasMore: response.hasNext));
/// return const Result.success(Page.last([])); // definitely no more
/// ```
class Page<E> extends Equatable {
  final List<E> items;
  final bool hasMore;

  const Page(this.items, {this.hasMore = true});

  /// A final page — no more results after this one.
  const Page.last(this.items) : hasMore = false;

  @override
  List<Object?> get props => [items, hasMore];
}

/// A [SmartCubit] specialized for infinite-scroll / load-more lists.
///
/// [loadFirst] loads (or reloads) page one and replaces the list; [loadMore]
/// fetches the next page and **appends** it to the current list — keeping the
/// existing items on screen, tracking [hasMore], and surfacing a load-more
/// failure as a one-shot message instead of wiping the list.
///
/// While [loadMore] runs, `state.isMutating` is `true` (drive a footer spinner
/// with `state.isMutating && cubit.hasMore`).
///
/// ```dart
/// class FeedCubit extends SmartPaginatedCubit<Post> {
///   FeedCubit(this._repo);
///   final FeedRepository _repo;
///   int _page = 1;
///
///   Future<void> load() {
///     _page = 1;
///     return loadFirst(() => _repo.page(_page));
///   }
///
///   Future<void> more() => loadMore(() => _repo.page(++_page));
/// }
/// ```
abstract class SmartPaginatedCubit<E> extends SmartCubit<List<E>> {
  SmartPaginatedCubit([super.initialState]);

  bool _hasMore = true;
  bool _loadingMore = false;

  /// Whether the last loaded page reported more results.
  bool get hasMore => _hasMore;

  /// Whether a [loadMore] call is currently in flight.
  bool get isLoadingMore => _loadingMore;

  /// Loads (or reloads) the first page, replacing the list. Resets [hasMore].
  Future<List<E>?> loadFirst(
    Future<Result<Page<E>>> Function() action, {
    bool keepPreviousData = true,
  }) {
    _hasMore = true;
    return queryWith<Page<E>>(
      action: action,
      map: (page) {
        _hasMore = page.hasMore;
        return page.items;
      },
      keepPreviousData: keepPreviousData,
    );
  }

  /// Fetches and appends the next page. No-op when there is no data yet, no more
  /// pages, a load-more is already running, or a first-page query is in flight.
  Future<void> loadMore(
    Future<Result<Page<E>>> Function() action, {
    String? Function(Failure failure)? errorMessage,
  }) async {
    if (_loadingMore || !_hasMore || state.isLoading || !state.hasData) return;
    _loadingMore = true;
    try {
      await mutate<Page<E>>(
        action: action,
        apply: (current, page) {
          _hasMore = page.hasMore;
          return [...current, ...page.items];
        },
        errorMessage: errorMessage,
      );
    } finally {
      _loadingMore = false;
    }
  }

  @override
  void reset() {
    _hasMore = true;
    _loadingMore = false;
    super.reset();
  }
}
