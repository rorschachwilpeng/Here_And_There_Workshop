import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'music_controller.dart';
import 'package:webview_flutter/webview_flutter.dart';

class PathMusicPage extends StatefulWidget {
  const PathMusicPage({Key? key}) : super(key: key);

  @override
  _PathMusicPageState createState() => _PathMusicPageState();
}

class _PathMusicPageState extends State<PathMusicPage> {
  // 音乐控制器
  final MusicController _musicController = MusicController();
  
  // 路径数据
  List<Map<String, dynamic>> _path1Points = [];
  List<Map<String, dynamic>> _path2Points = [];
  
  // 当前状态
  bool _isPlaying = false;
  int _currentPathIndex = 0;  // 1 表示 path 1, 2 表示 path 2
  int _currentPointIndex = 0;
  Timer? _pathSimulationTimer;
  String _statusMessage = "Ready";
  double _currentVisibility = 50.0;
  
  // 替换为从JSON加载的数据
  List<int> _path1VisibilityData = [];
  List<int> _path2VisibilityData = [];
  
  @override
  void initState() {
    super.initState();
    _initPage();
  }
  
  @override
  void dispose() {
    // 停止模拟和定时器
    _stopPathSimulation();
    
    // 移除状态变更回调
    _musicController.onStatusChanged = null;
    
    // 在处理控制器前先停止音乐，确保不会有后续回调
    if (_isPlaying) {
      _musicController.stopMusic();
    }
    
    // 移除控制器
    _musicController.dispose();
    
    // 最后调用父类方法
    super.dispose();
  }
  
  // 初始化页面
  Future<void> _initPage() async {
    // 初始化音乐控制器
    await _musicController.initialize();
    
    // 加载 GeoJSON 数据
    await _loadGeoJsonData();
    
    // 更新状态
    _musicController.onStatusChanged = (message) {
      setState(() {
        _statusMessage = message;
      });
    };
  }
  
  // 加载 GeoJSON 数据 - 同时设置Points数组
  Future<void> _loadGeoJsonData() async {
    try {
      // 设置默认数据
      _path1VisibilityData = [80, 74, 87, 85, 44, 2, 95, 89, 71, 67, 37, 67, 86];
      _path2VisibilityData = [66, 71, 31, 50, 55, 67, 78, 38, 60, 85, 87, 28, 38, 40, 43];
      
      // 同时设置点数据数组
      _path1Points = [];
      _path2Points = [];
      
      // 为每个可见度值创建相应的点数据
      for (int i = 0; i < _path1VisibilityData.length; i++) {
        _path1Points.add({
          'id': 1000 + i,
          'visibility_score': _path1VisibilityData[i],
          'row_index': i,
          'col_index': 0,
        });
      }
      
      // 尝试从文件加载，但不覆盖默认值
      try {
        final String data = await rootBundle.loadString('assets/grid_scored.geojson');
        final jsonResult = jsonDecode(data);
        final features = jsonResult['features'] as List;
        
        // 输出特征点数量（仅供参考）
        print("GeoJSON文件中的特征点数量: ${features.length}");
      } catch (e) {
        print("GeoJSON文件加载警告: $e");
      }
      
      setState(() {
        _statusMessage = "数据加载完成，Path 1: ${_path1VisibilityData.length}个点, Path 2: ${_path2VisibilityData.length}个点";
      });
      
      print("Path 1 visibility: $_path1VisibilityData");
      print("Path 2 visibility: $_path2VisibilityData");
      
    } catch (e) {
      print("数据加载错误: $e");
      setState(() {
        _statusMessage = "数据加载错误: $e";
        
        // 确保默认数据仍然可用
        _path1VisibilityData = [80, 74, 87, 85, 44, 2, 95, 89, 71, 67, 37, 67, 86];
        _path2VisibilityData = [66, 71, 31, 50, 55, 67, 78, 38, 60, 85, 87, 28, 38, 40, 43];
      });
    }
  }
  
  // 开始路径模拟
  void _startPathSimulation(int pathIndex) {
    // 停止任何正在进行的模拟
    _stopPathSimulation();
    
    // 获取当前使用的可见度数据
    List<int> visibilityData = pathIndex == 1 ? _path1VisibilityData : _path2VisibilityData;
    
    if (visibilityData.isEmpty) {
      setState(() {
        _statusMessage = "Path $pathIndex has no available points";
        _isPlaying = false;
      });
      return;
    }
    
    setState(() {
      _isPlaying = true;
      _currentPathIndex = pathIndex;
      _currentPointIndex = 0;
      _currentVisibility = visibilityData[0].toDouble();
    });
    
    // 开始音乐
    _musicController.startMusic(_currentVisibility);
    
    // 设置定时器，每2秒移动到下一个点
    _pathSimulationTimer = Timer.periodic(Duration(seconds: 5), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      setState(() {
        _currentPointIndex++;
      });
      
      // 检查是否到达路径末端
      if (_currentPointIndex >= visibilityData.length) {
        _stopPathSimulation();
        if (mounted) {
          setState(() {
            _statusMessage = "Path $pathIndex completed!";
          });
        }
        return;
      }
      
      // 更新下一个点的可见度
      _updateVisibility(visibilityData[_currentPointIndex].toDouble());
    });
  }
  
  // 停止路径模拟
  void _stopPathSimulation() {
    _pathSimulationTimer?.cancel();
    _pathSimulationTimer = null;
    
    if (_isPlaying) {
      _musicController.stopMusic();
      setState(() {
        _isPlaying = false;
      });
    }
  }
  
  // 更新可见度和音乐
  void _updateVisibility(double visibility) {
    if (!mounted) return;
    
    setState(() {
      _currentVisibility = visibility;
    });
    _musicController.updateVisibility(visibility);
  }
  
  // 根据可见度获取颜色
  Color _getColorForVisibility(double visibility) {
    if (visibility < 30) {
      return Colors.red;
    } else if (visibility < 60) {
      return Colors.orange;
    } else if (visibility < 80) {
      return Colors.blue;
    } else {
      return Colors.green;
    }
  }
  
  @override
  Widget build(BuildContext context) {
    // 获取当前路径和点
    final List<Map<String, dynamic>> currentPoints = 
        _currentPathIndex == 1 ? _path1Points : _path2Points;
    
    // 计算当前进度
    final double progress = currentPoints.isEmpty 
        ? 0.0 
        : _currentPointIndex / (currentPoints.length - 1);
    
    return Scaffold(
      appBar: AppBar(
        title: Text('muVz'),
      ),
      body: Column(
        children: [
          // WebView容器（不可见但必须存在）
          if (_musicController.controller != null)
            SizedBox(
              height: 1, // 几乎不可见
              child: WebViewWidget(controller: _musicController.controller!),
            ),
          
          // 主要内容
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 状态卡片
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            Text(
                              'Music Path Experience',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 10),
                            Text('Status: $_statusMessage'),
                            if (_isPlaying) ...[
                              SizedBox(height: 15),
                              // 添加一个更醒目的可见度显示区域
                              Container(
                                padding: EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.grey.shade400),
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      'Visibility: ${_currentVisibility.toInt()}%',
                                      style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                        color: _getColorForVisibility(_currentVisibility),
                                      ),
                                    ),
                                    SizedBox(height: 8),
                                    LinearProgressIndicator(
                                      value: _currentVisibility / 100,
                                      backgroundColor: Colors.grey.shade300,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        _getColorForVisibility(_currentVisibility),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(height: 10),
                              Text('Current Path: Path $_currentPathIndex'),
                              SizedBox(height: 5),
                              Text('Progress: ${_currentPointIndex + 1}/${_currentPathIndex == 1 ? _path1VisibilityData.length : _path2VisibilityData.length}'),
                              SizedBox(height: 10),
                              LinearProgressIndicator(
                                value: (_currentPointIndex + 1) / 
                                      (_currentPathIndex == 1 ? _path1VisibilityData.length : _path2VisibilityData.length),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    
                    SizedBox(height: 30),
                    
                    // 路径选择按钮
                    if (!_isPlaying) ...[
                      Text(
                        'Select Experience Path',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => _startPathSimulation(1),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                padding: EdgeInsets.symmetric(vertical: 15),
                              ),
                              child: Column(
                                children: [
                                  Icon(Icons.route, size: 36),
                                  SizedBox(height: 10),
                                  Text(
                                    'Path 1',
                                    style: TextStyle(fontSize: 18),
                                  ),
                                  SizedBox(height: 5),
                                  Text(
                                    'High Visibility Path',
                                    style: TextStyle(fontSize: 14),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(width: 15),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => _startPathSimulation(2),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                padding: EdgeInsets.symmetric(vertical: 15),
                              ),
                              child: Column(
                                children: [
                                  Icon(Icons.route, size: 36),
                                  SizedBox(height: 10),
                                  Text(
                                    'Path 2',
                                    style: TextStyle(fontSize: 18),
                                  ),
                                  SizedBox(height: 5),
                                  Text(
                                    'Low Visibility Path',
                                    style: TextStyle(fontSize: 14),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      // 停止按钮
                      ElevatedButton(
                        onPressed: _stopPathSimulation,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          padding: EdgeInsets.symmetric(vertical: 15),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.stop),
                            SizedBox(width: 10),
                            Text(
                              'Stop Experience',
                              style: TextStyle(fontSize: 18),
                            ),
                          ],
                        ),
                      ),
                    ],
                    
                    SizedBox(height: 20),
                    
                    // 路径说明
                    // Card(
                    //   child: Padding(
                    //     padding: const EdgeInsets.all(16.0),
                    //     child: Column(
                    //       crossAxisAlignment: CrossAxisAlignment.start,
                    //       children: [
                    //         Text(
                    //           'About Music Path Experience',
                    //           style: TextStyle(
                    //             fontSize: 18,
                    //             fontWeight: FontWeight.bold,
                    //           ),
                    //         ),
                    //         SizedBox(height: 10),
                    //         Text('This application simulates a user walking along two different paths and generates dynamic music based on the visibility changes along the paths:'),
                    //         SizedBox(height: 8),
                    //         Text('• Path 1: Mainly high visibility areas, music bright and open'),
                    //         Text('• Path 2: Includes areas of varying visibility, music varies'),
                    //         SizedBox(height: 8),
                    //         Text('As the simulated journey progresses, the music will automatically adjust dynamically based on the visibility score of the current location.'),
                    //       ],
                    //     ),
                    //   ),
                    // ),
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