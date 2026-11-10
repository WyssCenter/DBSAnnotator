/// Crash-safe, order-preserving writes: `File.writeAsString` truncates before
/// writing, and two un-awaited calls to one path can interleave.
library;

import 'dart:async';
import 'dart:io';

/// Holds every write until it completes, so a test can keep a save running.
Future<void>? debugWriteGate;

/// Atomically replace [path]'s contents: write `<path>.tmp`, then rename it
/// over [path], so a reader sees the old contents or the new, never a mixture.
/// The rename is retried with backoff (on Windows a reader, antivirus or the
/// indexer can hold the target) and never deletes it, so `.tmp` survives too.
Future<void> writeStringAtomic(String path, String contents) async {
  final gate = debugWriteGate;
  if (gate != null) await gate;
  final tmp = File('$path.tmp');
  await tmp.writeAsString(contents, flush: true);
  var delay = const Duration(milliseconds: 15);
  for (var attempt = 0; ; attempt++) {
    try {
      await tmp.rename(path);
      return;
    } on FileSystemException {
      if (attempt >= 5) rethrow;
      await Future<void>.delayed(delay);
      delay *= 2;
    }
  }
}

/// Serialises [writeStringAtomic] calls so overlapping saves cannot interleave.
class SafeFileWriter {
  Future<void> _chain = Future<void>.value();

  bool get isBusy => _busy > 0;
  int _busy = 0;

  Future<void> write(String path, String contents) {
    _busy++;
    final next = _chain.then((_) => writeStringAtomic(path, contents));
    // Swallowed on the chain only: one failure must not poison later saves.
    _chain = next.then((_) {}, onError: (_) {});
    return next.whenComplete(() => _busy--);
  }

  Future<void> get settled => _chain;
}
