import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

class MusicTestPage extends StatefulWidget {
  const MusicTestPage({Key? key}) : super(key: key);

  @override
  _MusicTestPageState createState() => _MusicTestPageState();
}

class _MusicTestPageState extends State<MusicTestPage> {
  WebViewController? _controller;
  bool _isPlaying = false;
  double _visibility = 50.0;
  String _currentInstrument = 'synth';
  double _tempo = 120.0;
  String _statusMessage = 'Ready';
  
  // Available instruments
  final List<Map<String, dynamic>> _instruments = [
    {'value': 'synth', 'name': 'Basic Synth'},
    {'value': 'am', 'name': 'AM Synth'},
    {'value': 'fm', 'name': 'FM Synth'},
  ];
  
  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  Future<void> _initWebView() async {
    // Copy HTML file to a local path that can be loaded by WebView
    final htmlFile = await _copyAssetToLocal('assets/web/tone_engine.html');
    
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..addJavaScriptChannel(
        'FlutterChannel',
        onMessageReceived: _handleMessageFromJS,
      )
      ..loadFile(htmlFile.path);
      
    setState(() {
      _controller = controller;
    });
  }
  
  void _handleMessageFromJS(JavaScriptMessage message) {
    final data = jsonDecode(message.message);
    setState(() {
      _statusMessage = data['status'] ?? 'Unknown';
    });
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
  
  void _sendCommandToJs(String action, {Map<String, dynamic>? extraData}) {
    if (_controller == null) return;
    
    final Map<String, dynamic> data = {'action': action};
    if (extraData != null) {
      data.addAll(extraData);
    }
    
    final jsonMessage = jsonEncode(data);
    _controller!.runJavaScript(
      'handleMessageFromFlutter(\'$jsonMessage\')'
    );
  }
  
  void _togglePlayStop() {
    setState(() {
      _isPlaying = !_isPlaying;
    });
    
    if (_isPlaying) {
      _sendCommandToJs('start', extraData: {'visibility': _visibility.toInt()});
    } else {
      _sendCommandToJs('stop');
    }
  }
  
  void _changeInstrument(String instrument) {
    setState(() {
      _currentInstrument = instrument;
    });
    _sendCommandToJs('changeInstrument', extraData: {'value': instrument});
  }
  
  void _changeTempo(double tempo) {
    setState(() {
      _tempo = tempo;
    });
    _sendCommandToJs('changeTempo', extraData: {'value': tempo.toInt().toString()});
  }
  
  void _changeVisibility(double visibility) {
    setState(() {
      _visibility = visibility;
    });
    _sendCommandToJs('changeVisibility', extraData: {'value': visibility.toInt().toString()});
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Tone.js Music Test'),
      ),
      body: Column(
        children: [
          // WebView (hidden but functional)
          SizedBox(
            height: 1, // Almost hidden
            child: _controller != null 
              ? WebViewWidget(controller: _controller!)
              : CircularProgressIndicator(),
          ),
          
          // Status and controls
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Status card
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            Text(
                              'Music Engine Status',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text('Status: $_statusMessage'),
                            Text('Current Visibility: ${_visibility.toInt()}'),
                          ],
                        ),
                      ),
                    ),
                    
                    SizedBox(height: 16),
                    
                    // Play/Stop button
                    ElevatedButton(
                      onPressed: _togglePlayStop,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isPlaying ? Colors.red : Colors.green,
                        padding: EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        _isPlaying ? 'Stop Music' : 'Start Music',
                        style: TextStyle(fontSize: 18),
                      ),
                    ),
                    
                    SizedBox(height: 24),
                    
                    // Controls section
                    Text(
                      'Music Controls',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    
                    SizedBox(height: 16),
                    
                    // Instrument selection
                    Text('Instrument:'),
                    SizedBox(height: 8),
                    DropdownButton<String>(
                      value: _currentInstrument,
                      isExpanded: true,
                      items: _instruments.map((instrument) {
                        return DropdownMenuItem<String>(
                          value: instrument['value'],
                          child: Text(instrument['name']),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          _changeInstrument(value);
                        }
                      },
                    ),
                    
                    SizedBox(height: 16),
                    
                    // Tempo slider
                    Text('Tempo: ${_tempo.toInt()} BPM'),
                    Slider(
                      value: _tempo,
                      min: 60,
                      max: 200,
                      divisions: 140,
                      label: _tempo.toInt().toString(),
                      onChanged: _changeTempo,
                    ),
                    
                    SizedBox(height: 16),
                    
                    // Visibility slider (simulating environment effect)
                    Text('Visibility: ${_visibility.toInt()}%'),
                    Slider(
                      value: _visibility,
                      min: 0,
                      max: 100,
                      divisions: 100,
                      label: _visibility.toInt().toString(),
                      onChanged: _changeVisibility,
                    ),
                    
                    SizedBox(height: 16),
                    
                    // Explanation
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'How it works:',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            SizedBox(height: 8),
                            Text('1. Start the music engine'),
                            Text('2. Change visibility to simulate different environments'),
                            Text('3. Low visibility (0-30): darker, more reverb'),
                            Text('4. Medium visibility (30-70): balanced sound'),
                            Text('5. High visibility (70-100): brighter, less reverb'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
