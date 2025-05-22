import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

class MusicController {
  static final MusicController _instance = MusicController._internal();
  
  factory MusicController() {
    return _instance;
  }
  
  MusicController._internal();
  
  // WebView controller
  WebViewController? _controller;
  
  // Music state
  bool isPlaying = false;
  String currentInstrument = 'synth';
  double tempo = 120.0;
  double visibility = 50.0;
  String statusMessage = 'Ready';
  
  // Callback for status updates
  Function(String)? onStatusChanged;
  
  // Initialize the WebView
  Future<void> initialize() async {
    if (_controller != null) return;
    
    try {
      // Copy HTML file to a local path that can be loaded by WebView
      final htmlFile = await _copyAssetToLocal('assets/web/tone_engine.html');
      
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0x00000000))
        ..addJavaScriptChannel(
          'FlutterChannel',
          onMessageReceived: _handleMessageFromJS,
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (String url) {
              _updateStatus("WebView loaded");
            },
            onWebResourceError: (WebResourceError error) {
              _updateStatus("WebView error: ${error.description}");
            },
          ),
        )
        ..loadFile(htmlFile.path);
        
      _controller = controller;
      _updateStatus("Music controller initialized");
    } catch (e) {
      _updateStatus("Initialization error: $e");
    }
  }
  
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
  
  void _handleMessageFromJS(JavaScriptMessage message) {
    final data = jsonDecode(message.message);
    statusMessage = data['status'] ?? 'Unknown';
    _updateStatus(statusMessage);
  }
  
  void _updateStatus(String status) {
    statusMessage = status;
    if (onStatusChanged != null) {
      onStatusChanged!(status);
    }
  }
  
  // Music control methods
  void startMusic(double visibilityValue) {
    if (_controller == null) return;
    
    visibility = visibilityValue;
    isPlaying = true;
    
    _sendCommandToJs('start', extraData: {'visibility': visibility.toInt().toString()});
    _updateStatus("Starting music");
  }
  
  void stopMusic() {
    if (_controller == null) return;
    
    isPlaying = false;
    _sendCommandToJs('stop');
    _updateStatus("Music stopped");
  }
  
  void changeInstrument(String instrument) {
    if (_controller == null) return;
    
    currentInstrument = instrument;
    _sendCommandToJs('changeInstrument', extraData: {'value': instrument});
    _updateStatus("Instrument changed to: $instrument");
  }
  
  void changeTempo(double newTempo) {
    if (_controller == null) return;
    
    tempo = newTempo;
    _sendCommandToJs('changeTempo', extraData: {'value': tempo.toInt().toString()});
    _updateStatus("Tempo changed to: ${tempo.toInt()}");
  }
  
  void updateVisibility(double newVisibility) {
    if (_controller == null) return;
    
    visibility = newVisibility;
    _sendCommandToJs('changeVisibility', extraData: {'value': visibility.toInt().toString()});
    _updateStatus("Visibility updated to: ${visibility.toInt()}");
  }
  
  void _sendCommandToJs(String action, {Map<String, dynamic>? extraData}) {
    if (_controller == null) return;
    
    try {
      final Map<String, dynamic> data = {'action': action};
      if (extraData != null) {
        data.addAll(extraData);
      }
      
      final jsonMessage = jsonEncode(data);
      
      _controller!.runJavaScript(
        'if(typeof handleMessageFromFlutter === "function") { handleMessageFromFlutter(\'$jsonMessage\'); } else { console.error("Function not found"); }'
      ).catchError((error) {
        _updateStatus("JavaScript error: $error");
      });
    } catch (e) {
      _updateStatus("Command error: $e");
    }
  }
  
  // Get WebView widget
  WebViewController? get controller => _controller;
  
  // Dispose resources
  void dispose() {
    isPlaying = false;
    _controller = null;
  }
}
