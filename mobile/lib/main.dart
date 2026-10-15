import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';

void main() {
  runApp(const ProxyProofApp());
}

class ProxyProofApp extends StatelessWidget {
  const ProxyProofApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ProxyProof',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const RoleSelectionScreen(),
    );
  }
}

// ----------------------------------------------------------------------
// 1. ROLE SELECTION SCREEN
// ----------------------------------------------------------------------
class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("ProxyProof - Select Role")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              child: const Text("I am an Organiser (Broadcaster)"),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OrganiserScreen())),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              child: const Text("I am a Student (Scanner)"),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StudentScreen())),
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// 2. ORGANISER SCREEN (Broadcasts Rotating Token)
// ----------------------------------------------------------------------
class OrganiserScreen extends StatefulWidget {
  const OrganiserScreen({Key? key}) : super(key: key);
  @override
  _OrganiserScreenState createState() => _OrganiserScreenState();
}

class _OrganiserScreenState extends State<OrganiserScreen> {
  final FlutterBlePeripheral blePeripheral = FlutterBlePeripheral();
  Timer? _timer;
  
  // Replace with local machine or server IPv4 address
  final String backendStartUrl = "http://10.107.215.158:8000/api/sessions/start";
  
  String sessionId = "";
  String secretKey = "";
  String currentToken = "";
  bool isBroadcasting = false;

  Future<void> startSession() async {
    try {
      var response = await http.post(
        Uri.parse(backendStartUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"duration_minutes": 5}),
      );
      
      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        sessionId = data['session_id'];
        secretKey = data['secret_key'];
        
        setState(() => isBroadcasting = true);
        _startTokenRotation();
      }
    } catch (e) {
      debugPrint("Network Error: Could not reach backend: $e");
    }
  }

  void _startTokenRotation() {
    _rotateAndBroadcast();
    _timer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _rotateAndBroadcast();
    });
  }

  void _rotateAndBroadcast() async {
    int timeWindow = (DateTime.now().millisecondsSinceEpoch / 1000 / 10).floor();
    var key = utf8.encode(secretKey);
    var bytes = utf8.encode(timeWindow.toString());
    var hmacSha256 = Hmac(sha256, key);
    String token = hmacSha256.convert(bytes).toString().substring(0, 6);
    
    setState(() => currentToken = token);

    AdvertiseData advertiseData = AdvertiseData(
      serviceUuid: 'bf27730d-860a-4e09-889c-2d8b6a9e0fe7',
      manufacturerId: 1234,
      manufacturerData: Uint8List.fromList(utf8.encode("$sessionId:$token")),
    );

    await blePeripheral.stop();
    await blePeripheral.start(advertiseData: advertiseData);
  }

  @override
  void dispose() {
    _timer?.cancel();
    blePeripheral.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Organiser Dashboard")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!isBroadcasting)
              ElevatedButton(onPressed: startSession, child: const Text("Start 5-Minute Session"))
            else ...[
              const Text("Session Active! Broadcasting BLE...", style: TextStyle(color: Colors.green, fontSize: 16)),
              const SizedBox(height: 10),
              Text("Session ID: $sessionId"),
              Text("Rotating Token: $currentToken", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
            ]
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// 3. STUDENT SCREEN (Scans for Token & Checks RSSI)
// ----------------------------------------------------------------------
class StudentScreen extends StatefulWidget {
  const StudentScreen({Key? key}) : super(key: key);
  @override
  _StudentScreenState createState() => _StudentScreenState();
}

class _StudentScreenState extends State<StudentScreen> {
  String status = "Waiting to scan...";
  final String studentId = "STU123"; 
  
  // Replace with local machine or server IPv4 address
  final String backendUrl = "http://10.107.215.158:8000/api/attendance/mark"; 

  Future<void> scanAndMark() async {
    setState(() => status = "Scanning for classroom...");

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));

    FlutterBluePlus.scanResults.listen((results) async {
      for (ScanResult r in results) {
        if (r.advertisementData.manufacturerData.containsKey(1234)) {
          await FlutterBluePlus.stopScan();
          setState(() => status = "Signal found, verifying with server...");

          List<int> rawData = r.advertisementData.manufacturerData[1234]!;
          String payload = utf8.decode(rawData);
          List<String> parts = payload.split(':');
          
          if (parts.length == 2) {
            await markAttendance(parts[0], parts[1], r.rssi);
          }
        }
      }
    });
  }

  Future<void> markAttendance(String sessionId, String token, int rssi) async {
    String deviceId = "unknown";
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    
    if (Platform.isAndroid) {
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      deviceId = androidInfo.id;
    } else if (Platform.isIOS) {
      IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
      deviceId = iosInfo.identifierForVendor ?? "unknown";
    }

    try {
      var response = await http.post(
        Uri.parse(backendUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "student_id": studentId,
          "session_id": sessionId,
          "token": token,
          "device_id": deviceId,
          "rssi": rssi,
        }),
      );

      if (response.statusCode == 200) {
        setState(() => status = "Present ✅\nAttendance logged successfully!");
      } else {
        setState(() => status = "Verification Failed:\n${jsonDecode(response.body)['detail']}");
      }
    } catch (e) {
      setState(() => status = "Network Error: Could not reach backend.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Student Check-In")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(onPressed: scanAndMark, child: const Text("Scan & Mark Attendance")),
            const SizedBox(height: 20),
            Text("Status: $status", textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );
  }
}
