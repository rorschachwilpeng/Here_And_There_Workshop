// lib/main.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'path_music_page.dart';

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
  // Current Position
  Position? _currentPosition;
  Map<String, dynamic>? _currentArea;
  StreamSubscription<Position>? _positionStreamSubscription;
  final List<Map<String, dynamic>> _areas = [];
  bool _isLoading = true;
  String _statusMessage = "Initializing...";
  
  // WebView related variables
  WebViewController? _webViewController;
  bool _isWebViewReady = false;
  
  // Music control related variables
  bool _isMusicPlaying = false;
  String _currentInstrument = 'synth';
  double _tempo = 120.0;
  double _visibility = 50.0;
  bool _showMusicControls = false;
  
  // Available instruments list
  final List<Map<String, dynamic>> _instruments = [
    {'value': 'synth', 'name': 'Basic Synth'},
    {'value': 'am', 'name': 'AM Synth'},
    {'value': 'fm', 'name': 'FM Synth'},
  ];

  // New: Track visited areas
  final List<Map<String, dynamic>> _visitedAreas = [];
  final int _requiredVisits = 5; // Number of areas to visit

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    super.dispose();
  }

  // Initialize the app
  Future<void> _initApp() async {
    setState(() {
      _statusMessage = "Loading data...";
    });
    
    // 1. Load GeoJSON data
    await _loadGeoJsonData();
    
    // 2. Initialize WebView
    await _initWebView();
    
    // 3. Request location permission and start tracking location
    await _requestLocationPermission();
    
    setState(() {
      _isLoading = false;
      _statusMessage = "Application is ready";
    });
  }

  // Initialize WebView
  Future<void> _initWebView() async {
    try {
      // Copy HTML file to local for WebView loading
      final htmlFile = await _copyAssetToLocal('assets/web/tone_engine.html');
      
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0x00000000)) // Transparent background
        ..addJavaScriptChannel(
          'FlutterChannel',
          onMessageReceived: _handleMessageFromJS,
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (String url) {
              setState(() {
                _isWebViewReady = true;
                _statusMessage = "Music engine loaded";
              });
            },
            onWebResourceError: (WebResourceError error) {
              setState(() {
                _statusMessage = "WebView error: ${error.description}";
              });
            },
          ),
        )
        ..loadFile(htmlFile.path);
        
      setState(() {
        _webViewController = controller;
      });
    } catch (e) {
      setState(() {
        _statusMessage = "WebView initialization error: $e";
      });
    }
  }
  
  // Copy resource files to local
  Future<File> _copyAssetToLocal(String assetPath) async {
    final directory = await getTemporaryDirectory();
    final path = '${directory.path}/tone_engine.html';
    final file = File(path);
    
    if (!await file.exists()) {
      final data = await rootBundle.load(assetPath);
      final bytes = data.buffer.asUint8List();
      await file.writeAsBytes(bytes);
    }
    
    return file;
  }
  
  // Handle messages from JavaScript
  void _handleMessageFromJS(JavaScriptMessage message) {
    try {
      final data = jsonDecode(message.message);
      setState(() {
        // Update UI status based on message
        if (data.containsKey('status')) {
          if (data['status'] == 'playing') {
            _isMusicPlaying = true;
          } else if (data['status'] == 'stopped') {
            _isMusicPlaying = false;
          }
        }
        
        // Update other states
        if (data.containsKey('instrument')) {
          _currentInstrument = data['instrument'];
        }
        if (data.containsKey('tempo')) {
          _tempo = double.tryParse(data['tempo'].toString()) ?? _tempo;
        }
        if (data.containsKey('visibility')) {
          _visibility = double.tryParse(data['visibility'].toString()) ?? _visibility;
        }
      });
    } catch (e) {
      print("Handle JavaScript message error: $e");
    }
  }
  
  // Send commands to JavaScript
  void _sendCommandToJs(String action, {Map<String, dynamic>? extraData}) {
    if (_webViewController == null || !_isWebViewReady) {
      print("Cannot send command: WebView not ready");
      return;
    }
    
    try {
      final Map<String, dynamic> data = {'action': action};
      if (extraData != null) {
        data.addAll(extraData);
      }
      
      final jsonMessage = jsonEncode(data);
      print("Sending command to JS: $jsonMessage");
      
      // Add error handling
      _webViewController!.runJavaScript(
        "try { if(typeof handleMessageFromFlutter === 'function') { "
        "handleMessageFromFlutter('$jsonMessage'); } else { "
        "console.error('Function not found'); document.getElementById('status').innerText = 'Error: Function not found'; }"
        "} catch(e) { console.error(e); document.getElementById('status').innerText = 'Error: ' + e; }"
      ).catchError((error) {
        print("JavaScript execution error: $error");
        setState(() {
          _statusMessage = "JavaScript execution error: $error";
        });
      });
    } catch (e) {
      print("Send command error: $e");
      setState(() {
        _statusMessage = "Send command error: $e";
      });
    }
  }

  // Load GeoJSON data
  Future<void> _loadGeoJsonData() async {
    try {
      // Read GeoJSON file
      final String geoJsonString = await rootBundle.loadString('assets/test.geojson');
      final Map<String, dynamic> geoJsonMap = json.decode(geoJsonString);
      
      // Parse GeoJSON features
      final features = geoJsonMap['features'] as List;
      
      for (var feature in features) {
        if (feature['geometry']['type'] == 'Polygon') {
          // Extract area properties
          final properties = feature['properties'];
          final name = properties['name'];
          final musicUrl = properties['music_url']; // Keep but may not be used
          final personalityResult = properties['personality_result'];
          final visibility = properties['visibility'] ?? 50; // Ensure reading visibility attribute
          
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
      
      _debugGeoJsonData();
    } catch (e) {
      setState(() {
        _statusMessage = "Failed to load GeoJSON data: $e";
      });
      print("Failed to load GeoJSON data: $e");
    }
  }

  void _debugGeoJsonData() {
    print("====== GeoJSON data debugging ======");
    print("Total areas: ${_areas.length}");
    
    for (int i = 0; i < _areas.length; i++) {
      final area = _areas[i];
      print("Area ${i+1}: ${area['name']}");
      print("  Visibility: ${area['visibility']}");
      print("  Boundary points: ${(area['polygon'] as List).length}");
    }
    
    print("====== Area list end ======");
  }

  // Location permission and tracking -基本保持原有实现
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

  void _startLocationTracking() {
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );

    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings
    ).listen(_handlePositionUpdate);
    
    setState(() {
      _statusMessage = "Start tracking location...";
    });
  }

  void _handlePositionUpdate(Position position) {
    setState(() {
      _currentPosition = position;
      _statusMessage = "Current position: ${position.latitude}, ${position.longitude}";
    });
    
    // Check if in any area
    _checkIfInAnyArea(position);
  }

  // Check if in any defined area - keep original algorithm logic
  void _checkIfInAnyArea(Position position) {
    final currentLat = position.latitude;
    final currentLng = position.longitude;
    
    print("Check if position ($currentLat, $currentLng) is in any area");
    
    for (var area in _areas) {
      final polygonCoords = area['polygon'] as List<List<double>>;
      bool isInside = _isPointInPolygon(currentLng, currentLat, polygonCoords);
      print("Area: ${area['name']} - Point inside: $isInside");
      
      if (isInside) {
        // If inside and not current area, trigger new area action
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
  
  // Custom method: Determine if a point is inside a polygon (ray casting method)
  bool _isPointInPolygon(double x, double y, List<List<double>> polygon) {
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

  // Enter new area
  void _enterNewArea(Map<String, dynamic> area) {
    print("Attempting to enter area: ${area['name']}, current visited areas count: ${_visitedAreas.length}");
    print("Current visited areas: ${_visitedAreas.map((a) => a['name']).join(', ')}");
    
    // Check if already visited this area
    bool alreadyVisited = _visitedAreas.any((visitedArea) => 
      visitedArea['name'] == area['name']);
    
    print("Already visited this area: $alreadyVisited");
    
    setState(() {
      _currentArea = area;
      _statusMessage = "You have entered area: ${area['name']}";
      
      // If new area, add to visited list
      if (!alreadyVisited) {
        _visitedAreas.add(Map<String, dynamic>.from(area));
        // Sort visited areas to ensure consistent order
        _visitedAreas.sort((a, b) => a['name'].compareTo(b['name']));
        print("After adding, visited areas count: ${_visitedAreas.length}");
        print("Visited areas list: ${_visitedAreas.map((a) => a['name']).join(', ')}");
      }
    });
    
    // Get area visibility value
    final visibility = (area['visibility'] as int?) ?? 50;
    
    // Update visibility slider
    setState(() {
      _visibility = visibility.toDouble();
    });
    
    // Ensure music playback - add debug output
    print("Attempting to play music, visibility: $visibility");
    if (!_isMusicPlaying) {
      print("Start playing music");
      _startMusic();
    } else {
      print("Update music parameters");
      _sendCommandToJs('changeVisibility', extraData: {'value': visibility.toString()});
    }
    
    // If visited areas count meets requirement, show final result
    if (_visitedAreas.length >= _requiredVisits && !alreadyVisited) {
      _showFinalPersonalityResult();
    } else {
      // Show area info without personality test result
      _showAreaInfo(area['name']);
    }
  }

  // New: Show area info (without personality test result)
  void _showAreaInfo(String areaName) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Entered area: $areaName, Visited ${_visitedAreas.length}/${_requiredVisits} areas'),
        duration: Duration(seconds: 2),
      ),
    );
  }
  
  // New: Show final personality test result
  void _showFinalPersonalityResult() {
    // 计算平均可见度
    double avgVisibility = _visitedAreas.fold(0.0, (sum, area) => 
        sum + ((area['visibility'] as int?) ?? 50)) / _visitedAreas.length;
    
    // 选择结果文本
    String resultText;
    if (avgVisibility < 30) {
      resultText = "You are a very mysterious person, inclined to deep thinking";
    } else if (avgVisibility < 70) {
      resultText = "You are a balanced person, able to appreciate life's details and see the path ahead.";
    } else {
      resultText = "You are an open and optimistic person, who loves to share and explore, always finding beauty in life.";
    }
    
    // 使用简洁的Material 3风格
    showDialog(
      context: context,
      builder: (context) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: Text('Personality Analysis Result'),
            leading: IconButton(
              icon: Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  Icons.psychology,
                  size: 64,
                  color: Theme.of(context).primaryColor,
                ),
                SizedBox(height: 16),
                Text(
                  'Average Visibility: ${avgVisibility.toStringAsFixed(1)}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 24),
                Text(
                  resultText,
                  style: TextStyle(fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                Spacer(),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('I understand'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: Size(double.infinity, 48),
                  ),
                ),
                SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  // Leave area processing - modified to stop music
  void _leaveArea() {
    setState(() {
      _currentArea = null;
      _statusMessage = "You have left the area";
    });
    
    // Stop music
    _stopMusic();
  }

  // New: Start music method
  void _startMusic() {
    if (!_isWebViewReady) {
      print("WebView not ready, cannot play music");
      setState(() {
        _statusMessage = "WebView not ready, trying to reload page...";
      });
      // Try to reload WebView
      _initWebView();
      return;
    }
    
    print("Sending start playing music command, parameters: visibility=${_visibility.toInt()}, tempo=${_tempo.toInt()}, instrument=$_currentInstrument");
    _sendCommandToJs('start', extraData: {
      'visibility': _visibility.toInt().toString(),
      'tempo': _tempo.toInt().toString(),
      'instrument': _currentInstrument,
    });
    
    setState(() {
      _isMusicPlaying = true;
      _statusMessage = "Current Instrument: (${_currentInstrument}, ${_tempo.toInt()} BPM)";
    });
  }
  
  // New: Stop music method
  void _stopMusic() {
    if (!_isWebViewReady) return;
    
    _sendCommandToJs('stop');
    
    setState(() {
      _isMusicPlaying = false;
    });
  }
  
  // Update music parameters
  void _updateMusicParameters() {
    if (!_isWebViewReady || !_isMusicPlaying) return;
    
    _sendCommandToJs('updateParameters', extraData: {
      'visibility': _visibility.toInt().toString(),
      'tempo': _tempo.toInt().toString(),
      'instrument': _currentInstrument,
    });
  }

  // Modify to simulate location
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
  
  // Toggle music controls panel display status
  void _toggleMusicControls() {
    setState(() {
      _showMusicControls = !_showMusicControls;
    });
  }

  // Add to class as a new method
  void _testAddAllAreas() {
    print("Total areas: ${_areas.length}");
    
    // Prepare the list of areas to add
    List<Map<String, dynamic>> areasToAdd = [];
    
    // Copy existing areas
    for (var area in _areas) {
      areasToAdd.add(Map<String, dynamic>.from(area));
    }
    
    // If the number of areas is less than the required number, add additional areas
    if (areasToAdd.length < _requiredVisits) {
      for (int i = areasToAdd.length; i < _requiredVisits; i++) {
        // Ensure necessary fields are added
        areasToAdd.add({
          'name': 'Area ${i+1}',
          'personality_result': 'This is the personality result for the automatically added area ${i+1}',
          'visibility': 40 + (i * 10),
          'polygon': [[121.0, 31.0], [121.1, 31.0], [121.1, 31.1], [121.0, 31.1], [121.0, 31.0]], // Add necessary polygon field
          'music_url': '', // Add possible other fields
        });
      }
    }
    
    print("Number of areas to add: ${areasToAdd.length}");
    
    // Clear and add all areas at once (avoid multiple setStates)
    setState(() {
      _visitedAreas.clear();
      
      for (int i = 0; i < _requiredVisits && i < areasToAdd.length; i++) {
        _visitedAreas.add(Map<String, dynamic>.from(areasToAdd[i]));
        print("Added area ${areasToAdd[i]['name']}");
      }
      
      print("After adding, visited areas count: ${_visitedAreas.length}");
      print("Visited areas: ${_visitedAreas.map((a) => a['name']).join(', ')}");
    });
    
    // If enough areas are successfully added, show the result
    if (_visitedAreas.length >= _requiredVisits) {
      _showFinalPersonalityResult();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to add enough areas: need ${_requiredVisits}, but only added ${_visitedAreas.length}'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  // Clear visited areas method
  void _clearVisitedAreas() {
    setState(() {
      _visitedAreas.clear();
      
      // Update status message
      _statusMessage = "All visited areas have been cleared";
    });
    
    // Show prompt message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('All visited areas have been cleared'),
        duration: Duration(seconds: 2),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            // Do not implement undo functionality, if needed, save a backup first
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Cannot undo'),
                duration: Duration(seconds: 1),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Geographic Music Personality Test'),
        actions: [
          // Add clear button
          IconButton(
            icon: Icon(Icons.delete_sweep),
            onPressed: _clearVisitedAreas,
            tooltip: 'Clear visited areas',
          ),
          // Existing music control button
          IconButton(
            icon: Icon(_showMusicControls ? Icons.music_off : Icons.music_note),
            onPressed: _toggleMusicControls,
            tooltip: 'Music control',
          ),
          // Refresh WebView button
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: () {
              _initWebView();
            },
            tooltip: 'Reload music engine',
          ),
          IconButton(
            icon: Icon(Icons.music_note),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => PathMusicPage()));
            },
            tooltip: '体验音乐路径',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                // Display WebView for debugging (can be hidden in release version)
                Positioned(
                  top: 0,
                  left: 0,
                  width: 300, // Visible for debugging
                  height: 100, // Visible for debugging
                  child: Opacity(
                    opacity: 0.3, // Transparent for debugging
                    child: _webViewController != null
                        ? WebViewWidget(controller: _webViewController!)
                        : Container(color: Colors.red, child: Text("No WebView")),
                  ),
                ),
                
                // Main content
                SingleChildScrollView(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 100), // Space for debugging WebView
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
                      
                      // Visited areas display
                      if (_visitedAreas.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(15),
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade100,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            children: [
                              Text(
                                'Visited areas: ${_visitedAreas.length}/${_requiredVisits}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                alignment: WrapAlignment.center,
                                children: _visitedAreas.map((area) => Chip(
                                  label: Text(area['name']),
                                  avatar: CircleAvatar(
                                    child: Text('${area['visibility']}'),
                                    backgroundColor: Colors.blue,
                                  ),
                                )).toList(),
                              ),
                              if (_visitedAreas.length >= _requiredVisits) ...[
                                const SizedBox(height: 10),
                                ElevatedButton(
                                  onPressed: _showFinalPersonalityResult,
                                  child: const Text('View complete personality analysis'),
                                ),
                              ] else ...[
                                const SizedBox(height: 10),
                                Text(
                                  'Need to visit ${_requiredVisits - _visitedAreas.length} more areas to view complete personality analysis',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                      
                      if (_currentArea != null) ...[
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(15),
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade100,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            children: [
                              Text(
                                'Current area: ${_currentArea!['name']}',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.visibility),
                                  const SizedBox(width: 5),
                                  Text('Visibility: ${_currentArea!['visibility']}'),
                                ],
                              ),
                              if (_isMusicPlaying) ...[
                                const SizedBox(height: 10),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Icon(Icons.music_note, color: Colors.green),
                                    SizedBox(width: 5),
                                    Text('Music is playing', style: TextStyle(color: Colors.green)),
                                  ],
                                ),
                              ] else ...[
                                const SizedBox(height: 10),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Icon(Icons.music_off, color: Colors.red),
                                    SizedBox(width: 5),
                                    Text('Music is not playing', style: TextStyle(color: Colors.red)),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                ElevatedButton(
                                  onPressed: _startMusic,
                                  child: const Text('Manually start music'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                      
                      // Music control panel
                      if (_showMusicControls) ...[
                        const SizedBox(height: 30),
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Music control',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  ElevatedButton(
                                    onPressed: () {
                                      if (_isMusicPlaying) {
                                        _stopMusic();
                                      } else {
                                        _startMusic();
                                      }
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _isMusicPlaying
                                          ? Colors.red
                                          : Colors.green,
                                    ),
                                    child: Text(_isMusicPlaying ? 'Stop' : 'Play'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              
                              // Instrument selection
                              Text('Instrument:'),
                              const SizedBox(height: 8),
                              DropdownButton<String>(
                                value: _currentInstrument,
                                isExpanded: true,
                                items: _instruments.map((instrument) {
                                  return DropdownMenuItem<String>(
                                    value: instrument['value'] as String,
                                    child: Text(instrument['name'] as String),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  if (value != null) {
                                    setState(() {
                                      _currentInstrument = value;
                                    });
                                    _sendCommandToJs('changeInstrument', extraData: {'value': value});
                                  }
                                },
                              ),
                              
                              const SizedBox(height: 16),
                              
                              // Speed slider
                              Text('Speed: ${_tempo.toInt()} BPM'),
                              Slider(
                                value: _tempo,
                                min: 60,
                                max: 200,
                                divisions: 140,
                                label: _tempo.toInt().toString(),
                                onChanged: (value) {
                                  setState(() {
                                    _tempo = value;
                                  });
                                  _sendCommandToJs('changeTempo', extraData: {'value': value.toInt().toString()});
                                },
                              ),
                              
                              const SizedBox(height: 16),
                              
                              // Visibility slider
                              Text('Visibility: ${_visibility.toInt()}%'),
                              Slider(
                                value: _visibility,
                                min: 0,
                                max: 100,
                                divisions: 100,
                                label: _visibility.toInt().toString(),
                                onChanged: (value) {
                                  setState(() {
                                    _visibility = value;
                                  });
                                  _sendCommandToJs('changeVisibility', extraData: {'value': value.toInt().toString()});
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                      
                      const SizedBox(height: 30),
                      // Test button
                      Text('Test button (simulate location)',
                          style: TextStyle(color: Colors.grey)),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            ElevatedButton(
                              onPressed: () {
                                _simulateLocation(31.25, 121.45);
                              },
                              child: const Text('Area 1 (25%)'),
                            ),
                            ElevatedButton(
                              onPressed: () {
                                _simulateLocation(31.35, 121.55);
                              },
                              child: const Text('Area 2 (50%)'),
                            ),
                            ElevatedButton(
                              onPressed: () {
                                _simulateLocation(31.45, 121.65);
                              },
                              child: const Text('Area 3 (75%)'),
                            ),
                            ElevatedButton(
                              onPressed: () {
                                _simulateLocation(31.45, 121.55);
                              },
                              child: const Text('Area 4 (90%)'),
                            ),
                            ElevatedButton(
                              onPressed: () {
                                _simulateLocation(31.55, 121.75);
                              },
                              child: const Text('Area 5 (40%)'),
                            ),
                            ElevatedButton(
                              onPressed: () {
                                _simulateLocation(30.0, 120.0);
                              },
                              child: const Text('Leave area'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}