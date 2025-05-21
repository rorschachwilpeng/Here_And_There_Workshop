import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';

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
    
    // Play the music of the area
    _playAreaMusic(area['music_url']);
    
    // Show personality test result
    _showPersonalityResult(area['name'], area['personality_result']);
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
                child: const Text('了解了'),
              ),
            ],
          ),
        );
      },
    );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Geo Music Personality Test'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
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
                const SizedBox(height: 30),
                // Test button
                Text('Test Button (Simulate Location)',
                    style: TextStyle(color: Colors.grey)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        // Simulate entering test area 1
                        _simulateLocation(31.25, 121.45);
                      },
                      child: const Text('Area 1'),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: () {
                        // Simulate entering test area 2
                        _simulateLocation(31.35, 121.55);
                      },
                      child: const Text('Area 2'),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: () {
                        // Simulate leaving all areas
                        _simulateLocation(30.0, 120.0);
                      },
                      child: const Text('Leave Area'),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
} 