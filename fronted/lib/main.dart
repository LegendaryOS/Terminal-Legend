import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/io.dart';
import 'package:window_manager/window_manager.dart';
import 'package:particles_flutter/particles_flutter.dart';  // For particles

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  WindowOptions windowOptions = const WindowOptions(
    size: Size(800, 600),
    center: true,
    backgroundColor: Colors.transparent,  // Semi-transparent setup
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
    await windowManager.setOpacity(0.9);  // Semi-transparent (90% opacity)
  });
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Terminal Legend',
      theme: ThemeData.dark(),
      home: const TerminalScreen(),
    );
  }
}

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});

  @override
  _TerminalScreenState createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<String> _output = [];
  IOWebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Process? _backendProcess;

  @override
  void initState() {
    super.initState();
    _startBackendAndConnect();
  }

  Future<void> _startBackendAndConnect() async {
    // Spawn backend binary (adjust path if needed)
    _backendProcess = await Process.start('tl-backend', []);  // Assuming in PATH; or use full path like '/path/to/tl-backend'

    // Connect to WebSocket
    await Future.delayed(const Duration(seconds: 1));  // Wait for backend to start
    _channel = IOWebSocketChannel.connect('ws://127.0.0.1:8080');
    _subscription = _channel!.stream.listen((message) {
      setState(() {
        _output.add(message);
      });
      _scrollToBottom();
    });
  }

  void _sendCommand() {
    final command = _controller.text.trim();
    if (command.isNotEmpty) {
      setState(() {
        _output.add('> $command');
      });
      _channel?.sink.add('{"command": "$command"}');
      _controller.clear();
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),  // Custom animation: smooth scroll
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _channel?.sink.close();
    _subscription?.cancel();
    _backendProcess?.kill();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Particle background
          CircularParticle(
            key: UniqueKey(),
            awayRadius: 80,
            numberOfParticles: 100,
            speedOfParticles: 1,
            height: MediaQuery.of(context).size.height,
            width: MediaQuery.of(context).size.width,
            onTapAnimation: true,
            particleColor: Colors.white.withAlpha(150),
            awayAnimationDuration: const Duration(milliseconds: 600),
            maxParticleSize: 8,
            isRandSize: true,
            isRandomColor: true,
            randColorList: [
              Colors.red.withAlpha(210),
              Colors.blue.withAlpha(210),
              Colors.green.withAlpha(210),
              Colors.yellow.withAlpha(210),
            ],
            awayAnimationCurve: Curves.easeInOutBack,
            enableHover: true,
            hoverColor: Colors.white,
            hoverRadius: 90,
            connectDots: false,  // Connect particles like a web
          ),
          // Terminal content (semi-transparent overlay)
          Container(
            color: Colors.black.withOpacity(0.5),  // Semi-transparent black background
            child: Column(
              children: [
                Expanded(
                  child: AnimatedList(  // Custom animation: fade-in for new output
                  controller: _scrollController,
                  initialItemCount: _output.length,
                  itemBuilder: (context, index, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(_output[index], style: const TextStyle(color: Colors.green)),
                      ),
                    );
                  },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      const Text('> ', style: TextStyle(color: Colors.green, fontSize: 18)),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            hintText: 'Enter command...',
                            hintStyle: TextStyle(color: Colors.grey),
                          ),
                          onSubmitted: (_) => _sendCommand(),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.send, color: Colors.green),
                        onPressed: _sendCommand,
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
