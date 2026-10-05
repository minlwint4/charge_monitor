package com.example.charge_monitor

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.os.Process
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.charge_monitor/app_control"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "killAppLikeSwipe") {
                result.success(true)

                try {
                    // ၁။ flutter_background ၏ Foreground Service ကို Android OS အဆင့်မှ တိုက်ရိုက် ရပ်တန့်မည်
                    val serviceIntent = Intent(this, Class.forName("de.julianassmann.flutter_background.IsolateHolderService"))
                    stopService(serviceIntent)
                } catch (_: Exception) {}

                try {
                    // ၂။ Notification အားလုံးကို ချက်ချင်း ဖျက်ချမည်
                    val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    notificationManager.cancelAll()
                } catch (_: Exception) {}

                // ၃။ Recent Apps (Tab) ကို လက်ဖြင့် ဆွဲပိတ်လိုက်သကဲ့သို့ Task တစ်ခုလုံးကို ရှင်းလင်းမည်
                finishAndRemoveTask()

                // ၄။ Task ရှင်းလင်းပြီးသည်နှင့် Process ကို လုံးဝ အပြီးသတ် သတ်ပစ်မည်
                Handler(Looper.getMainLooper()).postDelayed({
                    Process.killProcess(Process.myPid())
                    System.exit(0)
                }, 200)
            } else {
                result.notImplemented()
            }
        }
    }
}
