import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final List<String> serverUrls = [
    "http://10.10.10.10:5000/api/update",
    "http://192.168.1.50:5000/api/update"
  ];
  
  int workingUrlIndex = 0; 
  final Battery _battery = Battery();
  
  String? deviceUid;
  String deviceName = "Android Phone";
  String? assignedId;
  int batteryLevel = 0;
  String currentStatus = "not_charging";
  String syncStatus = "Connecting...";
  
  Timer? _timer;
  StreamSubscription<BatteryState>? _batteryStateSubscription;

  // Visual Alert (မျက်နှာပြင် မီးတဖျတ်ဖျတ်လင်းမည့် စနစ်) အတွက် State များ
  bool isAlerting = false;
  Color flashColor = Colors.redAccent;
  Color flashTextColor = Colors.white;

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

  // မျက်နှာပြင်ပေါ်တွင် အနီရောင်နှင့် အဝါရောင် တဖျတ်ဖျတ် လင်းလက်စေမည့် စနစ် (၅ စက္ကန့်ကြာမည်)
  Future<void> startFlashingBeacon() async {
    setState(() {
      isAlerting = true;
    });

    // အကြိမ် ၂၀ ခန့် တဖျတ်ဖျတ် လင်းလက်ပြေးမည် (စုစုပေါင်း ၅ စက္ကန့်ခန့်)
    for (int i = 0; i < 18; i++) {
      if (!mounted) break;
      setState(() {
        if (i % 2 == 0) {
          flashColor = Colors.redAccent;
          flashTextColor = Colors.white;
        } else {
          flashColor = Colors.amberAccent;
          flashTextColor = Colors.black;
        }
      });

      // System Sound နှင့် Vibration ကိုပါ တွဲဖက် အချက်ပေးမည်
      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.heavyImpact();

      await Future.delayed(const Duration(milliseconds: 300));
    }
  }

  // App နှင့် Background Service ကို အပြီးသတ် ပိတ်ပစ်မည့် စနစ်
  Future<void> shutdownApp() async {
    _timer?.cancel();
    _batteryStateSubscription?.cancel();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('uid');

    try {
      if (FlutterBackground.isBackgroundExecutionEnabled) {
        await FlutterBackground.disableBackgroundExecution();
      }
    } catch (_) {}

    await Future.delayed(const Duration(milliseconds: 400));
    await SystemNavigator.pop();
    exit(0);
  }

  Future<void> sendUpdate() async {
    // Alert ပြနေစဉ်အတွင်း update မပို့တော့ပါ
    if (isAlerting) return;

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

      bool isConnected = false;

      for (int i = 0; i < serverUrls.length; i++) {
        int tryIndex = (workingUrlIndex + i) % serverUrls.length;
        String tryUrl = serverUrls[tryIndex];

        try {
          final response = await http.post(
            Uri.parse(tryUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'uid': deviceUid,
              'name': deviceName,
              'battery': level,
              'status': status,
            }),
          ).timeout(const Duration(seconds: 3)); 

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            
            // Excel မှ Pickup လုပ်လိုက်သောအခါ
            if (data['command'] == 'alarm_and_close') {
              await startFlashingBeacon(); // မျက်နှာပြင် တဖျတ်ဖျတ် လင်းပြမည်
              await shutdownApp();         // ပြီးလျှင် App ကို အပြီး ပိတ်မည်
              return;
            }
            
            // PC Monitor မှ ✕ (Delete) နှိပ်သောအခါ
            if (data['command'] == 'close_app') {
              await shutdownApp();
              return;
            }

            setState(() {
              assignedId = data['assigned_id'];
              syncStatus = "Connected (${tryUrl.split('/')[2]})"; 
            });
            
            workingUrlIndex = tryIndex; 
            isConnected = true;
            break; 
          }
        } catch (e) {
          continue; 
        }
      }

      if (!isConnected) {
        setState(() { syncStatus = "Connection Lost / Retrying..."; });
      }
      
    } catch (e) {
      setState(() { syncStatus = "Error updating data"; });
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
    // Pickup လုပ်ချိန်တွင် ပြသမည့် Visual Alert Screen (အရေးပေါ် မီးရောင်ပုံစံ)
    if (isAlerting) {
      return Scaffold(
        backgroundColor: flashColor,
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.notifications_active, size: 100, color: flashTextColor),
                const SizedBox(height: 20),
                Text(
                  assignedId ?? "PICKUP",
                  style: TextStyle(
                    fontSize: 80,
                    fontWeight: FontWeight.w900,
                    color: flashTextColor,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 15),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  decoration: BoxDecoration(
                    color: flashTextColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Text(
                    "⚡ PICKUP READY ⚡",
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: flashTextColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // ပုံမှန် အချိန်တွင် ပြသမည့် Monitor Screen
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
