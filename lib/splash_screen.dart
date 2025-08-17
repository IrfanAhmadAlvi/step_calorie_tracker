import 'dart:async';
import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac =
  AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  late final Animation<double> _fade = CurvedAnimation(
    parent: _ac,
    curve: Curves.easeInOut,
  );

  @override
  void initState() {
    super.initState();
    _ac.forward();

    // Navigate after a short delay
    Timer(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/tracker');
    });
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // No AppBar, full screen
      body: Stack(
        children: [
          // Gradient backdrop to match your app
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0A0D13), Color(0xFF0F1021)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),

          // Decorative blobs (soft glows)
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

          // Center content
          SafeArea(
            child: Center(
              child: FadeTransition(
                opacity: _fade,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 96,
                      height: 96,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [Color(0xFF00E5FF), Color(0xFF7C4DFF)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x8000E5FF),
                            blurRadius: 30,
                            spreadRadius: 1,
                            offset: Offset(0, 6),
                          ),
                          BoxShadow(
                            color: Color(0x807C4DFF),
                            blurRadius: 40,
                            spreadRadius: -4,
                            offset: Offset(0, 10),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.directions_walk_rounded,
                          size: 50, color: Colors.white),
                    ),
                    const SizedBox(height: 18),

                    // App name in your gradient style
                    ShaderMask(
                      shaderCallback: (rect) => const LinearGradient(
                        colors: [Color(0xFF00E5FF), Color(0xFF7C4DFF)],
                      ).createShader(rect),
                      child: const Text(
                        'Step & Calorie Tracker',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 24,
                          color: Colors.white,
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),
                    Text(
                      'get moving...',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
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
