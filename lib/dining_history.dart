/// Dining scan history and "report incorrect result", stored in Supabase.
///
/// Tables: `dining_scans` and `dining_reports` (see
/// supabase_dining_history.sql). Saving never blocks or breaks a scan: a
/// missing table, signed-out user, or offline device just skips the save.
library;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'dining_food.dart';

/// How many past scans the history screen shows.
const int kDiningHistoryLimit = 50;

/// What a user can say is wrong with one identified food.
const List<String> kDiningReportProblems = [
  'Wrong food name',
  'Wrong allergens',
  'Wrong dietary information',
  'Wrong location',
  'Something else',
];

/// One saved scan: when it happened and the foods it found.
class DiningScan {
  const DiningScan({
    required this.id,
    required this.createdAt,
    required this.foods,
  });

  factory DiningScan.fromRow(Map<String, dynamic> row) {
    final rawFoods = row['foods'];
    return DiningScan(
      id: '${row['id']}',
      createdAt:
          DateTime.tryParse('${row['created_at']}')?.toLocal() ??
          DateTime.now(),
      foods: rawFoods is List
          ? [
              for (final item in rawFoods)
                if (item is Map)
                  DiningFood.fromJson(Map<String, dynamic>.from(item)),
            ]
          : const [],
    );
  }

  final String id;
  final DateTime createdAt;
  final List<DiningFood> foods;
}

SupabaseClient? get _client {
  try {
    return Supabase.instance.client;
  } catch (_) {
    return null;
  }
}

/// Saves a finished scan and returns its id, or null when it could not be
/// saved. Never throws.
Future<String?> saveDiningScan(List<DiningFood> foods) async {
  final client = _client;
  final userId = client?.auth.currentUser?.id;
  if (client == null || userId == null || foods.isEmpty) return null;
  try {
    final row = await client
        .from('dining_scans')
        .insert({
          'user_id': userId,
          'foods': [for (final food in foods) food.toJson()],
          'food_count': foods.length,
        })
        .select('id')
        .single();
    return '${row['id']}';
  } catch (error) {
    debugPrint('Dining scan history not saved: $error');
    return null;
  }
}

/// The signed-in user's most recent scans, newest first.
Future<List<DiningScan>> loadDiningScans() async {
  final client = _client;
  final userId = client?.auth.currentUser?.id;
  if (client == null || userId == null) {
    throw StateError('Sign in to see your scan history.');
  }
  final rows = await client
      .from('dining_scans')
      .select('id, created_at, foods')
      .eq('user_id', userId)
      .order('created_at', ascending: false)
      .limit(kDiningHistoryLimit);
  return [
    for (final row in rows) DiningScan.fromRow(Map<String, dynamic>.from(row)),
  ];
}

Future<void> deleteDiningScan(String id) async {
  final client = _client;
  if (client == null) throw StateError('Scan history is unavailable.');
  await client.from('dining_scans').delete().eq('id', id);
}

/// Flags [food] as identified wrongly. Throws when the report could not be
/// sent, so the screen can say so.
Future<void> reportIncorrectDiningFood({
  required DiningFood food,
  required List<String> problems,
  String note = '',
  String? scanId,
}) async {
  final client = _client;
  final userId = client?.auth.currentUser?.id;
  if (client == null || userId == null) {
    throw StateError('Sign in to send a report.');
  }
  await client.from('dining_reports').insert({
    'user_id': userId,
    'scan_id': scanId,
    'dish_name': food.dishName,
    'location': food.location,
    'problems': problems,
    'note': note.trim(),
    'food': food.toJson(),
  });
}

const List<String> _kWeekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const List<String> _kMonths = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// "Today at 3:05 PM", "Yesterday at 9:30 AM", or
/// "Monday, November 2 at 3:05 PM" (with the year when it is not this year).
/// Written out in full so a screen reader says it naturally.
String formatDiningScanTime(DateTime when, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final hour12 = when.hour % 12 == 0 ? 12 : when.hour % 12;
  final minute = when.minute.toString().padLeft(2, '0');
  final clock = '$hour12:$minute ${when.hour < 12 ? 'AM' : 'PM'}';

  final day = DateTime(when.year, when.month, when.day);
  final today = DateTime(current.year, current.month, current.day);
  final daysAgo = today.difference(day).inDays;
  if (daysAgo == 0) return 'Today at $clock';
  if (daysAgo == 1) return 'Yesterday at $clock';

  final date =
      '${_kWeekdays[when.weekday - 1]}, ${_kMonths[when.month - 1]} ${when.day}';
  final year = when.year == current.year ? '' : ', ${when.year}';
  return '$date$year at $clock';
}
