import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

enum PickLogicMediaSourceKind { file, contentUri }

final class PickLogicMediaSource {
  const PickLogicMediaSource.file(this.value)
    : kind = PickLogicMediaSourceKind.file;

  const PickLogicMediaSource.contentUri(this.value)
    : kind = PickLogicMediaSourceKind.contentUri;

  final String value;
  final PickLogicMediaSourceKind kind;
}

/// Small shared player surface backed by the platform media stack.
///
/// PickLogic never decodes media itself. Windows uses Media Foundation through
/// its registered `video_player` implementation and Android uses ExoPlayer.
final class PickLogicMediaPlayer extends StatefulWidget {
  const PickLogicMediaPlayer({
    super.key,
    required this.source,
    required this.title,
    required this.chinese,
    this.audioOnly = false,
    this.artist,
    this.album,
  });

  final PickLogicMediaSource source;
  final String title;
  final bool chinese;
  final bool audioOnly;
  final String? artist;
  final String? album;

  @override
  State<PickLogicMediaPlayer> createState() => _PickLogicMediaPlayerState();
}

final class _PickLogicMediaPlayerState extends State<PickLogicMediaPlayer> {
  VideoPlayerController? _controller;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void didUpdateWidget(covariant PickLogicMediaPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source.kind != widget.source.kind ||
        oldWidget.source.value != widget.source.value) {
      _disposeController();
      _initialize();
    }
  }

  Future<void> _initialize() async {
    final controller = switch (widget.source.kind) {
      PickLogicMediaSourceKind.file => VideoPlayerController.file(
        File(widget.source.value),
      ),
      PickLogicMediaSourceKind.contentUri => VideoPlayerController.contentUri(
        Uri.parse(widget.source.value),
      ),
    };
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setVolume(1);
      if (mounted && identical(_controller, controller)) setState(() {});
    } on Object catch (error) {
      if (mounted && identical(_controller, controller)) {
        setState(() => _error = error);
      }
    }
  }

  void _disposeController() {
    final controller = _controller;
    _controller = null;
    _error = null;
    if (controller != null) controller.dispose();
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  Future<void> _showFullscreen(VideoPlayerController controller) async {
    await showDialog<void>(
      context: context,
      useSafeArea: false,
      builder: (context) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: controller.value.aspectRatio == 0
                    ? 16 / 9
                    : controller.value.aspectRatio,
                child: VideoPlayer(controller),
              ),
            ),
            Positioned(
              right: 16,
              top: 16,
              child: IconButton.filled(
                tooltip: widget.chinese ? '退出全屏' : 'Exit full screen',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.fullscreen_exit),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_error != null) {
      return Center(
        key: const Key('picklogic-media-error'),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            widget.chinese
                ? '系统媒体组件无法播放此格式。可从“更多”使用其他应用打开。'
                : 'The system media stack cannot play this format. Use More to open it with another app.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        key: Key('picklogic-media-loading'),
        child: CircularProgressIndicator(),
      );
    }
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) => Column(
        key: const Key('picklogic-media-player'),
        children: [
          Expanded(
            child: ColoredBox(
              color: widget.audioOnly
                  ? Theme.of(context).colorScheme.surfaceContainerLow
                  : Colors.black,
              child: Center(
                child: widget.audioOnly
                    ? _AudioIdentity(
                        title: widget.title,
                        artist: widget.artist,
                        album: widget.album,
                        chinese: widget.chinese,
                      )
                    : AspectRatio(
                        aspectRatio: value.aspectRatio == 0
                            ? 16 / 9
                            : value.aspectRatio,
                        child: VideoPlayer(controller),
                      ),
              ),
            ),
          ),
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Column(
                children: [
                  VideoProgressIndicator(
                    controller,
                    allowScrubbing: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  Row(
                    children: [
                      IconButton(
                        key: const Key('media-play-pause'),
                        tooltip: value.isPlaying
                            ? (widget.chinese ? '暂停' : 'Pause')
                            : (widget.chinese ? '播放' : 'Play'),
                        onPressed: value.isPlaying
                            ? controller.pause
                            : controller.play,
                        icon: Icon(
                          value.isPlaying ? Icons.pause : Icons.play_arrow,
                        ),
                      ),
                      Text(
                        '${_duration(value.position)} / ${_duration(value.duration)}',
                      ),
                      const Spacer(),
                      const Icon(Icons.volume_down, size: 20),
                      SizedBox(
                        width: 110,
                        child: Slider(
                          value: value.volume.clamp(0, 1),
                          onChanged: controller.setVolume,
                        ),
                      ),
                      if (!widget.audioOnly)
                        IconButton(
                          tooltip: widget.chinese ? '全屏' : 'Full screen',
                          onPressed: () => _showFullscreen(controller),
                          icon: const Icon(Icons.fullscreen),
                        ),
                    ],
                  ),
                  if (!widget.audioOnly && value.size != Size.zero)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        '${value.size.width.round()} × ${value.size.height.round()}',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final class _AudioIdentity extends StatelessWidget {
  const _AudioIdentity({
    required this.title,
    required this.artist,
    required this.album,
    required this.chinese,
  });

  final String title;
  final String? artist;
  final String? album;
  final bool chinese;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.album,
          size: 112,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          artist?.trim().isNotEmpty == true
              ? artist!
              : (chinese ? '艺术家：无法确认' : 'Artist: Unknown'),
        ),
        Text(
          album?.trim().isNotEmpty == true
              ? album!
              : (chinese ? '专辑：无法确认' : 'Album: Unknown'),
        ),
      ],
    ),
  );
}

String _duration(Duration value) {
  final totalSeconds = value.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  return hours > 0
      ? '$hours:${minutes.toString().padLeft(2, '0')}:$seconds'
      : '$minutes:$seconds';
}
