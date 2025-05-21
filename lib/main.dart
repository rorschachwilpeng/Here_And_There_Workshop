import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geo_music_personality/models/user_path.dart';
import 'package:geo_music_personality/models/personality_calculator.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Geo Music Personality Test',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Current position information
  Position? _currentPosition;
  
  // Music player
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  // Store all area data
  final List<Map<String, dynamic>> _areas = [];
  
  // Current entered area
  Map<String, dynamic>? _currentArea;
  
  // Position listener subscription
  StreamSubscription<Position>? _positionStreamSubscription;
  
  // Program status
  bool _isLoading = true;
  bool _isPlaying = false;
  String _statusMessage = "Initializing...";

  // Track user path
  UserPath _currentPath = UserPath();

  // Store personality results based on paths
  Map<String, dynamic>? _pathResults;

  // Flag to show path results
  bool _showingPathResults = false;

  // Store previously visited areas for path tracking
  Set<String> _visitedAreas = {};

  // Personality calculator using fixed-size array approach
  PersonalityCalculator _personalityCalculator = PersonalityCalculator(maxEntries: 5);
  bool _resultShown = false;

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  @override
  void dispose() {
    // Release resources
    _positionStreamSubscription?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  // Initialize the application
  Future<void> _initApp() async {
    setState(() {
      _statusMessage = "Loading data...";
    });
    
    // 1. Load GeoJSON data
    await _loadGeoJsonData();
    
    // 2. Request location permission and start tracking location
    await _requestLocationPermission();
    
    setState(() {
      _isLoading = false;
      _statusMessage = "Application ready";
    });
  }

  // Load GeoJSON data
  Future<void> _loadGeoJsonData() async {
    try {
      // Read GeoJSON file
      final String geoJsonString = await rootBundle.loadString('assets/test.geojson');
      final Map<String, dynamic> geoJsonMap = json.decode(geoJsonString);
      
      // 解析GeoJSON features
      final features = geoJsonMap['features'] as List;
      
      for (var feature in features) {
        if (feature['geometry']['type'] == 'Polygon') {
          // Extract area attributes
          final properties = feature['properties'];
          final name = properties['name'];
          final musicUrl = properties['music_url'];
          final personalityResult = properties['personality_result'];
          final visibility = properties['visibility'] as int? ?? 50; // Default to 50 if not specified
          
          // Extract area boundary coordinates
          final coordinates = feature['geometry']['coordinates'][0] as List;
          final List<List<double>> polygonPoints = [];
          
          for (var coord in coordinates) {
            polygonPoints.add([coord[0], coord[1]]);
          }
          
          // Save area information
          _areas.add({
            'name': name,
            'music_url': musicUrl,
            'personality_result': personalityResult,
            'polygon': polygonPoints,
            'visibility': visibility,
          });
        }
      }
      
      setState(() {
        _statusMessage = "Loaded ${_areas.length} areas";
      });
    } catch (e) {
      setState(() {
        _statusMessage = "Failed to load GeoJSON data: $e";
      });
      log("Failed to load GeoJSON data: $e");
    }
  }

  // Request location permission
  Future<void> _requestLocationPermission() async {
    final status = await Permission.location.request();
    
    if (status.isGranted) {
      _startLocationTracking();
    } else {
      setState(() {
        _statusMessage = "Need location permission to use this app";
      });
    }
  }

  // Start location tracking
  void _startLocationTracking() {
    // Define location settings
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10, // Update every 10 meters
    );

    // Listen for location changes
    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings
    ).listen(_handlePositionUpdate);
    
    setState(() {
      _statusMessage = "Started tracking location...";
    });
  }

  // Handle position updates
  void _handlePositionUpdate(Position position) {
    setState(() {
      _currentPosition = position;
      _statusMessage = "Current position: ${position.latitude}, ${position.longitude}";
    });
    
    // Check if in any area
    _checkIfInAnyArea(position);
  }

  // Check if in any defined area
  void _checkIfInAnyArea(Position position) {
    final currentLat = position.latitude;
    final currentLng = position.longitude;
    
    for (var area in _areas) {
      final polygonCoords = area['polygon'] as List<List<double>>;
      
      // Use custom method to check if point is in polygon
      if (_isPointInPolygon(currentLng, currentLat, polygonCoords)) {
        // If in area and not current area, trigger new area action
        if (_currentArea == null || _currentArea!['name'] != area['name']) {
          _enterNewArea(area);
        }
        return;
      }
    }
    
    // If not in any area and previously in an area, leave the area
    if (_currentArea != null) {
      _leaveArea();
    }
  }
  
  // Custom method: Check if point is in polygon (Ray Casting Algorithm)
  bool _isPointInPolygon(double x, double y, List<List<double>> polygon) {
    // Implement Ray Casting Algorithm to check if point is in polygon
    bool isInside = false;
    int i = 0, j = polygon.length - 1;
    
    for (i = 0; i < polygon.length; i++) {
      if (((polygon[i][1] > y) != (polygon[j][1] > y)) &&
          (x < polygon[i][0] + (polygon[j][0] - polygon[i][0]) * (y - polygon[i][1]) / 
          (polygon[j][1] - polygon[i][1]))) {
        isInside = !isInside;
      }
      j = i;
    }
    
    return isInside;
  }

  // Handle entering a new area
  void _enterNewArea(Map<String, dynamic> area) {
    setState(() {
      _currentArea = area;
      _statusMessage = "You have entered the area: ${area['name']}";
    });
    
    // Get visibility value from the area
    final visibility = (area['visibility'] as int?) ?? 50;
    
    // Add to the calculator
    _personalityCalculator.addVisibilityValue(visibility);
    
    // Play the music of the area
    _playAreaMusic(area['music_url']);
    
    // Only show result when array is full and result hasn't been shown yet
    if (_personalityCalculator.isFull() && !_resultShown) {
      _showFinalPersonalityResult();
      _resultShown = true;
    }
  }

  // Handle leaving an area
  void _leaveArea() {
    setState(() {
      _currentArea = null;
      _statusMessage = "You have left the area";
      _isPlaying = false;
    });
    
    // Stop music playback
    _audioPlayer.stop();
  }

  // Play area music
  Future<void> _playAreaMusic(String musicUrl) async {
    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(UrlSource(musicUrl));
      setState(() {
        _isPlaying = true;
      });
    } catch (e) {
      log("Play music failed: $e");
      setState(() {
        _statusMessage = "Play music failed: $e";
      });
    }
  }

  // Show personality test result
  void _showPersonalityResult(String areaName, String personalityResult) {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                areaName,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                personalityResult,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text('Got it!'),
              ),
            ],
          ),
        );
      },
    );
  }

  // Show the final personality result dialog
  void _showFinalPersonalityResult() {
    String result = _personalityCalculator.determinePersonalityResult();
    double average = _personalityCalculator.calculateAverageVisibility();
    
    showDialog(
      context: context,
      barrierDismissible: false, // User must respond to dialog
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Your Personality Analysis Results'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Based on your visits to ${_personalityCalculator.visibilityValues.length} different areas:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 16),
              Text('Average Visibility Score: ${average.toStringAsFixed(1)}'),
              SizedBox(height: 4),
              // Show all collected values
              Wrap(
                spacing: 6,
                children: _personalityCalculator.visibilityValues
                    .map((v) => Chip(
                          label: Text('$v'),
                          backgroundColor: _getColorForVisibility(v),
                          labelStyle: TextStyle(fontSize: 12),
                          visualDensity: VisualDensity.compact,
                        ))
                    .toList(),
              ),
              SizedBox(height: 20),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  result,
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _resetCalculator();
              },
              child: Text('Start New Analysis'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Close'),
            ),
          ],
        );
      },
    );
  }

  // Reset the calculator
  void _resetCalculator() {
    setState(() {
      _personalityCalculator.reset();
      _resultShown = false;
      _statusMessage = "Starting a new personality analysis";
    });
  }

  // Helper method to generate colors based on visibility value
  Color _getColorForVisibility(int visibility) {
    if (visibility < 20) return Colors.indigo[100]!;
    if (visibility < 40) return Colors.blue[100]!;
    if (visibility < 60) return Colors.green[100]!;
    if (visibility < 80) return Colors.amber[100]!;
    return Colors.orange[100]!;
  }

  // Simulate location for testing
  void _simulateLocation(double lat, double lng) {
    final simulatedPosition = Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.now(),
      accuracy: 0,
      altitude: 0,
      heading: 0,
      speed: 0,
      speedAccuracy: 0,
      altitudeAccuracy: 0,
      headingAccuracy: 0,
    );
    
    _handlePositionUpdate(simulatedPosition);
  }

  void _completePath() {
    if (_currentPath.entries.isNotEmpty) {
      final results = _currentPath.completePath();
      setState(() {
        _pathResults = results;
        _showingPathResults = true;
      });
      _showPathResults(results);
    }
  }

  void _showPathResults(Map<String, dynamic> results) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Your Path Results'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Total Visibility Score: ${results['score']}'),
                SizedBox(height: 10),
                Text('Your Journey:'),
                ...List.generate(
                  results['path'].length,
                  (index) => Padding(
                    padding: EdgeInsets.only(left: 16.0, top: 4.0),
                    child: Text('${index + 1}. ${results['path'][index]}'),
                  ),
                ),
                SizedBox(height: 20),
                Text(
                  results['result'],
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _resetPath();
              },
              child: Text('Start New Path'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _resetPath() {
    setState(() {
      _currentPath.reset();
      _visitedAreas.clear();
      _pathResults = null;
      _showingPathResults = false;
      _statusMessage = "Starting a new journey";
    });
  }

  void _simulatePath(List<String> areaNames) {
    // Reset current path
    _resetPath();
    
    // Find the areas by name
    final areasToVisit = _areas.where((area) => 
      areaNames.contains(area['name'])).toList();
    
    if (areasToVisit.isEmpty) {
      setState(() {
        _statusMessage = "Could not find areas for simulation";
      });
      return;
    }
    
    // Add each area to the path
    for (var area in areasToVisit) {
      final areaName = area['name'] as String;
      final visibility = (area['visibility'] as int?) ?? 50;
      
      _currentPath.addArea(areaName, visibility);
      _visitedAreas.add(areaName);
      
      // Brief delay to simulate movement between areas
      Future.delayed(
        Duration(milliseconds: 500 * (areasToVisit.indexOf(area) + 1)), 
        () {
          setState(() {
            _statusMessage = "Visited ${areaName} (Visibility: $visibility)";
          });
        }
      );
    }
    
    // Show results after a delay
    Future.delayed(
      Duration(milliseconds: 500 * (areasToVisit.length + 1)),
      () => _completePath()
    );
  }

  // Simulate visiting multiple areas in sequence to fill the calculator
  void _simulateMultipleVisits(List<String> areaNames) {
    // Reset calculator first
    _resetCalculator();
    
    // Find areas that match the provided names
    final areasToVisit = _areas.where((area) => 
      areaNames.contains(area['name'])).toList();
    
    if (areasToVisit.isEmpty) {
      setState(() {
        _statusMessage = "Could not find areas for simulation";
      });
      return;
    }
    
    // Simulate visiting each area with a delay
    for (int i = 0; i < areasToVisit.length; i++) {
      final area = areasToVisit[i];
      
      // Add delay to create a sequence of visits
      Future.delayed(
        Duration(milliseconds: 1000 * (i + 1)), 
        () => _simulateAreaVisit(area),
      );
    }
  }

  // Simulate visiting a single area by using its center coordinates
  void _simulateAreaVisit(Map<String, dynamic> area) {
    // Get polygon coordinates
    final polygonCoords = area['polygon'] as List<List<double>>;
    
    // Calculate polygon center (simple average)
    double sumLat = 0;
    double sumLng = 0;
    
    for (var coord in polygonCoords) {
      sumLng += coord[0];
      sumLat += coord[1];
    }
    
    double centerLat = sumLat / polygonCoords.length;
    double centerLng = sumLng / polygonCoords.length;
    
    // Simulate location at center of the area
    _simulateLocation(centerLat, centerLng);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Geo Music Personality Test'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.location_on,
                    size: 80,
                    color: Colors.blue,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _statusMessage,
                    style: const TextStyle(fontSize: 18),
                    textAlign: TextAlign.center,
                  ),
                  if (_currentPosition != null) ...[
                    const SizedBox(height: 20),
                    Text(
                      'Latitude: ${_currentPosition!.latitude.toStringAsFixed(6)}\nLongitude: ${_currentPosition!.longitude.toStringAsFixed(6)}',
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (_currentArea != null) ...[
                    const SizedBox(height: 30),
                    Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade100,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'Current Area: ${_currentArea!['name']}',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (_isPlaying)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Icon(Icons.music_note),
                                SizedBox(width: 5),
                                Text('Playing music...'),
                              ],
                            ),
                          const SizedBox(height: 10),
                          ElevatedButton(
                            onPressed: () {
                              _showPersonalityResult(
                                _currentArea!['name'],
                                _currentArea!['personality_result'],
                              );
                            },
                            child: const Text('View personality analysis'),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  // Personality analysis progress card
                  Card(
                    margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Personality Analysis Progress',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Collecting ${_personalityCalculator.maxEntries} area visits to analyze your personality...',
                            style: TextStyle(fontSize: 14),
                          ),
                          SizedBox(height: 8),
                          // Add more guidance text if needed
                          if (!_personalityCalculator.isFull()) ...[
                            SizedBox(height: 8),
                            Text(
                              'Visit ${_personalityCalculator.maxEntries - _personalityCalculator.visibilityValues.length} more areas to see your result',
                              style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey[600]),
                            ),
                          ],
                          // Progress bar showing completion status
                          LinearProgressIndicator(
                            value: _personalityCalculator.getCompletionPercentage(),
                            backgroundColor: Colors.grey[200],
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Progress: ${_personalityCalculator.getProgressText()}',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                          // Display collected visibility values if any
                          if (_personalityCalculator.visibilityValues.isNotEmpty) ...[
                            SizedBox(height: 12),
                            Text('Recent visibility values:'),
                            SizedBox(height: 4),
                            Wrap(
                              spacing: 8,
                              children: _personalityCalculator.visibilityValues
                                  .map((value) => Chip(
                                        label: Text('$value'),
                                        backgroundColor: _getColorForVisibility(value),
                                      ))
                                  .toList(),
                            ),
                          ],
                          SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              OutlinedButton(
                                onPressed: _resetCalculator,
                                child: Text('Reset Analysis'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Path tracking information
                  Card(
                    margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Your Current Path',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 8),
                          if (_currentPath.entries.isEmpty)
                            Text('No areas visited yet. Start exploring!'),
                          if (_currentPath.entries.isNotEmpty) ...[
                            Text('Areas visited: ${_currentPath.entries.length}'),
                            SizedBox(height: 4),
                            Text('Total visibility score: ${_currentPath.calculateVisibilityScore()}'),
                            SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              children: _currentPath.getAreaNames()
                                  .map((name) => Chip(label: Text(name)))
                                  .toList(),
                            ),
                            SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                ElevatedButton(
                                  onPressed: _completePath,
                                  child: Text('Complete Path'),
                                ),
                                OutlinedButton(
                                  onPressed: _resetPath,
                                  child: Text('Reset Path'),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  // Test section
                  Card(
                    margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          Text('Test Functions',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          SizedBox(height: 8),
                          Text('Simulate individual locations:',
                              style: TextStyle(color: Colors.grey)),
                          SizedBox(height: 8),
                          // Test buttons for individual areas
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              ElevatedButton(
                                onPressed: () => _simulateLocation(31.25, 121.45),
                                child: const Text('Area 1'),
                              ),
                              ElevatedButton(
                                onPressed: () => _simulateLocation(31.35, 121.55),
                                child: const Text('Area 2'),
                              ),
                              ElevatedButton(
                                onPressed: () => _simulateLocation(31.45, 121.65),
                                child: const Text('Area 3'),
                              ),
                              ElevatedButton(
                                onPressed: () => _simulateLocation(31.45, 121.55),
                                child: const Text('Area 4'),
                              ),
                              ElevatedButton(
                                onPressed: () => _simulateLocation(30.0, 120.0),
                                child: const Text('Leave Area'),
                              ),
                            ],
                          ),
                          SizedBox(height: 16),
                          Text('Simulate area sequences:',
                              style: TextStyle(color: Colors.grey)),
                          SizedBox(height: 8),
                          // Test buttons for sequence simulation
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ElevatedButton(
                                onPressed: () => _simulateMultipleVisits(['Area 1', 'Area 2', 'Area 3', 'Area 4', 'Area 1']),
                                child: const Text('Sequence 1'),
                              ),
                              const SizedBox(width: 10),
                              ElevatedButton(
                                onPressed: () => _simulateMultipleVisits(['Area 4', 'Area 3', 'Area 2', 'Area 1', 'Area 4']),
                                child: const Text('Sequence 2'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
} 