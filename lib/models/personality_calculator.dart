// A calculator that uses a fixed-size array to determine personality traits
// based on the average visibility value of recently visited areas
class PersonalityCalculator {
  final int maxEntries; // Maximum number of entries in the array
  final List<int> visibilityValues = []; // Stores recent visibility values
  
  PersonalityCalculator({this.maxEntries = 5});
  
  // Add a new visibility value to the array
  void addVisibilityValue(int value) {
    // Remove the oldest value if array is full
    if (visibilityValues.length >= maxEntries) {
      visibilityValues.removeAt(0);
    }
    
    // Add the new value
    visibilityValues.add(value);
  }
  
  // Check if the array is full
  bool isFull() {
    return visibilityValues.length >= maxEntries;
  }
  
  // Calculate the average of current visibility values
  double calculateAverageVisibility() {
    if (visibilityValues.isEmpty) return 0;
    
    int sum = visibilityValues.fold(0, (sum, value) => sum + value);
    return sum / visibilityValues.length;
  }
  
  // Determine personality result based on average visibility
  String determinePersonalityResult() {
    double average = calculateAverageVisibility();
    
    if (average < 20) {
      return "You are an introspective person who prefers solitude and quiet environments. You find peace in solitude and excel at deep thinking.";
    } else if (average < 40) {
      return "You are an analytical person who enjoys solving complex problems. Your logical thinking is strong, and you're good at finding connections between things.";
    } else if (average < 60) {
      return "You are a balanced person with both social skills and independent thinking. You can collaborate with others and also work well independently.";
    } else if (average < 80) {
      return "You are an extroverted person who enjoys socializing and new environments. You're energetic in team settings and good at motivating others.";
    } else {
      return "You are a vibrant leader who loves adventure and challenges. Your enthusiasm is contagious, and you stand out in any environment.";
    }
  }
  
  // Reset the calculator
  void reset() {
    visibilityValues.clear();
  }
  
  // Get progress text (e.g. "3/5")
  String getProgressText() {
    return "${visibilityValues.length}/$maxEntries";
  }
  
  // Get completion percentage
  double getCompletionPercentage() {
    return visibilityValues.length / maxEntries;
  }
}
