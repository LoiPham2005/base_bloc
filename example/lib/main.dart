import 'package:flutter/material.dart';
import 'package:smart_bloc/smart_bloc.dart';

// ── Domain ─────────────────────────────────────────────────────────────────

class Post {
  final int id;
  final String title;
  const Post({required this.id, required this.title});
}

/// Simulated repository — every call returns a [Result], never throws.
class PostRepository {
  final _posts = <Post>[
    const Post(id: 1, title: 'Hello smart_bloc'),
    const Post(id: 2, title: 'Sealed BaseState, no codegen'),
    const Post(id: 3, title: 'One-shot messages done right'),
  ];

  Future<Result<List<Post>>> getAll() =>
      Result.guard(() async {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        return List<Post>.unmodifiable(_posts);
      });

  Future<Result<int>> delete(int id) =>
      Result.guard(() async {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        if (id == 1) throw const ServerFailure(message: 'Cannot delete the pinned post');
        _posts.removeWhere((p) => p.id == id);
        return id;
      });
}

// ── Cubit ──────────────────────────────────────────────────────────────────

class PostCubit extends SmartCubit<List<Post>> {
  PostCubit(this._repo);
  final PostRepository _repo;

  /// Query: emits loading → data | error, keeping old data during reloads.
  Future<void> load() => query(action: _repo.getAll);

  /// Mutation: independent of the data type, keeps the list on screen,
  /// removes the row optimistically-safely, and shows a one-shot snackbar.
  Future<void> delete(int id) => mutate<int>(
        action: () => _repo.delete(id),
        apply: (posts, removedId) => posts.where((p) => p.id != removedId).toList(),
        successMessage: 'Post deleted',
      );
}

// ── App ────────────────────────────────────────────────────────────────────

void main() {
  // Apply the design system to every default placeholder once (optional).
  SmartBlocDefaults.empty = (context) => const Center(child: Text('No posts yet'));
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'smart_bloc example',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const PostPage(),
    );
  }
}

class PostPage extends StatelessWidget {
  const PostPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('smart_bloc example')),
      // AutoStateBuilder leases the cubit (auto-closed on dispose), wires the
      // default loading/error/empty UIs, and surfaces one-shot messages.
      body: AutoStateBuilder<PostCubit, List<Post>>(
        create: () => PostCubit(PostRepository()),
        onCreate: (cubit) => cubit.load(), // once per instance
        listenMessages: true,
        data: (context, posts) => RefreshIndicator(
          onRefresh: () => context.read<PostCubit>().refresh(),
          child: ListView.builder(
            itemCount: posts.length,
            itemBuilder: (context, index) {
              final post = posts[index];
              return ListTile(
                leading: CircleAvatar(child: Text('${post.id}')),
                title: Text(post.title),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => context.read<PostCubit>().delete(post.id),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
