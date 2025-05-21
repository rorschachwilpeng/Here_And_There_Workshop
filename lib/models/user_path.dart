import 'package:flutter/material.dart';

/// Represents a single entry in a user's path
class UserPathEntry {
  final String areaName;
  final int visibility;
  final DateTime enteredAt;

  UserPathEntry({
    required this.areaName,
    required this.visibility,
    required this.enteredAt,
  });
}

/// Manages the user's path through different areas
class UserPath {
  final List<UserPathEntry> entries = [];
  bool isActive = true;
  
  /// Add a new area to the path
  void addArea(String name, int visibility) {
    entries.add(
      UserPathEntry(
        areaName: name,
        visibility: visibility,
        enteredAt: DateTime.now(),
      ),
    );
  }
  
  /// Calculate the total visibility score of the path
  int calculateVisibilityScore() {
    return entries.fold(0, (sum, entry) => sum + entry.visibility);
  }
  
  /// Check if this area has already been visited in this path
  bool hasVisitedArea(String areaName) {
    return entries.any((entry) => entry.areaName == areaName);
  }
  
  /// Get a list of area names in this path
  List<String> getAreaNames() {
    return entries.map((entry) => entry.areaName).toList();
  }
  
  /// Complete the current path and calculate results
  Map<String, dynamic> completePath() {
    isActive = false;
    
    final score = calculateVisibilityScore();
    final result = _determinePersonalityResult(score);
    
    return {
      'score': score,
      'path': getAreaNames(),
      'result': result,
    };
  }
  
  /// Reset the path to start a new journey
  void reset() {
    entries.clear();
    isActive = true;
  }
  
  /// Map visibility score to personality results
  String _determinePersonalityResult(int score) {
    if (score < 50) {
      return "You are deeply introspective and value solitude. You find wisdom in quiet reflection.";
    } else if (score < 100) {
      return "You have a balanced perspective on life. You appreciate both quiet moments and social interactions.";
    } else if (score < 150) {
      return "You are outgoing and energetic. You draw inspiration from connecting with others and exploring new environments.";
    } else {
      return "You are exceptionally vibrant and expressive. You thrive in dynamic settings and inspire those around you with your energy.";
    }
  }
}
