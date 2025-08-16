import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const StepCalorieApp());
}

class StepCalorieApp extends StatelessWidget {
  const StepCalorieApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C5CE7),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0B0E13),
        useMaterial3: true,
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: Colors.white70),
        ),
      ),
      home: const Scaffold(
        body: TrackerPage(), // no AppBar here
      ),
    );
  }
}

class TrackerPage extends StatefulWidget {
  const TrackerPage({super.key});

  @override
  State<TrackerPage> createState() => _TrackerPageState();
}

class _TrackerPageState extends State<TrackerPage> {
  // streams & timers
  Timer? _ticker;
  StreamSubscription<StepCount>? _stepSub;

  // pedometer state
  int? _baselineSteps;
  int _steps = 0;

  // user settings
  double _stepLengthCm = 78;
  double _weightKg = 70;

  // timing model
  DateTime? _runningSince;                // null when paused/stopped
  Duration _accumulated = Duration.zero;  // total elapsed across run segments
  DateTime? _lastReadingTime;

  bool _isTracking = false; // true only while running
  String? _error;

  bool get _isPaused =>
      !_isTracking && (_accumulated > Duration.zero || _baselineSteps != null);

  Duration get _elapsed {
    if (_runningSince != null) {
      return _accumulated + DateTime.now().difference(_runningSince!);
    }
    return _accumulated;
  }

  // ---------- lifecycle ----------
  @override
  void initState() {
    super.initState();
    _start(); // auto-start; remove this if you want manual start
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _stepSub?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }

  // ---------- permissions ----------
  Future<void> _requestPermissions() async {
    await Permission.activityRecognition.request();
  }

  // ---------- control ----------
  Future<void> _start() async {
    setState(() => _error = null);

    await _requestPermissions();
    if (await Permission.activityRecognition.isDenied ||
        await Permission.activityRecognition.isPermanentlyDenied) {
      setState(() => _error = 'Motion/Activity permission is required.');
      return;
    }

    try {
      await WakelockPlus.enable();

      // Create subscription if not present; otherwise we might be resuming
      if (_stepSub == null) {
        _stepSub = Pedometer.stepCountStream.listen(
          _onStepCount,
          onError: (e) => setState(() {
            _error = 'Pedometer error: $e';
            _isTracking = false;
          }),
          onDone: () => setState(() => _isTracking = false),
          cancelOnError: true,
        );
      } else {
        _stepSub?.resume(); // <-- resume returns void (no await)
      }

      // Begin a new run segment if currently paused/stopped
      _runningSince ??= DateTime.now();
      _startTicker();

      setState(() => _isTracking = true);
    } catch (e) {
      setState(() {
        _error = 'Could not start pedometer: $e';
        _isTracking = false;
      });
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_isTracking && _runningSince != null) {
        // Rebuild to reflect updated _elapsed getter
        setState(() {});
      }
    });
  }

  void _onStepCount(StepCount event) {
    final now = event.timeStamp ?? DateTime.now();
    _lastReadingTime = now;

    _baselineSteps ??= event.steps;
    final sessionSteps = event.steps - (_baselineSteps ?? 0);
    if (sessionSteps >= 0) {
      setState(() {
        _steps = sessionSteps;
        // NOTE: Do NOT mutate elapsed here. The ticker/UI handles it.
      });
    }
  }

  void _pause() {
    if (_runningSince != null) {
      _accumulated += DateTime.now().difference(_runningSince!);
      _runningSince = null;
    }
    _ticker?.cancel();
    _stepSub?.pause();
    WakelockPlus.disable();
    setState(() {
      _isTracking = false;
    });
  }

  void _resume() {
    if (_runningSince == null) {
      _runningSince = DateTime.now();
    }
    _startTicker();
    _stepSub?.resume(); // no await
    WakelockPlus.enable();
    setState(() {
      _isTracking = true;
    });
  }

  void _stop() {
    // Fold in any running segment, then cancel subscription
    if (_runningSince != null) {
      _accumulated += DateTime.now().difference(_runningSince!);
      _runningSince = null;
    }
    _ticker?.cancel();
    _stepSub?.cancel();
    _stepSub = null;
    WakelockPlus.disable();
    setState(() {
      _isTracking = false;
    });
  }

  void _reset() {
    _ticker?.cancel();
    _stop();
    setState(() {
      _baselineSteps = null;
      _steps = 0;
      _accumulated = Duration.zero;
      _runningSince = null;
      _lastReadingTime = null;
      _error = null;
    });
  }

  // ---------- derived metrics ----------
  double get _distanceMeters => _steps * (_stepLengthCm / 100.0);
  double get _distanceKm => _distanceMeters / 1000.0;
  double get _durationHours => _elapsed.inSeconds / 3600.0;
  double get _speedKmh => _durationHours > 0 ? _distanceKm / _durationHours : 0.0;

  // simple speed→MET mapping
  double get _met {
    final v = _speedKmh;
    if (v < 3.0) return 2.8; // easy stroll
    if (v < 4.5) return 3.5; // normal walk
    if (v < 5.5) return 4.3; // brisk
    return 5.0; // very brisk
  }

  double get _kcal => _durationHours > 0 ? _met * _weightKg * _durationHours : 0.0;

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${h.toString().padLeft(2, '0')}:$m:$s';
  }

  // ---------- UI helpers ----------
  BoxDecoration _glassBox() => BoxDecoration(
    color: const Color(0x334B4E57), // translucent bluish
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: const Color(0x22FFFFFF)),
    boxShadow: const [
      BoxShadow(
        color: Color(0x3300E5FF),
        blurRadius: 22,
        spreadRadius: 0,
        offset: Offset(0, 8),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const _AnimatedBackdrop(), // glowing blobs
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const _GradientTitle(text: 'Step & Calorie Tracker'),
                  const SizedBox(height: 16),

                  // Top metrics
                  Row(
                    children: [
                      Expanded(
                        child: _MetricCard(
                          decoration: _glassBox(),
                          icon: Icons.directions_walk_rounded,
                          title: 'Steps',
                          value: '$_steps',
                          subtitle: _lastReadingTime == null
                              ? ''
                              : 'Updated ${_lastReadingTime!.hour.toString().padLeft(2, '0')}:${_lastReadingTime!.minute.toString().padLeft(2, '0')}',
                          valueFontSize: 32,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _MetricCard(
                          decoration: _glassBox(),
                          icon: Icons.route_rounded,
                          title: 'Distance',
                          value: '${_distanceKm.toStringAsFixed(2)} km',
                          subtitle: '${_distanceMeters.toStringAsFixed(0)} m',
                          valueFontSize: 28,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _MetricCard(
                          decoration: _glassBox(),
                          icon: Icons.timer_rounded,
                          title: 'Duration',
                          value: _fmt(_elapsed),
                          subtitle: _isTracking
                              ? 'Running'
                              : (_isPaused ? 'Paused' : 'Stopped'),
                          valueFontSize: 26,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _MetricCard(
                          decoration: _glassBox(),
                          icon: Icons.local_fire_department_rounded,
                          title: 'Calories',
                          value: '${_kcal.toStringAsFixed(0)} kcal',
                          subtitle:
                          'MET ${_met.toStringAsFixed(1)} | ${_speedKmh.toStringAsFixed(1)} km/h',
                          valueFontSize: 28,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),
                  const Text(
                    'Your settings',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                  ),

                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _SettingField(
                          label: 'Step length (cm)',
                          initialText: _stepLengthCm.toStringAsFixed(0),
                          onSubmitted: (v) {
                            final parsed = double.tryParse(v);
                            if (parsed != null && parsed > 20 && parsed < 200) {
                              setState(() => _stepLengthCm = parsed);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SettingField(
                          label: 'Weight (kg)',
                          initialText: _weightKg.toStringAsFixed(0),
                          onSubmitted: (v) {
                            final parsed = double.tryParse(v);
                            if (parsed != null && parsed > 20 && parsed < 300) {
                              setState(() => _weightKg = parsed);
                            }
                          },
                        ),
                      ),
                    ],
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ],

                  const Spacer(),

                  // ----------- CENTERED CONTROLS -----------
                  Center(
                    child: Wrap(
                      spacing: 26,
                      runSpacing: 22,
                      alignment: WrapAlignment.center,
                      children: [
                        if (_isTracking)
                          _GlowButton(
                            icon: Icons.pause_rounded,
                            label: 'Pause',
                            onTap: _pause,
                          )
                        else if (_isPaused)
                          _GlowButton(
                            icon: Icons.play_arrow_rounded,
                            label: 'Resume',
                            onTap: _resume,
                          )
                        else
                          _GlowButton(
                            icon: Icons.play_arrow_rounded,
                            label: 'Start',
                            onTap: _start,
                          ),

                        _GlowButton(
                          icon: Icons.restart_alt_rounded,
                          label: 'Reset',
                          onTap: _reset,
                        ),
                      ],
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

// ====================== Widgets ======================

class _AnimatedBackdrop extends StatefulWidget {
  const _AnimatedBackdrop();

  @override
  State<_AnimatedBackdrop> createState() => _AnimatedBackdropState();
}

class _AnimatedBackdropState extends State<_AnimatedBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac =
  AnimationController(vsync: this, duration: const Duration(seconds: 8))
    ..repeat(reverse: true);
  late final Animation<Alignment> _a1 =
  AlignmentTween(begin: Alignment.topLeft, end: Alignment.bottomRight)
      .animate(CurvedAnimation(parent: _ac, curve: Curves.easeInOut));
  late final Animation<Alignment> _a2 =
  AlignmentTween(begin: Alignment.bottomRight, end: Alignment.topLeft)
      .animate(CurvedAnimation(parent: _ac, curve: Curves.easeInOut));

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ac,
      builder: (_, __) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: _a1.value,
              end: _a2.value,
              colors: const [Color(0xFF0A0D13), Color(0xFF0F1021)],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                top: -80,
                left: -40,
                child: _blob(const Color(0x3300E5FF), 220),
              ),
              Positioned(
                bottom: -60,
                right: -20,
                child: _blob(const Color(0x337C4DFF), 200),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _blob(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [BoxShadow(color: color, blurRadius: 80, spreadRadius: 20)],
      ),
    );
  }
}

class _GradientTitle extends StatelessWidget {
  final String text;
  const _GradientTitle({required this.text});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (rect) =>
          const LinearGradient(colors: [Color(0xFF00E5FF), Color(0xFF7C4DFF)])
              .createShader(rect),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 22,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final BoxDecoration decoration;
  final IconData icon;
  final String title;
  final String value;
  final String subtitle;
  final double valueFontSize;

  const _MetricCard({
    required this.decoration,
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.valueFontSize,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: decoration,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 20, color: Colors.white70),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, color: Colors.white70)),
                      const SizedBox(height: 6),
                      // Neon gradient number
                      ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [Color(0xFF00E5FF), Color(0xFF7C4DFF)],
                        ).createShader(bounds),
                        child: Text(
                          value,
                          style: TextStyle(
                            fontSize: valueFontSize,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            shadows: const [
                              Shadow(
                                  blurRadius: 8,
                                  color: Color(0x5500E5FF),
                                  offset: Offset(0, 0)),
                              Shadow(
                                  blurRadius: 8,
                                  color: Color(0x557C4DFF),
                                  offset: Offset(0, 0)),
                            ],
                          ),
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(subtitle,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.white70)),
                      ],
                    ],
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

class _SettingField extends StatefulWidget {
  final String label;
  final String initialText;
  final ValueChanged<String> onSubmitted;
  const _SettingField({
    required this.label,
    required this.initialText,
    required this.onSubmitted,
  });

  @override
  State<_SettingField> createState() => _SettingFieldState();
}

class _SettingFieldState extends State<_SettingField> {
  late final TextEditingController _c;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0x22333A45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x22FFFFFF)),
      ),
      child: TextField(
        controller: _c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: const TextStyle(fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          labelText: widget.label,
          labelStyle: const TextStyle(color: Colors.white70),
          border: InputBorder.none,
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        ),
        onSubmitted: widget.onSubmitted,
      ),
    );
  }
}

class _GlowButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _GlowButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 92,
          height: 92,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient:
            LinearGradient(colors: [Color(0xFF00E5FF), Color(0xFF7C4DFF)]),
            boxShadow: [
              BoxShadow(
                  color: Color(0x8000E5FF),
                  blurRadius: 30,
                  spreadRadius: 1,
                  offset: Offset(0, 6)),
              BoxShadow(
                  color: Color(0x807C4DFF),
                  blurRadius: 40,
                  spreadRadius: -4,
                  offset: Offset(0, 10)),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Icon(icon, size: 44, color: Colors.white),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
        ),
      ],
    );
  }
}
