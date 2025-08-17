// lib/weekly_steps.dart
import 'package:flutter/material.dart';
import 'storage.dart';

class WeeklyStepsScreen extends StatefulWidget {
  const WeeklyStepsScreen({super.key});
  @override
  State<WeeklyStepsScreen> createState() => _WeeklyStepsScreenState();
}

class _WeeklyStepsScreenState extends State<WeeklyStepsScreen> {
  final _store = StepStorage();
  Map<String, int> _dailySteps = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDaily();
  }

  Future<void> _loadDaily() async {
    _dailySteps = await _store.loadDaily();
    if (mounted) setState(() => _loading = false);
  }

  static String _keyFor(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  List<_DaySteps> _last7DaysData() {
    final now = DateTime.now();
    final list = <_DaySteps>[];
    for (int i = 6; i >= 0; i--) {
      final d = DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
      final key = _keyFor(d);
      final steps = _dailySteps[key] ?? 0;
      list.add(_DaySteps(date: d, steps: steps));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final week = _last7DaysData();
    final maxSteps = week.isEmpty
        ? 1
        : week.map((e) => e.steps).fold<int>(0, (a, b) => a > b ? a : b).clamp(1, 1 << 30);
    final todayIndex = week.isEmpty ? 0 : week.length - 1;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0E13),
      body: Stack(
        children: [
          const _Backdrop(),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const _GradientTitle(text: 'Weekly Steps'),
                  const SizedBox(height: 6),
                  Text(
                    'Last 7 days',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),

                  _Glass(
                    child: _loading
                        ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                        : Padding(
                      padding: const EdgeInsets.fromLTRB(12, 16, 12, 28),
                      child: _WeeklyBarChart(
                        data: week,
                        maxSteps: maxSteps,
                        todayIndex: todayIndex,
                      ),
                    ),
                  ),

                  const SizedBox(height: 40), // ✅ avoids bottom overflow

                  TextButton.icon(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: const Text('Back'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF9FA8DA),
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

/* ------------------------ Bar Chart ------------------------ */

class _DaySteps {
  final DateTime date;
  final int steps;
  _DaySteps({required this.date, required this.steps});
}

class _WeeklyBarChart extends StatelessWidget {
  final List<_DaySteps> data;
  final int maxSteps;
  final int todayIndex;

  const _WeeklyBarChart({
    required this.data,
    required this.maxSteps,
    required this.todayIndex,
  });

  String _abbr(DateTime d) {
    const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return days[d.weekday % 7];
  }

  @override
  Widget build(BuildContext context) {
    const chartHeight = 220.0; // space for bars
    return LayoutBuilder(builder: (context, c) {
      final totalGaps = 6 * 12.0; // 7 bars → 6 gaps
      final barWidth = ((c.maxWidth - totalGaps) / 7).clamp(18.0, 40.0);

      return SizedBox(
        height: chartHeight + 70, // ✅ more room for labels/values
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (int i = 0; i < data.length; i++) ...[
              _Bar(
                width: barWidth,
                height: chartHeight *
                    (data[i].steps / (maxSteps == 0 ? 1 : maxSteps)),
                steps: data[i].steps,
                label: _abbr(data[i].date),
                highlight: i == todayIndex,
              ),
              if (i != data.length - 1) const SizedBox(width: 12),
            ],
          ],
        ),
      );
    });
  }
}

class _Bar extends StatelessWidget {
  final double width;
  final double height;
  final int steps;
  final String label;
  final bool highlight;

  const _Bar({
    required this.width,
    required this.height,
    required this.steps,
    required this.label,
    required this.highlight,
  });

  @override
  Widget build(BuildContext context) {
    final barRadius = BorderRadius.circular(12);

    return SizedBox(
      width: width,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            '$steps',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.white.withOpacity(0.9),
            ),
          ),
          const SizedBox(height: 6),

          Container(
            height: height.clamp(6.0, double.infinity),
            decoration: BoxDecoration(
              borderRadius: barRadius,
              gradient: const LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Color(0xFF00E5FF), Color(0xFF7C4DFF)],
              ),
              boxShadow: highlight
                  ? const [
                BoxShadow(
                  color: Color(0x8000E5FF),
                  blurRadius: 18,
                  spreadRadius: 1,
                  offset: Offset(0, 6),
                ),
              ]
                  : const [],
            ),
          ),

          const SizedBox(height: 8),

          Column(
            children: [
              Container(
                height: 4,
                width: width * 0.9,
                decoration: BoxDecoration(
                  color: const Color(0x5522D3EE),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/* ------------------------ UI helpers ------------------------ */

class _Glass extends StatelessWidget {
  final Widget child;
  const _Glass({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.none,
      decoration: BoxDecoration(
        color: const Color(0x334B4E57),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x22FFFFFF)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      child: child,
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
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 24,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _Backdrop extends StatelessWidget {
  const _Backdrop();
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0A0D13), Color(0xFF0F1021)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );
  }
}
