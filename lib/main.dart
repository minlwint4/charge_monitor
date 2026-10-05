import 'dart:async';
import 'dart:convert';
import 'dart:io'; // exit(0) အတွက် ထည့်သွင်းထားသည်
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:battery_plus/battery_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_background/flutter_background.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    home: BatteryMonitorClient(),
    debugShowCheckedModeBanner: false,
  ));
}

class BatteryMonitorClient extends StatefulWidget {
  const BatteryMonitorClient({super.key});
  @override
  State<BatteryMonitorClient> createState() => _BatteryMonitorClientState();
}

class _BatteryMonitorClientState extends State<BatteryMonitorClient> {
  final String serverUrl = "http://10.10.10.10:5000/api/update";
  final Battery _battery = Battery();
  
  String? deviceUid;
  String deviceName = "Android Phone";
  String? assignedId;
  int batteryLevel = 0;
  String currentStatus = "not_charging";
  String syncStatus = "Connecting...";
  
  Timer? _timer;
  StreamSubscription<BatteryState>? _batteryStateSubscription;

  @override
  void initState() {
    super.initState();
    initClient();
  }

  Future<void> initClient() async {
    const androidConfig = FlutterBackgroundAndroidConfig(
      notificationTitle: "Charging Monitor",
      notificationText: "Battery data syncing in background...",
      notificationIcon: AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
    );
    bool hasPermissions = await FlutterBackground.initialize(androidConfig: androidConfig);
    if (hasPermissions) {
      await FlutterBackground.enableBackgroundExecution();
    }

    final prefs = await SharedPreferences.getInstance();
    deviceUid = prefs.getString('uid');
    if (deviceUid == null) {
      deviceUid = const Uuid().v4().substring(0, 8);
      await prefs.setString('uid', deviceUid!);
    }

    try {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      deviceName = "${androidInfo.brand.toUpperCase()} ${androidInfo.model}";
    } catch (_) {}

    await sendUpdate();

    _timer = Timer.periodic(const Duration(seconds: 15), (timer) {
      sendUpdate();
    });

    _batteryStateSubscription = _battery.onBatteryStateChanged.listen((BatteryState state) {
      sendUpdate();
    });
  }

  Future<void> sendUpdate() async {
    try {
      final level = await _battery.batteryLevel;
      final state = await _battery.batteryState;

      String status = "not_charging";
      if (level >= 100 || state == BatteryState.full) {
        status = "full";
      } else if (state == BatteryState.charging) {
        status = "charging";
      }

      setState(() {
        batteryLevel = level;
        currentStatus = status;
      });

      final response = await http.post(
        Uri.parse(serverUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'uid': deviceUid,
          'name': deviceName,
          'battery': level,
          'status': status,
        }),
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        // PC မှ ဖယ်ရှားလိုက်လျှင် App ကို အလိုအလျောက် ပိတ်မည့်စနစ်
        if (data['command'] == 'close_app') {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('uid'); // UID အဟောင်းကို ဖျက်မည်
          exit(0); // App ကို ချက်ချင်း ပိတ်ချမည် (Background အပါအဝင် အကုန်သေသွားမည်)
        }

        setState(() {
          assignedId = data['assigned_id'];
          syncStatus = "Connected (OK)";
        });
      }
    } catch (e) {
      setState(() { syncStatus = "Connection Lost / Retrying..."; });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _batteryStateSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Color statusColor = Colors.redAccent;
    String statusText = "🔌 NOT CHARGING";

    if (currentStatus == "full") {
      statusColor = Colors.greenAccent;
      statusText = "✅ FULL CHARGE";
    } else if (currentStatus == "charging") {
      statusColor = Colors.amberAccent;
      statusText = "⚡ CHARGING";
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  assignedId ?? "WAITING FOR ID...",
                  style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: assignedId != null ? Colors.yellowAccent : Colors.white38),
                ),
                const SizedBox(height: 10),
                Text(deviceName, style: const TextStyle(color: Colors.white70, fontSize: 16)),
                const SizedBox(height: 30),
                Text("$batteryLevel%", style: const TextStyle(fontSize: 72, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(color: statusColor.withOpacity(0.15), borderRadius: BorderRadius.circular(20), border: Border.all(color: statusColor, width: 1.5)),
                  child: Text(statusText, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: statusColor)),
                ),
                const SizedBox(height: 40),
                Text(syncStatus, style: const TextStyle(color: Colors.white30, fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
