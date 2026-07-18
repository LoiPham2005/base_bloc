import 'package:flutter_bloc/flutter_bloc.dart';

import 'bloc_manager.dart';

/// A typed, parameterized instance factory — smart_bloc's answer to Riverpod's
/// `family`. Each distinct [Arg] maps to its own [BlocManager] scope, so you get
/// one shared instance per argument, auto-disposed when its last lease drops.
///
/// ```dart
/// final productDetail = BlocFamily<ProductCubit, String>(
///   (id) => ProductCubit(id),
///   keepAlive: const Duration(minutes: 2),
/// );
///
/// // Anywhere:
/// final lease = productDetail.acquire(productId);
/// lease.bloc.load();
/// // ...later
/// lease.release();
/// ```
///
/// In widgets, pass the family's [keyFor] result as `scopeKey`:
/// ```dart
/// AutoStateBuilder<ProductCubit, Product>(
///   scopeKey: productDetail.keyFor(id),
///   create: () => ProductCubit(id),
///   onInit: (c) => c.load(),
///   data: (context, product) => ProductView(product),
/// )
/// ```
class BlocFamily<B extends BlocBase<Object?>, Arg> {
  BlocFamily(this._create, {String Function(Arg arg)? keyOf, this.keepAlive})
      : _keyOf = keyOf;

  final B Function(Arg arg) _create;
  final String Function(Arg arg)? _keyOf;

  /// Optional warm-cache duration applied to every acquired instance.
  final Duration? keepAlive;

  /// The [BlocManager] scope key for [arg] (defaults to `'$arg'`). Override
  /// resolution with the `keyOf` constructor argument for complex [Arg] types.
  String keyFor(Arg arg) => _keyOf?.call(arg) ?? '$arg';

  /// Acquires a lease on the instance for [arg], creating it on first use.
  BlocLease<B> acquire(Arg arg) => BlocManager.acquire<B>(
        key: keyFor(arg),
        create: () => _create(arg),
        keepAlive: keepAlive,
      );

  /// The live instance for [arg] without leasing, or `null` if none.
  B? peek(Arg arg) => BlocManager.peek<B>(key: keyFor(arg));
}
