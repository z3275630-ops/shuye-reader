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
            color: const Color(0xfffaf9f5),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const ShuyeIcon(
                      Icons.lock_outline,
                      size: 56,
                      color: Color(0xffd97757),
                    ),
                    const SizedBox(height: 20),
                    const Text('你的阅读，留给自己', style: TextStyle(fontSize: 22)),
                    const SizedBox(height: 20),
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
