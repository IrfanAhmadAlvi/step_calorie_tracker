import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class StepStorage {
  // daily steps map
  static const _kDaily = 'daily_steps_v1';          // Map<String date, int steps>
  static const _kLastDayKey = 'last_day_key_v1';    // String
  static const _kLastToday = 'last_today_total_v1'; // int

  // goals (nullable)
  static const _kGoalSteps   = 'goal_steps_v1';     // int?
  static const _kGoalKcal    = 'goal_kcal_v1';      // int?
  static const _kGoalMinutes = 'goal_minutes_v1';   // int?

  // ---------- daily map ----------
  Future<Map<String, int>> loadDaily() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kDaily);
    if (raw == null) return {};
    final decoded = json.decode(raw);
    if (decoded is! Map) return {};
    return decoded.map<String, int>((k, v) => MapEntry(k.toString(), (v as num).toInt()));
  }

  Future<void> saveDaily(Map<String, int> daily) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kDaily, json.encode(daily));
  }

  Future<void> saveTodaySnapshot({required String dayKey, required int todaySteps}) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kLastDayKey, dayKey);
    await p.setInt(_kLastToday, todaySteps);
  }

  Future<({String? dayKey, int? today})> loadTodaySnapshot() async {
    final p = await SharedPreferences.getInstance();
    final dk = p.getString(_kLastDayKey);
    final t = p.getInt(_kLastToday);
    return (dayKey: dk, today: t);
  }

  // ---------- goals (nullable) ----------
  Future<int?> getGoalSteps() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_kGoalSteps);
  }

  Future<int?> getGoalKcal() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_kGoalKcal);
  }

  Future<int?> getGoalMinutes() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_kGoalMinutes);
  }

  Future<void> setGoalSteps(int? v) async {
    final p = await SharedPreferences.getInstance();
    if (v == null) {
      await p.remove(_kGoalSteps);
    } else {
      await p.setInt(_kGoalSteps, v);
    }
  }

  Future<void> setGoalKcal(int? v) async {
    final p = await SharedPreferences.getInstance();
    if (v == null) {
      await p.remove(_kGoalKcal);
    } else {
      await p.setInt(_kGoalKcal, v);
    }
  }

  Future<void> setGoalMinutes(int? v) async {
    final p = await SharedPreferences.getInstance();
    if (v == null) {
      await p.remove(_kGoalMinutes);
    } else {
      await p.setInt(_kGoalMinutes, v);
    }
  }
}
