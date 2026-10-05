import 'app_icons.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import 'repository.dart';
import 'services.dart';

final privacyEnabled = ValueNotifier<bool>(false);
Future<bool> authenticateLibrary() async =>
    LocalAuthentication().authenticate(localizedReason: '解锁书叶本地书库');

class PrivacyGate extends StatefulWidget {
  final ReaderRepository repo;
  final Widget child;
  const PrivacyGate({super.key, required this.repo, required this.child});
  @override
  State<PrivacyGate> createState() => _PrivacyGateState();
}

class _PrivacyGateState extends State<PrivacyGate> with WidgetsBindingObserver {
  bool locked = false, checking = false, loading = true;
  String? error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    privacyEnabled.addListener(configure);
    unawaited(load());
  }

  Future<void> load() async {
    try {
      final s = await widget.repo.settings();
      privacyEnabled.value = s.flag('privacy.lock');
      configure();
      if (mounted) {
        setState(() {
          locked = privacyEnabled.value;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          locked = true;
          loading = false;
          error = '读取隐私设置失败，请保留数据并重新打开应用。';
        });
      }
    }
  }

  void configure() {
    unawaited(DeviceReader.call('secure', privacyEnabled.value));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed &&
        !checking &&
        privacyEnabled.value) {
      setState(() => locked = true);
    }
  }

  @override
  void dispose() {
    privacyEnabled.removeListener(configure);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> unlock() async {
    if (checking) return;
    setState(() => checking = true);
    try {
      final ok = await authenticateLibrary();
      if (mounted) setState(() => locked = !ok);
    } catch (_) {
      if (mounted) setState(() => error = '解锁失败，请检查手机的屏幕锁或指纹设置。');
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  // Lock screen furniture borrowed from the Claude-style reference: a large
  // thin clock, the date, and a greeting that follows the hour.
  String _clock() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  String _dateLine() {
    final now = DateTime.now();
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    return '${now.month} 月 ${now.day} 日 · 周${weekdays[now.weekday - 1]}';
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 6) return '夜深了，读到这一页就休息吧。';
    if (hour < 10) return '早上好，今天的阅读在等你。';
    if (hour < 14) return '午后，适合翻几页。';
    if (hour < 19) return '下午好，给阅读留一点时间。';
    if (hour < 23) return '晚上好，接着上次的地方读。';
    return '夜深了，注意眼睛。';
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Offstage(offstage: loading || locked, child: widget.child),
      if (loading)
        const Positioned.fill(
          child: Material(child: Center(child: CircularProgressIndicator())),
        ),
      if (locked)
        Positioned.fill(
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _clock(),
                      style: TextStyle(
                        fontSize: 46,
                        fontWeight: FontWeight.w300,
                        letterSpacing: 0,
                        color: Theme.of(context).colorScheme.onSurface,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _dateLine(),
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 30),
                    ShuyeIcon(
                      Icons.lock_outline,
                      size: 40,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '你的阅读，留给自己',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _greeting(),
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 26),
                    if (error != null) Text(error!),
                    FilledButton(
                      onPressed: checking ? null : unlock,
                      child: Text(checking ? '正在验证…' : '解锁书库'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
    ],
  );
}
