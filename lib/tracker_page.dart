// lib/tracker_page.dart
import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'storage.dart';

class TrackerPage extends StatefulWidget {
  const TrackerPage({super.key});
  @override
  State<TrackerPage> createState() => _TrackerPageState();
}

class _TrackerPageState extends State<TrackerPage> with WidgetsBindingObserver {
  // streams & timers
  Timer? _ticker;
  StreamSubscription<StepCount>? _stepSub;

  // session pedometer state
  int? _baselineSteps;
  int _steps = 0;

  // daily tracking
  final _store = StepStorage();
  Map<String, int> _dailySteps = {};
  String _currentDayKey = _keyFor(DateTime.now());
  int? _dayBaselineSteps;

  // user settings
  double _stepLengthCm = 78;
  double _weightKg = 70;

  // GOALS — nullable & persisted
  int? _goalSteps;     // outer ring (pink)
  int? _goalKcal;      // middle ring (lime)
  int? _goalMinutes;   // inner ring (cyan)

  // timing
  DateTime? _runningSince;
  Duration _accumulated = Duration.zero;
  DateTime? _lastReadingTime;

  bool _isTracking = false;
  bool _loaded = false;
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
    WidgetsBinding.instance.addObserver(this);
    _initLoad(); // 🔒 load only; do NOT start tracking automatically
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _stepSub?.cancel();
    WakelockPlus.disable();
    _persistNow();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _persistNow();
    }
  }

  Future<void> _initLoad() async {
    // load daily data
    _dailySteps = await _store.loadDaily();

    // load goals (nullable)
    final stepsGoal = await _store.getGoalSteps();
    final kcalGoal  = await _store.getGoalKcal();
    final minGoal   = await _store.getGoalMinutes();

    if (!mounted) return;
    setState(() {
      _goalSteps   = stepsGoal;
      _goalKcal    = kcalGoal;
      _goalMinutes = minGoal;
      _loaded = true;
    });

    // ❌ DO NOT auto start tracking here
    // _start();
  }

  // ---------- persistence ----------
  Future<void> _persistNow() async {
    await _store.saveDaily(_dailySteps);
    final todayTotal = _dailySteps[_currentDayKey] ?? 0;
    await _store.saveTodaySnapshot(dayKey: _currentDayKey, todaySteps: todayTotal);
  }

  static String _keyFor(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

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
        _stepSub?.resume();
      }

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
        setState(() {}); // just to refresh elapsed time + rings
      }
    });
  }

  Future<int?> _reconstructedDayBaseline(int currentRaw) async {
    // If we already saved today's total, baseline = currentRaw - saved
    final saved = _dailySteps[_currentDayKey];
    if (saved != null) {
      final b = currentRaw - saved;
      return b < 0 ? 0 : b;
    }
    // Also try snapshot
    final snap = await _store.loadTodaySnapshot();
    if (snap.dayKey == _currentDayKey && snap.today != null) {
      final b = currentRaw - snap.today!;
      return b < 0 ? 0 : b;
    }
    return currentRaw; // first time today
  }

  void _onStepCount(StepCount event) async {
    final now = event.timeStamp ?? DateTime.now();
    _lastReadingTime = now;

    // Session steps
    _baselineSteps ??= event.steps;
    final sessionSteps = event.steps - (_baselineSteps ?? 0);
    if (sessionSteps >= 0) _steps = sessionSteps;

    // Daily steps (persistent)
    final key = _keyFor(now);
    if (key != _currentDayKey) {
      _currentDayKey = key; // day rollover
      _dayBaselineSteps = null;
    }

    _dayBaselineSteps ??= await _reconstructedDayBaseline(event.steps);
    int today = event.steps - (_dayBaselineSteps ?? event.steps);
    if (today < 0) today = 0;
    _dailySteps[_currentDayKey] = today;

    await _persistNow();
    if (mounted) setState(() {});
  }

  void _pause() {
    if (_runningSince != null) {
      _accumulated += DateTime.now().difference(_runningSince!);
      _runningSince = null;
    }
    _ticker?.cancel();
    _stepSub?.pause();
    WakelockPlus.disable();
    _persistNow();
    setState(() => _isTracking = false);
  }

  void _resume() {
    if (_runningSince == null) _runningSince = DateTime.now();
    _startTicker();
    _stepSub?.resume();
    WakelockPlus.enable();
    setState(() => _isTracking = true);
  }

  void _reset() {
    _ticker?.cancel();
    _stepSub?.pause();
    WakelockPlus.disable();
    _persistNow();
    setState(() {
      _isTracking = false;
      _baselineSteps = null;
      _steps = 0;
      _accumulated = Duration.zero;
      _runningSince = null;
      _lastReadingTime = null;
      _error = null;
      _dayBaselineSteps = null;
      _currentDayKey = _keyFor(DateTime.now());
    });
  }

  // ---------- metrics ----------
  double get _durationHours => _elapsed.inSeconds / 3600.0;
  double get _speedKmh {
    final distanceKm = (_steps * (_stepLengthCm / 100.0)) / 1000.0;
    return _durationHours > 0 ? distanceKm / _durationHours : 0.0;
  }

  double get _met {
    final v = _speedKmh;
    if (v < 3.0) return 2.8;
    if (v < 4.5) return 3.5;
    if (v < 5.5) return 4.3;
    return 5.0;
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
    color: const Color(0x334B4E57),
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
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final todaySteps = (_dailySteps[_currentDayKey] ?? 0);

    // Ring progress: only if goal is present; otherwise 0 (no default)
    final pSteps = (_goalSteps != null && _goalSteps! > 0)
        ? todaySteps / _goalSteps!
        : 0.0;
    final pKcal = (_goalKcal != null && _goalKcal! > 0)
        ? _kcal / _goalKcal!
        : 0.0;
    final pMins = (_goalMinutes != null && _goalMinutes! > 0)
        ? _elapsed.inMinutes / _goalMinutes!
        : 0.0;

    return Scaffold(
      body: Stack(
        children: [
          const _AnimatedBackdrop(),
          SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // header
                    Column(
                      children: [
                        const _GradientTitle(text: 'Step & Calorie Tracker'),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () => Navigator.pushNamed(context, '/weekly'),
                          icon: const Icon(Icons.bar_chart_rounded, color: Colors.white70),
                          label: const Text('Weekly Bar Chart',
                              style: TextStyle(color: Colors.white70)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // rings
                    Container(
                      decoration: _glassBox(),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          SizedBox(
                            height: 220,
                            width: 220,
                            child: _ActivityRings(
                              progressOuter: pSteps.clamp(0.0, 1.0),
                              progressMiddle: pKcal.clamp(0.0, 1.0),
                              progressInner: pMins.clamp(0.0, 1.0),
                              colorOuter: const Color(0xFFFF2F86),
                              colorMiddle: const Color(0xFF9CFF3A),
                              colorInner: const Color(0xFF30E6FF),
                              backgroundColor: const Color(0x22FFFFFF),
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Legend that hides "/goal" when no goal set
                          Wrap(
                            spacing: 16,
                            runSpacing: 8,
                            alignment: WrapAlignment.center,
                            children: [
                              _LegendDot(
                                color: const Color(0xFFFF2F86),
                                text: _goalSteps == null
                                    ? 'Steps: $todaySteps'
                                    : 'Steps: $todaySteps/${_goalSteps!}',
                              ),
                              _LegendDot(
                                color: const Color(0xFF9CFF3A),
                                text: _goalKcal == null
                                    ? 'kcal: ${_kcal.toStringAsFixed(0)}'
                                    : 'kcal: ${_kcal.toStringAsFixed(0)}/${_goalKcal!}',
                              ),
                              _LegendDot(
                                color: const Color(0xFF30E6FF),
                                text: _goalMinutes == null
                                    ? 'Active: ${_fmt(_elapsed)}'
                                    : 'Active: ${_fmt(_elapsed)} • ${_elapsed.inMinutes}/${_goalMinutes!}m',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),

                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Your settings',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                    ),
                    const SizedBox(height: 10),

                    // step length & weight
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
                    const SizedBox(height: 10),

                    // goals (nullable; blank input clears)
                    Row(
                      children: [
                        Expanded(
                          child: _SettingField(
                            label: 'Goal Steps (blank = none)',
                            initialText: _goalSteps?.toString() ?? '',
                            onSubmitted: (v) async {
                              final val = v.trim().isEmpty ? null : int.tryParse(v);
                              setState(() => _goalSteps = val);
                              await _store.setGoalSteps(val);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _SettingField(
                            label: 'Goal kcal (blank = none)',
                            initialText: _goalKcal?.toString() ?? '',
                            onSubmitted: (v) async {
                              final val = v.trim().isEmpty ? null : int.tryParse(v);
                              setState(() => _goalKcal = val);
                              await _store.setGoalKcal(val);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _SettingField(
                            label: 'Goal minutes (blank = none)',
                            initialText: _goalMinutes?.toString() ?? '',
                            onSubmitted: (v) async {
                              final val = v.trim().isEmpty ? null : int.tryParse(v);
                              setState(() => _goalMinutes = val);
                              await _store.setGoalMinutes(val);
                            },
                          ),
                        ),
                      ],
                    ),

                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                    ],

                    const SizedBox(height: 24),

                    // controls
                    Center(
                      child: Wrap(
                        spacing: 26,
                        runSpacing: 22,
                        alignment: WrapAlignment.center,
                        children: [
                          if (_isTracking)
                            _GlowButton(icon: Icons.pause_rounded, label: 'Pause', onTap: _pause)
                          else if (_isPaused)
                            _GlowButton(icon: Icons.play_arrow_rounded, label: 'Resume', onTap: _resume)
                          else
                            _GlowButton(icon: Icons.play_arrow_rounded, label: 'Start', onTap: _start),
                          _GlowButton(icon: Icons.restart_alt_rounded, label: 'Reset', onTap: _reset),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/* ======================== Activity Rings & UI bits ======================== */

class _ActivityRings extends StatelessWidget {
  final double progressOuter; // steps
  final double progressMiddle; // kcal
  final double progressInner; // minutes
  final Color colorOuter;
  final Color colorMiddle;
  final Color colorInner;
  final Color backgroundColor;

  const _ActivityRings({
    required this.progressOuter,
    required this.progressMiddle,
    required this.progressInner,
    required this.colorOuter,
    required this.colorMiddle,
    required this.colorInner,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RingsPainter(
        pOuter: progressOuter,
        pMiddle: progressMiddle,
        pInner: progressInner,
        cOuter: colorOuter,
        cMiddle: colorMiddle,
        cInner: colorInner,
        cTrack: backgroundColor,
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  final double pOuter, pMiddle, pInner;
  final Color cOuter, cMiddle, cInner, cTrack;

  _RingsPainter({
    required this.pOuter,
    required this.pMiddle,
    required this.pInner,
    required this.cOuter,
    required this.cMiddle,
    required this.cInner,
    required this.cTrack,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    const stroke = 20.0;
    const gap = 10.0;
    final minSide = min(size.width, size.height);

    final radii = [
      minSide / 2 - stroke / 2,
      minSide / 2 - stroke * 1.5 - gap,
      minSide / 2 - stroke * 2.5 - gap * 2,
    ];

    _drawRing(canvas, center, radii[0], stroke, cTrack, cOuter, pOuter);
    _drawRing(canvas, center, radii[1], stroke, cTrack, cMiddle, pMiddle);
    _drawRing(canvas, center, radii[2], stroke, cTrack, cInner, pInner);
  }

  void _drawRing(
      Canvas canvas, Offset center, double radius, double stroke,
      Color track, Color color, double progress) {
    final rect = Rect.fromCircle(center: center, radius: radius);
    const startAngle = -pi / 2;
    final sweep = (2 * pi) * progress.clamp(0.0, 1.0);

    // Track
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * pi, false, trackPaint);

    if (sweep <= 0.0) return;

    // Progress
    final progPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = color
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawArc(rect, startAngle, sweep, false, progPaint);

    // Arrow tip
    final endAngle = startAngle + sweep;
    final tip = Offset(center.dx + radius * cos(endAngle), center.dy + radius * sin(endAngle));
    _drawArrow(canvas, tip, endAngle, color);
    _drawArrowShadow(canvas, tip, endAngle);
  }

  void _drawArrow(Canvas canvas, Offset tip, double angle, Color color) {
    const arrowLen = 12.0;
    const arrowWidth = 8.0;
    final back = tip - Offset(cos(angle), sin(angle)) * arrowLen;
    final left = back + Offset(-sin(angle), cos(angle)) * (arrowWidth / 2);
    final right = back + Offset(sin(angle), -cos(angle)) * (arrowWidth / 2);

    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(right.dx, right.dy)
      ..close();

    final paint = Paint()..style = PaintingStyle.fill..color = color;
    canvas.drawPath(path, paint);
  }

  void _drawArrowShadow(Canvas canvas, Offset tip, double angle) {
    const arrowLen = 12.0;
    const arrowWidth = 8.0;
    final back = tip - Offset(cos(angle), sin(angle)) * arrowLen;
    final left = back + Offset(-sin(angle), cos(angle)) * (arrowWidth / 2);
    final right = back + Offset(sin(angle), -cos(angle)) * (arrowWidth / 2);

    final path = Path()
      ..moveTo(tip.dx + 1, tip.dy + 2)
      ..lineTo(left.dx + 1, left.dy + 2)
      ..lineTo(right.dx + 1, right.dy + 2)
      ..close();

    final paint = Paint()..style = PaintingStyle.fill..color = const Color(0x66000000);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _RingsPainter old) =>
      pOuter != old.pOuter || pMiddle != old.pMiddle || pInner != old.pInner ||
          cOuter != old.cOuter || cMiddle != old.cMiddle || cInner != old.cInner;
}

/* ---------- small UI bits ---------- */

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
              Positioned(top: -80, left: -40, child: _blob(const Color(0x3300E5FF), 220)),
              Positioned(bottom: -60, right: -20, child: _blob(const Color(0x337C4DFF), 200)),
            ],
          ),
        );
      },
    );
  }

  Widget _blob(Color color, double size) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: color,
      boxShadow: [BoxShadow(color: color, blurRadius: 80, spreadRadius: 20)],
    ),
  );
}

class _GradientTitle extends StatelessWidget {
  final String text;
  const _GradientTitle({required this.text});
  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (rect) =>
          const LinearGradient(colors: [Color(0xFF00E5FF), Color(0xFF7C4DFF)]).createShader(rect),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22, color: Colors.white),
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
        keyboardType: const TextInputType.numberWithOptions(decimal: false, signed: false),
        style: const TextStyle(fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          labelText: widget.label,
          labelStyle: const TextStyle(color: Colors.white70),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
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
  const _GlowButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 92,
          height: 92,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [Color(0xFF00E5FF), Color(0xFF7C4DFF)]),
            boxShadow: [
              BoxShadow(color: Color(0x8000E5FF), blurRadius: 30, spreadRadius: 1, offset: Offset(0, 6)),
              BoxShadow(color: Color(0x807C4DFF), blurRadius: 40, spreadRadius: -4, offset: Offset(0, 10)),
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
        Text(label, style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String text;
  const _LegendDot({required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: color.withOpacity(0.5), blurRadius: 8)],
          ),
        ),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
