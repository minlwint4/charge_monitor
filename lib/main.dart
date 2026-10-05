import 'dart:async';
import 'dart:convert';
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

  bool isMonitoring = true;
  bool isAlerting = false;
  Color flashColor = Colors.redAccent;
  Color flashTextColor = Colors.white;

  @override
  void initState() {
    super.initState();
    checkAndInit();
  }

  Future<void> checkAndInit() async {
    final prefs = await SharedPreferences.getInstance();
    
    // ၁။ UID ကို အမြဲတမ်း တစ်ခုတည်းသာ ထားရှိမည် (ဘယ်တော့မှ မဖျက်ပါ)
    deviceUid = prefs.getString('uid');
    if (deviceUid == null) {
      deviceUid = const Uuid().v4().substring(0, 8);
      await prefs.setString('uid', deviceUid!);
    }

    try {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      deviceName = "${androidInfo.brand.toUpperCase()} ${androidInfo.model}";
    } catch (_) {}

    // အကယ်၍ App ကို ရပ်တန့်ထားခဲ့ပါက နောက်ကွယ်မှ အလိုအလျောက် မ run စေရန် တားဆီးမည်
    isMonitoring = prefs.getBool('is_monitoring') ?? true;
    if (!isMonitoring) {
      setState(() {
        syncStatus = "Service Stopped (Inactive)";
      });
      return;
    }

    await startMonitoringService();
  }

  Future<void> startMonitoringService() async {
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
    await prefs.setBool('is_monitoring', true);

    setState(() {
      isMonitoring = true;
    });

    await sendUpdate();

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 15), (timer) {
      sendUpdate();
    });

    _batteryStateSubscription?.cancel();
    _batteryStateSubscription = _battery.onBatteryStateChanged.listen((BatteryState state) {
      sendUpdate();
    });
  }

  // ၁၀ စက္ကန့် အပြည့် မျက်နှာပြင် မီးတဖျတ်ဖျတ် လင်းလက်ပြသမည့် စနစ်
  Future<void> startFlashingBeacon() async {
    setState(() {
      isAlerting = true;
    });

    for (int i = 0; i < 30; i++) { // ၃၀ ကြိမ် x ၃၃၀ ms = ၁၀ စက္ကန့်
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

      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.heavyImpact();

      await Future.delayed(const Duration(milliseconds: 330));
    }
  }

  // App ကို နောက်ကွယ် Service ရော အကုန်လုံးပါ အပြီးသတ် ပိတ်ပစ်မည့် စနစ်
  Future<void> stopAndExitApp({bool flashFirst = false}) async {
    // Timer များနှင့် Background Listener များကို ချက်ချင်း ရပ်တန့်မည်
    _timer?.cancel();
    _timer = null;
    _batteryStateSubscription?.cancel();
    _batteryStateSubscription = null;

    // အရေးကြီးဆုံး: App ကို ရပ်တန့်ထားသည်ဟု အမှတ်အသား ပြုလုပ်မည် (Auto-restart မဖြစ်စေရန်)
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_monitoring', false);

    // Background Service နှင့် Notification ကို အပြီးသတ် ဖြုတ်ချမည်
    try {
      if (FlutterBackground.isBackgroundExecutionEnabled) {
        await FlutterBackground.disableBackgroundExecution();
      }
    } catch (_) {}

    if (flashFirst) {
      await startFlashingBeacon(); // Pickup ဖြစ်ပါက ၁၀ စက္ကန့် မီးလင်းပြမည်
    }

    await Future.delayed(const Duration(milliseconds: 500));
    
    // Android စနစ်နှင့် အကိုက်ညီဆုံးဖြစ်သော SystemNavigator ဖြင့် ပိတ်သိမ်းမည်
    await SystemNavigator.pop(animated: true);
  }

  Future<void> sendUpdate() async {
    if (isAlerting || !isMonitoring) return;

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
            
            // Excel မှ Pickup လုပ်လိုက်သောအခါ (၁၀ စက္ကန့် လင်းလက်ပြပြီး အပြီးသတ် ပိတ်မည်)
            if (data['command'] == 'alarm_and_close') {
              await stopAndExitApp(flashFirst: true);
              return;
            }
            
            // PC Monitor မှ ✕ (Delete) နှိပ်သောအခါ
            if (data['command'] == 'close_app') {
              await stopAndExitApp(flashFirst: false);
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
    // Pickup လုပ်ချိန်တွင် ပြသမည့် Visual Alert Screen (၁၀ စက္ကန့် မီးရောင်)
    if (isAlerting) {
      return Scaffold(
        backgroundColor: flashColor,
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.notifications_active, size: 110, color: flashTextColor),
                const SizedBox(height: 20),
                Text(
                  assignedId ?? "PICKUP",
                  style: TextStyle(
                    fontSize: 84,
                    fontWeight: FontWeight.w900,
                    color: flashTextColor,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 15),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                  decoration: BoxDecoration(
                    color: flashTextColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Text(
                    "⚡ PICKUP READY (10s) ⚡",
                    style: TextStyle(
                      fontSize: 22,
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
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: assignedId != null ? Colors.yellowAccent : Colors.white38,
                  ),
                ),
                const SizedBox(height: 8),
                Text(deviceName, style: const TextStyle(color: Colors.white70, fontSize: 16)),
                const SizedBox(height: 24),
                Text("$batteryLevel%", style: const TextStyle(fontSize: 72, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor, width: 1.5),
                  ),
                  child: Text(statusText, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: statusColor)),
                ),
                const SizedBox(height: 30),
                Text(syncStatus, style: const TextStyle(color: Colors.white30, fontSize: 12)),
                const SizedBox(height: 40),

                // App အား နောက်ကွယ် Service ရော အကုန်လုံးပါ လုံးဝ ပိတ်ချမည့် EXIT ခလုတ်
                ElevatedButton.icon(
                  onPressed: () => stopAndExitApp(flashFirst: false),
                  icon: const Icon(Icons.power_settings_new, color: Colors.white, size: 22),
                  label: const Text(
                    "EXIT APP (လုံးဝပိတ်မည်)",
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade800,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
