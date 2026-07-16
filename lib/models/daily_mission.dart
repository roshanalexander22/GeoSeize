// ─────────────────────────────────────────────────────────────────────────────
// DailyMission model
// ─────────────────────────────────────────────────────────────────────────────

enum MissionType {
  walk,       // walk X metres
  capture,    // capture X m² of area
  territory,  // create X new zones
  visit,      // visit X different areas (regions)
}

class DailyMission {
  final String id;
  final MissionType type;
  final String title;
  final String description;
  final String unit;       // display unit string, e.g. "m", "m²", "zones"
  final double goal;
  double progress;
  bool completed;
  bool claimed;
  final int coinReward;

  DailyMission({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.unit,
    required this.goal,
    this.progress = 0,
    this.completed = false,
    this.claimed = false,
    required this.coinReward,
  });

  double get progressFraction => (progress / goal).clamp(0.0, 1.0);

  String get progressLabel {
    if (goal >= 1000) {
      return '${(progress / 1000).toStringAsFixed(1)}k / ${(goal / 1000).toStringAsFixed(1)}k $unit';
    }
    return '${progress.toInt()} / ${goal.toInt()} $unit';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'title': title,
    'description': description,
    'unit': unit,
    'goal': goal,
    'progress': progress,
    'completed': completed,
    'claimed': claimed,
    'coinReward': coinReward,
  };

  factory DailyMission.fromJson(Map<String, dynamic> j) => DailyMission(
    id: j['id'] as String,
    type: MissionType.values.firstWhere(
      (e) => e.name == j['type'],
      orElse: () => MissionType.walk,
    ),
    title: j['title'] as String,
    description: j['description'] as String,
    unit: j['unit'] as String,
    goal: (j['goal'] as num).toDouble(),
    progress: (j['progress'] as num?)?.toDouble() ?? 0,
    completed: j['completed'] as bool? ?? false,
    claimed: j['claimed'] as bool? ?? false,
    coinReward: (j['coinReward'] as num).toInt(),
  );

  DailyMission copyWith({double? progress, bool? completed, bool? claimed}) {
    return DailyMission(
      id: id,
      type: type,
      title: title,
      description: description,
      unit: unit,
      goal: goal,
      progress: progress ?? this.progress,
      completed: completed ?? this.completed,
      claimed: claimed ?? this.claimed,
      coinReward: coinReward,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Predefined mission templates (one picked per slot per day)
// ─────────────────────────────────────────────────────────────────────────────
class MissionTemplates {
  static const List<Map<String, dynamic>> _all = [
    // Walk missions
    {
      'id': 'w_500',   'type': 'walk',    'title': 'Short Sprint',
      'description': 'Walk 500 m while capturing.',
      'unit': 'm',     'goal': 500,       'coinReward': 50,
    },
    {
      'id': 'w_1000',  'type': 'walk',    'title': 'Patrol Run',
      'description': 'Walk 1 km during your capture session.',
      'unit': 'm',     'goal': 1000,      'coinReward': 100,
    },
    {
      'id': 'w_2000',  'type': 'walk',    'title': 'Urban Trek',
      'description': 'Walk 2 km while capturing territory.',
      'unit': 'm',     'goal': 2000,      'coinReward': 180,
    },
    // Capture area missions
    {
      'id': 'c_100',   'type': 'capture', 'title': 'First Mark',
      'description': 'Capture at least 100 m² of area.',
      'unit': 'm²',    'goal': 100,       'coinReward': 60,
    },
    {
      'id': 'c_500',   'type': 'capture', 'title': 'Area Sweep',
      'description': 'Capture 500 m² in total today.',
      'unit': 'm²',    'goal': 500,       'coinReward': 120,
    },
    {
      'id': 'c_2000',  'type': 'capture', 'title': 'Zone Dominator',
      'description': 'Capture 2000 m² in a single session.',
      'unit': 'm²',    'goal': 2000,      'coinReward': 250,
    },
    // Territory missions
    {
      'id': 't_1',     'type': 'territory','title': 'First Contact',
      'description': 'Create 1 new territory zone.',
      'unit': 'zones', 'goal': 1,         'coinReward': 40,
    },
    {
      'id': 't_2',     'type': 'territory','title': 'Expand Empire',
      'description': 'Create 2 new territory zones.',
      'unit': 'zones', 'goal': 2,         'coinReward': 90,
    },
    {
      'id': 't_3',     'type': 'territory','title': 'Triple Grab',
      'description': 'Capture 3 distinct territory zones.',
      'unit': 'zones', 'goal': 3,         'coinReward': 150,
    },
    // Visit / explore missions
    {
      'id': 'v_1',     'type': 'visit',   'title': 'Scout Ahead',
      'description': 'Visit 1 new area you have not captured before.',
      'unit': 'areas', 'goal': 1,         'coinReward': 50,
    },
    {
      'id': 'v_2',     'type': 'visit',   'title': 'Explorer',
      'description': 'Visit 2 different named areas today.',
      'unit': 'areas', 'goal': 2,         'coinReward': 110,
    },
  ];

  /// Returns a stable pseudo-random selection of 4 missions for the given date
  /// string (format: "YYYY-MM-DD"). The seed ensures the same set is shown all day.
  static List<DailyMission> forDate(String dateStr) {
    // Cheap repeatable shuffle using dateStr as seed
    final seed = dateStr.codeUnits.fold(0, (a, b) => a * 31 + b);
    final indices = List.generate(_all.length, (i) => i);
    // Fisher-Yates with LCG
    int rng = seed;
    for (int i = indices.length - 1; i > 0; i--) {
      rng = (rng * 1664525 + 1013904223) & 0xFFFFFFFF;
      final j = rng % (i + 1);
      final tmp = indices[i]; indices[i] = indices[j]; indices[j] = tmp;
    }
    return indices.take(4).map((i) => DailyMission.fromJson({
      ..._all[i],
      'id': '${_all[i]['id']}_$dateStr',
    })).toList();
  }
}
