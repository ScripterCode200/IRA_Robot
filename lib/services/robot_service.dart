import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:multicast_dns/multicast_dns.dart';

class RobotService {
  static String? _robotIp;
  static WebSocketChannel? _channel;
  static bool _robotOnline = false;
  static bool get isConnected => _channel != null && _robotOnline;
  static RawDatagramSocket? _cmdSocket;
  static RawDatagramSocket? _videoUdpSocket;

  // Custom UDP Reassembly State
  static int _currentFrameId = -1;
  static int _expectedChunks = 0;
  static int _receivedChunks = 0;
  static List<Uint8List?> _frameChunks = [];

  // Streams for broadcasting data
  static final _videoStreamController = StreamController<Uint8List>.broadcast();
  static Stream<Uint8List> get videoStream => _videoStreamController.stream;

  static String _logBuffer = "";
  static bool _isConnecting = false;


  /// Initializes the WebSocket connection
  static Future<void> init() async {
    _connect();
  }

  static void setManualIp(String ip) {
    _robotIp = ip;
  }

  static Future<void> _connect() async {
    if (_isConnecting) return;
    _isConnecting = true;

    try {
      if (_robotIp == null) {
        _logBuffer += "Checking AP Mode default IP (192.168.4.1)...\n";
        try {
          // Fast check: Try connecting to the WebSocket port on the default AP IP
          final socket = await Socket.connect('192.168.4.1', 81, timeout: const Duration(milliseconds: 300));
          socket.destroy();
          _robotIp = '192.168.4.1';
          _logBuffer += "Instant connection to AP Mode IP successful!\n";
        } catch (e) {
          _logBuffer += "AP Mode IP not found, falling back to discovery...\n";
        }
      }

      if (_robotIp == null) {
        _logBuffer += "Searching for robot via UDP...\n";
        try {
          final RawDatagramSocket udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 8888, reuseAddress: true, reusePort: false);
          udpSocket.broadcastEnabled = true;
          
          final completer = Completer<String?>();
          final sub = udpSocket.listen((RawSocketEvent e) {
            if (e == RawSocketEvent.read) {
              final Datagram? dg = udpSocket.receive();
              if (dg != null) {
                final msg = String.fromCharCodes(dg.data);
                if (msg.startsWith("IRA_ROBOT_IP:")) {
                   final ip = msg.substring(13).trim();
                   if (!completer.isCompleted) completer.complete(ip);
                }
              }
            }
          });
          
          _robotIp = await completer.future.timeout(const Duration(seconds: 2), onTimeout: () => null); // Reduced timeout to 2s
          sub.cancel();
          udpSocket.close();
        } catch (e) {
          _logBuffer += "UDP error: $e\n";
        }

        if (_robotIp == null) {
          _logBuffer += "UDP failed. Searching via mDNS...\n";
          try {
            final MDnsClient client = MDnsClient(rawDatagramSocketFactory: (dynamic host, int port, {bool? reuseAddress, bool? reusePort, int? ttl}) {
              return RawDatagramSocket.bind(host, port, reuseAddress: true, reusePort: false, ttl: ttl ?? 1);
            });
            await client.start();
            await for (final IPAddressResourceRecord ptr in client.lookup<IPAddressResourceRecord>(
                ResourceRecordQuery.addressIPv4('ira.local')).timeout(const Duration(seconds: 3), onTimeout: (sink) => sink.close())) {
              _robotIp = ptr.address.address;
              break;
            }
            client.stop();
          } catch (e) {
            _logBuffer += "mDNS error: $e\n";
            print("mDNS error: $e");
          }
        }
        
        if (_robotIp != null) {
          _logBuffer += "Found robot at $_robotIp\n";
        }
      }

      if (_robotIp == null) {
        _logBuffer += "Multicast blocked by Hotspot. Running aggressive TCP subnet scan...\n";
        
        List<String> activeSubnets = [];
        try {
          for (var interface in await NetworkInterface.list()) {
            for (var addr in interface.addresses) {
              if (addr.type == InternetAddressType.IPv4) {
                String ip = addr.address;
                if (!ip.startsWith('127.')) {
                   activeSubnets.add(ip.substring(0, ip.lastIndexOf('.')));
                }
              }
            }
          }
        } catch(e){}
        
        // Add common Android hotspot subnets just in case
        for(var s in ['192.168.43', '192.168.212', '192.168.137', '192.168.140']) { 
          if(!activeSubnets.contains(s)) activeSubnets.add(s); 
        }

        bool found = false;
        for (String subnet in activeSubnets) {
          if (found) break;
          _logBuffer += "Scanning $subnet.x ...\n";
          List<Future<void>> checks = [];
          for (int i = 2; i < 255; i++) {
            String testIp = "$subnet.$i";
            checks.add(Socket.connect(testIp, 81, timeout: const Duration(milliseconds: 500)).then((socket) {
              if (!found) {
                _robotIp = testIp;
                found = true;
              }
              socket.destroy();
            }).catchError((_) {}));
          }
          await Future.wait(checks);
        }

        if (_robotIp == null) {
          print("ROBOT_SERVICE: Scan failed. Defaulting to AP Mode IP (192.168.4.1).");
          _logBuffer += "Scan failed. Defaulting to AP Mode IP (192.168.4.1).\n";
          _robotIp = "192.168.4.1";
        } else {
          print("ROBOT_SERVICE: Subnet scan found robot at $_robotIp");
        }
      }

      final String wsUrl = 'ws://$_robotIp:81';
      print("ROBOT_SERVICE: Attempting WebSocket connection to $wsUrl ...");
      _logBuffer += "Connecting to $wsUrl...\n";

      try {
        if (_cmdSocket == null) {
          _cmdSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
        }
        
        _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
        
        // Wait a bit to see if connection is established without error
        await _channel!.ready.timeout(const Duration(seconds: 10));
        
        _robotOnline = true;
        _logBuffer += "Connected successfully!\n";

        // Setup UDP Video Listener
        if (_videoUdpSocket != null) {
          _videoUdpSocket!.close();
        }
        _videoUdpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 8889);
        _videoUdpSocket!.listen((RawSocketEvent e) {
          if (e == RawSocketEvent.read) {
            Datagram? dg = _videoUdpSocket!.receive();
            if (dg != null && dg.data.length > 4) {
              if (dg.data[0] == 0x56) { // Magic byte 'V'
                int frameId = dg.data[1];
                int chunkIdx = dg.data[2];
                int totalChunks = dg.data[3];

                if (frameId != _currentFrameId) {
                  // New frame arrived, discard old incomplete frame and reset
                  _currentFrameId = frameId;
                  _expectedChunks = totalChunks;
                  _receivedChunks = 0;
                  _frameChunks = List<Uint8List?>.filled(totalChunks, null);
                }

                if (chunkIdx < totalChunks && _frameChunks[chunkIdx] == null) {
                  _frameChunks[chunkIdx] = dg.data.sublist(4);
                  _receivedChunks++;

                  if (_receivedChunks == _expectedChunks) {
                    // All chunks received! Assemble and push to UI
                    int totalLength = _frameChunks.fold(0, (sum, chunk) => sum + (chunk?.length ?? 0));
                    Uint8List completeFrame = Uint8List(totalLength);
                    int offset = 0;
                    for (int i = 0; i < totalChunks; i++) {
                      if (_frameChunks[i] != null) {
                        completeFrame.setAll(offset, _frameChunks[i]!);
                        offset += _frameChunks[i]!.length;
                      }
                    }
                    _videoStreamController.add(completeFrame);
                    // Prevent duplicate processing
                    _currentFrameId = -1;
                  }
                }
              }
            }
          }
        });


        // Setup WebSocket Listener
        _channel!.stream.listen(
          (message) {
            if (message is String) {
              _logBuffer += message + "\n";
              if (_logBuffer.length > 5000) {
                _logBuffer = _logBuffer.substring(_logBuffer.length - 5000);
              }
            }
          },
          onDone: () {
            print("WebSocket closed");
            _logBuffer += "Disconnected.\n";
            _channel = null;
            _robotOnline = false;
            _robotIp = null; // Reset IP to search again next time
            _videoUdpSocket?.close();
            _videoUdpSocket = null;
          },
          onError: (error) {
            print("WebSocket Error: $error");
            _logBuffer += "WebSocket Error: $error\n";
            _channel = null;
            _robotOnline = false;
            _robotIp = null;
            _videoUdpSocket?.close();
            _videoUdpSocket = null;
          },
        );
      } catch (e) {
        print("WebSocket Connection Error: $e");
        _logBuffer += "Connection Error: $e\n";
        _robotOnline = false;
        _robotIp = null;
        _channel = null;
      }
    } finally {
      _isConnecting = false;
    }
  }

  /// Sends physical steering payloads (e.g. "M:0.5,-0.2;G:0,0;H:0;S:0") via TRUE UDP for 0ms latency
  static void sendUdpPayload(String payload) {
    if (_robotIp != null && _cmdSocket != null) {
      final ip = InternetAddress.tryParse(_robotIp!);
      if (ip != null) {
        _cmdSocket!.send(utf8.encode(payload), ip, 8888);
      }
    }
  }

  /// Sends a command like face expression or horn
  static Future<void> sendHttpCommand(String cmd) async {
    if (_channel != null) {
      _channel!.sink.add("cmd:$cmd");
    }
  }
  
  /// Sends raw text over WebSocket
  static Future<void> sendRawText(String text) async {
    if (_channel != null) {
      _channel!.sink.add(text);
    }
  }

  /// Signals the ESP32 to prepare its PSRAM buffer for an incoming audio burst
  static Future<void> sendAudioStart() async {
    if (_channel != null) {
      _channel!.sink.add("audio_start");
    }
  }

  /// Signals the ESP32 that the audio burst is complete and it should begin playback
  static Future<void> sendAudioEnd() async {
    if (_channel != null) {
      _channel!.sink.add("audio_end");
    }
  }

  /// Streams a raw Int16 PCM chunk to the robot's PSRAM buffer
  static Future<void> streamAudioChunk(Uint8List chunk) async {
    if (_channel != null) {
      _channel!.sink.add(chunk); // Send raw without header, ESP32 handles state internally
    }
  }

  /// Sends a raw 128x64 bit-packed pixel array for custom face rendering
  static Future<void> sendCustomFace(Uint8List bitmap) async {
    if (_channel != null && bitmap.length == 1024) {
      _channel!.sink.add(bitmap);
    }
  }

  /// Sends a batch of frames to initialize the ESP32 animation block
  static Future<void> sendAnimationSequence(List<Uint8List> sequence) async {
    if (_channel != null) {
      int tFrames = sequence.length;
      if (tFrames > 30) tFrames = 30; // Max supported by ESP32 RAM
      for (int i = 0; i < tFrames; i++) {
        if (sequence[i].length == 1024) {
          Uint8List packet = Uint8List(1026);
          packet[0] = tFrames;
          packet[1] = i;
          packet.setRange(2, 1026, sequence[i]);
          _channel!.sink.add(packet);
          // 10ms delay to give the ESP32 WiFi and RAM buffer breathing room
          await Future.delayed(const Duration(milliseconds: 10)); 
        }
      }
    }
  }
  /// Fetches real-time log statements from the robot log buffer
  static Future<String> getRobotLogs() async {
    String logs = _logBuffer;
    _logBuffer = "";
    return logs;
  }

  /// Simple connection handshake to check if relay is actively reachable
  static Future<bool> pingRobot() async {
    if (!_robotOnline) {
      await _connect();
    }
    return _robotOnline;
  }
}
