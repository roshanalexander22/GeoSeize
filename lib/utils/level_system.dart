class LevelSystem {
  static const List<int> _xpRequirements = [
    0,      // Lvl 1
    500,    // Lvl 2
    1500,   // Lvl 3
    3500,   // Lvl 4
    7000,   // Lvl 5
    12000,  // Lvl 6
    20000,  // Lvl 7
    35000,  // Lvl 8
    60000,  // Lvl 9
    100000, // Lvl 10
  ];

  static const List<String> _rankTitles = [
    "Novice Explorer",
    "Street Walker",
    "Block Runner",
    "Neighborhood Boss",
    "District Ruler",
    "Urban Conqueror",
    "City Legend",
    "Metropolis King",
    "Continental Emperor",
    "Geo Master"
  ];

  /// Total number of defined levels.
  static int get maxLevel => _xpRequirements.length;

  /// Minimum area (m²) required to reach [level] (1-indexed).
  static double getMinAreaForLevel(int level) {
    final idx = (level - 1).clamp(0, _xpRequirements.length - 1);
    return _xpRequirements[idx].toDouble();
  }



  /// Returns the player's current level (1-indexed) based on total area captured.
  static int getLevel(double totalArea) {
    for (int i = _xpRequirements.length - 1; i >= 0; i--) {
      if (totalArea >= _xpRequirements[i]) {
        return i + 1;
      }
    }
    return 1;
  }

  /// Returns the player's title based on their current level.
  static String getRankTitle(int level) {
    if (level <= 0) return _rankTitles.first;
    if (level > _rankTitles.length) return _rankTitles.last;
    return _rankTitles[level - 1];
  }

  /// Returns the progress (0.0 to 1.0) towards the next level.
  static double getProgressToNextLevel(double totalArea) {
    int currentLevelIndex = getLevel(totalArea) - 1;
    
    if (currentLevelIndex >= _xpRequirements.length - 1) {
      return 1.0; // Max level
    }

    double currentLevelXpStart = _xpRequirements[currentLevelIndex].toDouble();
    double nextLevelXpStart = _xpRequirements[currentLevelIndex + 1].toDouble();

    double xpIntoLevel = totalArea - currentLevelXpStart;
    double xpRequiredForLevel = nextLevelXpStart - currentLevelXpStart;

    return (xpIntoLevel / xpRequiredForLevel).clamp(0.0, 1.0);
  }

  static double getNextLevelXpStart(int currentLevel) {
     if (currentLevel >= _xpRequirements.length) {
      return _xpRequirements.last.toDouble();
    }
    return _xpRequirements[currentLevel].toDouble();
  }
}
