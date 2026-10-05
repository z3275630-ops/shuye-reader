import 'app_icons.dart';

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'repository.dart';
import 'services.dart';

class AudioLibrary {
  static final equalizer = AndroidEqualizer();
  static final player = AudioPlayer(
    audioPipeline: AudioPipeline(androidAudioEffects: [equalizer]),
  );
  static Timer? sleeper;
  static StreamSubscription<Duration>? watcher;
  static Map<String, dynamic>? current;
  static ReaderRepository? repository;
  static DateTime savedAt = DateTime(2000);
  static bool loading = false;
  static String? saveError;
  static void attach(ReaderRepository repo) {
    repository = repo;
    watcher ??= player.positionStream.listen((position) {
      if (!loading &&
          current != null &&
          DateTime.now().difference(savedAt).inSeconds >= 5) {
        savedAt = DateTime.now();
        unawaited(save());
      }
    });
  }

  static Future<void> save() async {
    final item = current;
    if (item == null || loading || repository == null) return;
    item['position'] = player.position.inMilliseconds;
    item['speed'] = player.speed;
    try {
      await repository!.putEntry('audio', item, id: item['id'] as String);
      saveError = null;
    } catch (_) {
      saveError = '播放进度暂未保存，请检查手机存储空间';
    }
  }

  static Future<void> open(Map<String, dynamic> item) async {
    await save();
    if (!await File(item['path'] as String).exists()) {
      throw const FileSystemException('音频文件已移动，请重新导入');
    }
    loading = true;
    try {
      await player.setAudioSource(
        AudioSource.file(
          item['path'] as String,
          tag: MediaItem(
            id: item['path'] as String,
            title: item['title'] as String,
            album: '书叶有声书',
          ),
        ),
      );
      current = {...item};
      await player.setSpeed(
        (item['speed'] as num? ?? 1).toDouble().clamp(.5, 2),
      );
      final end = player.duration?.inMilliseconds ?? 0;
      await player.seek(
        Duration(milliseconds: (item['position'] as int? ?? 0).clamp(0, end)),
      );
    } finally {
      loading = false;
    }
  }
}

class AudioScreen extends StatefulWidget {
  final ReaderRepository repo;
  const AudioScreen({super.key, required this.repo});
  @override
  State<AudioScreen> createState() => _AudioScreenState();
}

class _AudioScreenState extends State<AudioScreen> with WidgetsBindingObserver {
  final player = AudioLibrary.player;
  List<Map<String, dynamic>> files = [];
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AudioLibrary.attach(widget.repo);
    unawaited(load());
  }

  Future<void> load() async {
    final items = await widget.repo.entries('audio');
    if (mounted) setState(() => files = items);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(AudioLibrary.save());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(AudioLibrary.save());
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
      await load();
    } catch (e) {
      if (mounted) setState(() => error = '操作未完成：$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> pick() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.audio);
    if (picked == null) return;
    final file = picked.files.single;
    if (file.path == null || file.size > 512 * 1024 * 1024) {
      throw const FormatException('音频无法访问或超过 512 MB，请分段导入');
    }
    final root = await getApplicationSupportDirectory();
    final dir = await Directory('${root.path}/audio').create(recursive: true);
    final name = file.name.replaceAll(RegExp(r'[^\w.\u3400-\u9fff-]'), '_');
    final id = 'audio-${DateTime.now().microsecondsSinceEpoch}';
    final saved = await File(file.path!).copy('${dir.path}/$id-$name');
    final item = <String, dynamic>{
      'id': id,
      'title': file.name,
      'path': saved.path,
      'position': 0,
      'speed': 1.0,
    };
    await widget.repo.putEntry('audio', item, id: id);
    await AudioLibrary.open(item);
  }

  Future<void> remove(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('移除音频？'),
        content: Text('删除应用内的《${item['title']}》副本和播放记录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (AudioLibrary.current?['id'] == item['id']) {
      await player.stop();
      AudioLibrary.current = null;
    }
    final root = await getApplicationSupportDirectory();
    final file = File(item['path'] as String);
    if (p.isWithin(
          p.join(root.path, 'audio'),
          p.normalize(file.absolute.path),
        ) &&
        await file.exists()) {
      await file.delete();
    }
    await widget.repo.removeEntry(item['id'] as String);
  }

  Future<void> equalizer() async {
    if (!Platform.isAndroid || AudioLibrary.current == null) {
      throw const FormatException('请先选择音频，均衡器仅用于安卓');
    }
    final eq = AudioLibrary.equalizer;
    final parameters = await eq.parameters.timeout(const Duration(seconds: 5));
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              SwitchListTile(
                title: const Text('安卓均衡器'),
                value: eq.enabled,
                onChanged: (v) async {
                  await eq.setEnabled(v);
                  set(() {});
                },
              ),
              for (final band in parameters.bands) ...[
                Text(
                  '${band.centerFrequency.round()} Hz · ${band.gain.toStringAsFixed(1)} dB',
                ),
                Slider(
                  value: band.gain.clamp(
                    parameters.minDecibels,
                    parameters.maxDecibels,
                  ),
                  min: parameters.minDecibels,
                  max: parameters.maxDecibels,
                  onChanged: (v) {
                    unawaited(band.setGain(v));
                    set(() {});
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('有声书'),
      actions: [
        IconButton(
          tooltip: '均衡器',
          onPressed: busy ? null : () => run(equalizer),
          icon: const ShuyeIcon(Icons.equalizer),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (busy) const LinearProgressIndicator(),
        ShuyeIcon(
          Icons.headphones_outlined,
          size: 72,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 20),
        Text(
          AudioLibrary.current?['title'] as String? ?? '选择手机上的音频',
          style: const TextStyle(fontSize: 20),
        ),
        if (error != null || AudioLibrary.saveError != null)
          Text(error ?? AudioLibrary.saveError!),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: () => DeviceReader.call('audioNotification'),
          icon: const ShuyeIcon(Icons.notifications_outlined),
          label: const Text('允许播放通知'),
        ),
        FilledButton.icon(
          onPressed: busy ? null : () => run(pick),
          icon: const ShuyeIcon(Icons.add),
          label: const Text('导入音频'),
        ),
        StreamBuilder<Duration>(
          stream: player.positionStream,
          initialData: player.position,
          builder: (c, s) {
            final end = player.duration?.inMilliseconds.toDouble() ?? 0;
            return Column(
              children: [
                Slider(
                  value: (s.data?.inMilliseconds.toDouble() ?? 0).clamp(0, end),
                  max: end > 0 ? end : 1,
                  onChanged: end == 0
                      ? null
                      : (v) => unawaited(
                          player.seek(Duration(milliseconds: v.round())),
                        ),
                ),
                Text(
                  '${s.data?.toString().split('.').first ?? '0:00'} / ${player.duration?.toString().split('.').first ?? '0:00'}',
                ),
              ],
            );
          },
        ),
        StreamBuilder<PlayerState>(
          stream: player.playerStateStream,
          initialData: player.playerState,
          builder: (c, s) => IconButton(
            iconSize: 60,
            onPressed: busy || AudioLibrary.current == null
                ? null
                : () async {
                    try {
                      if (player.playing) {
                        await player.pause();
                        await AudioLibrary.save();
                      } else {
                        if (player.processingState ==
                            ProcessingState.completed) {
                          await player.seek(Duration.zero);
                        }
                        unawaited(
                          player.play().catchError((Object e) {
                            if (mounted) setState(() => error = '播放失败：$e');
                          }),
                        );
                      }
                    } catch (e) {
                      if (mounted) setState(() => error = '播放失败：$e');
                    }
                  },
            icon: ShuyeIcon(
              s.data?.playing == true ? Icons.pause_circle : Icons.play_circle,
            ),
          ),
        ),
        Text('播放速度 ${player.speed.toStringAsFixed(1)}×'),
        Slider(
          value: player.speed.clamp(.5, 2),
          min: .5,
          max: 2,
          divisions: 15,
          onChanged: (v) {
            unawaited(
              player.setSpeed(v).then((_) {
                if (mounted) setState(() {});
              }),
            );
          },
        ),
        Wrap(
          spacing: 8,
          children: [
            for (final minutes in [0, 15, 30, 60])
              ActionChip(
                label: Text(minutes == 0 ? '取消定时' : '$minutes 分钟后暂停'),
                onPressed: () {
                  AudioLibrary.sleeper?.cancel();
                  if (minutes > 0) {
                    AudioLibrary.sleeper = Timer(
                      Duration(minutes: minutes),
                      () => unawaited(
                        player.pause().then((_) => AudioLibrary.save()),
                      ),
                    );
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        minutes == 0 ? '定时已取消' : '将在 $minutes 分钟后暂停',
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Text(
            '支持后台播放、通知栏与耳机控制。进度会保存；音频副本仅保留在本机，换手机需重新导入。',
            style: TextStyle(fontSize: 12),
          ),
        ),
        const Text('音频库', style: TextStyle(fontSize: 20)),
        if (files.isEmpty)
          const Padding(padding: EdgeInsets.all(20), child: Text('还没有导入音频')),
        for (final item in files)
          ListTile(
            title: Text(item['title'] as String),
            subtitle: Text(
              '上次播放 ${(item['position'] as int? ?? 0) ~/ 60000} 分钟',
            ),
            onTap: busy ? null : () => run(() => AudioLibrary.open(item)),
            trailing: IconButton(
              tooltip: '移除音频',
              onPressed: busy ? null : () => run(() => remove(item)),
              icon: const ShuyeIcon(Icons.delete_outline),
            ),
          ),
      ],
    ),
  );
}
