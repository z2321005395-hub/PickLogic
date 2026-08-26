import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:picklogic_windows_bridge/picklogic_windows_bridge.dart';

import 'desktop_repository.dart';

/// Visible-item Shell thumbnail loader with a strict in-memory entry bound.
final class DesktopShellThumbnail extends StatefulWidget {
  const DesktopShellThumbnail({
    super.key,
    required this.entry,
    required this.size,
    required this.fallback,
  });

  final BrowseEntry entry;
  final double size;
  final IconData fallback;

  @override
  State<DesktopShellThumbnail> createState() => _DesktopShellThumbnailState();
}

final class _DesktopShellThumbnailState extends State<DesktopShellThumbnail> {
  static final _ShellImageCache _cache = _ShellImageCache(maxEntries: 96);
  late Future<ui.Image?> _image;

  @override
  void initState() {
    super.initState();
    _image = _load();
  }

  @override
  void didUpdateWidget(covariant DesktopShellThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.path != widget.entry.path ||
        oldWidget.size.round() != widget.size.round()) {
      _image = _load();
    }
  }

  Future<ui.Image?> _load() {
    if (widget.entry.isDirectory ||
        widget.entry.path.startsWith('synthetic:')) {
      return Future<ui.Image?>.value(null);
    }
    final requested = widget.size.round().clamp(32, 256);
    return _cache.load(widget.entry.path, requested);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<ui.Image?>(
    future: _image,
    builder: (context, snapshot) {
      final image = snapshot.data;
      if (image == null) {
        return Icon(
          widget.entry.isDirectory ? Icons.folder_outlined : widget.fallback,
          size: widget.size * 0.72,
        );
      }
      return RawImage(
        image: image,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      );
    },
  );
}

final class _ShellImageCache {
  _ShellImageCache({required this.maxEntries});

  final int maxEntries;
  final LinkedHashMap<String, Future<ui.Image?>> _entries =
      LinkedHashMap<String, Future<ui.Image?>>();

  Future<ui.Image?> load(String path, int size) {
    final key = '$path|$size';
    final existing = _entries.remove(key);
    if (existing != null) {
      _entries[key] = existing;
      return existing;
    }
    final pending = _read(path, size);
    _entries[key] = pending;
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    return pending;
  }

  Future<ui.Image?> _read(String path, int size) async {
    try {
      final thumbnail = await const PicklogicWindowsBridge().loadShellThumbnail(
        path,
        size: size,
      );
      if (thumbnail == null) return null;
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        thumbnail.bgraBytes,
        thumbnail.width,
        thumbnail.height,
        ui.PixelFormat.bgra8888,
        completer.complete,
        rowBytes: thumbnail.width * 4,
      );
      return completer.future;
    } on Object {
      return null;
    }
  }
}
