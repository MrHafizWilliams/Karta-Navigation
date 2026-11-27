import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../i18n/karta_l10n.dart';
import '../icons/karta_logo_mark.dart';
import '../tokens/karta_typography.dart';
import 'karta_pointer_shield.dart';
import 'karta_runtime_env_stub.dart'
    if (dart.library.io) 'karta_runtime_env_io.dart' as runtime_env;

/// Official Karta MP4 video intro splash played on launch across all devices
/// (Android, iOS, Web, macOS, tablets & automotive displays).
///
/// Plays the bundled `Karta Logo (Small_Smartphone).mp4` (`assets/karta_intro.mp4`)
/// on a seamless pure-black (`#000000`) backdrop while the 3D map and live GPS
/// initialize underneath, then smoothly fades into the live map when playback
/// completes (or immediately when tapped).
class KartaIntroSplashOverlay extends StatefulWidget {
  const KartaIntroSplashOverlay({
    super.key,
    required this.onFinished,
    this.maxDuration = const Duration(milliseconds: 5600),
  });

  final VoidCallback onFinished;
  final Duration maxDuration;

  static const String videoAssetPath = 'assets/karta_intro.mp4';
  static const String packageName = 'karta_design_system';

  @override
  State<KartaIntroSplashOverlay> createState() => _KartaIntroSplashOverlayState();
}

class _KartaIntroSplashOverlayState extends State<KartaIntroSplashOverlay>
    with SingleTickerProviderStateMixin {
  VideoPlayerController? _videoCtrl;
  late final AnimationController _exitCtrl;
  Timer? _failsafeTimer;
  bool _videoReady = false;
  bool _videoFailed = false;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _exitCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );

    final useVideoPlayer = !runtime_env.isKartaHeadlessTest &&
        !runtime_env.isKartaDesktopWithoutVideoPlugin;

    if (useVideoPlayer) {
      _initIntroVideo();
      _failsafeTimer = Timer(widget.maxDuration, _beginDismiss);
    } else {
      _videoFailed = true;
      _failsafeTimer = Timer(const Duration(milliseconds: 2200), _beginDismiss);
    }
  }

  Future<void> _initIntroVideo() async {
    try {
      final ctrl = VideoPlayerController.asset(
        KartaIntroSplashOverlay.videoAssetPath,
        package: KartaIntroSplashOverlay.packageName,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      _videoCtrl = ctrl;
      ctrl.addListener(_onVideoTick);
      await ctrl.initialize();
      if (!mounted || _dismissing) return;

      // Muted autoplay ensures instant zero-prompt playback on Chrome/Safari Web & mobile
      await ctrl.setVolume(0.0);
      await ctrl.setLooping(false);
      await ctrl.play();

      if (mounted) {
        setState(() => _videoReady = true);
      }

      // Align failsafe timeout closely to real video duration (+650ms buffer)
      final dur = ctrl.value.duration;
      if (dur > Duration.zero) {
        _failsafeTimer?.cancel();
        _failsafeTimer = Timer(dur + const Duration(milliseconds: 650), _beginDismiss);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _videoFailed = true);
        _failsafeTimer?.cancel();
        _failsafeTimer = Timer(const Duration(milliseconds: 1800), _beginDismiss);
      }
    }
  }

  void _onVideoTick() {
    final ctrl = _videoCtrl;
    if (ctrl == null || _dismissing || !mounted) return;
    final val = ctrl.value;
    if (val.hasError) {
      setState(() => _videoFailed = true);
      return;
    }
    if (val.isInitialized && val.duration > Duration.zero) {
      final remaining = val.duration - val.position;
      if (val.isCompleted || remaining <= const Duration(milliseconds: 120)) {
        _beginDismiss();
      }
    }
  }

  void _beginDismiss() {
    if (_dismissing || !mounted) return;
    _dismissing = true;
    _failsafeTimer?.cancel();
    _videoCtrl?.pause();
    _exitCtrl.forward().whenComplete(() {
      if (mounted) {
        widget.onFinished();
      }
    });
  }

  @override
  void dispose() {
    _failsafeTimer?.cancel();
    _videoCtrl?.removeListener(_onVideoTick);
    _videoCtrl?.dispose();
    _exitCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final exitFade = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _exitCtrl, curve: Curves.easeInOutCubic),
    );
    final exitScale = Tween<double>(begin: 1.0, end: 1.04).animate(
      CurvedAnimation(parent: _exitCtrl, curve: Curves.easeInCubic),
    );

    return KartaPointerShield(
      child: Material(
        type: MaterialType.transparency,
        child: AnimatedBuilder(
          animation: _exitCtrl,
          builder: (context, child) {
            return Opacity(
              opacity: exitFade.value.clamp(0.0, 1.0),
              child: Transform.scale(
                scale: exitScale.value,
                child: child,
              ),
            );
          },
          child: ColoredBox(
            color: Colors.black,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                // Centered square MP4 video on seamless pure-black canvas
                if (_videoReady && _videoCtrl != null && !_videoFailed)
                  Center(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final aspect = _videoCtrl!.value.aspectRatio > 0
                            ? _videoCtrl!.value.aspectRatio
                            : 1.0;
                        final maxSide = constraints.biggest.shortestSide;
                        return ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: maxSide,
                            maxHeight: maxSide,
                          ),
                          child: AspectRatio(
                            aspectRatio: aspect,
                            child: VideoPlayer(_videoCtrl!),
                          ),
                        );
                      },
                    ),
                  )
                else
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const KartaLogoMark(size: 112),
                        const SizedBox(height: 18),
                        Text(
                          'Karta',
                          style: KartaTypography.hudHero.copyWith(
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Navigational App',
                          style: KartaTypography.bodySecondary.copyWith(
                            fontSize: 15,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Transparent full-screen pointer shield + tap-to-skip layer above video
                Positioned.fill(
                  child: KartaPointerShield(
                    child: GestureDetector(
                      key: const ValueKey<String>('karta-intro-splash'),
                      behavior: HitTestBehavior.opaque,
                      onTap: _beginDismiss,
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: SafeArea(
                          top: false,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 24),
                            child: Text(
                              context.kartaStrings.tapToSkipIntro,
                              style: KartaTypography.captionLabel.copyWith(
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: 0.38),
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
