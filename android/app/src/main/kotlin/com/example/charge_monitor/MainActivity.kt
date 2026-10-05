package com.example.charge_monitor

import android.app.NotificationManager
import android.content.Context
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
                try {
                    // ၁။ Notification အားလုံးကို ချက်ချင်း ဖျက်ချမည်
                    val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    notificationManager.cancelAll()
                } catch (e: Exception) {}

                // ၂။ Tab ကို လက်ဖြင့် ဆွဲပိတ်လိုက်သကဲ့သို့ Task တစ်ခုလုံးကို ရှင်းထုတ်မည်
                finishAndRemoveTask()

                // ၃။ Process တစ်ခုလုံးကို အပြီးသတ် သတ်ပစ်မည်
                Process.killProcess(Process.myPid())
                System.exit(0)
            } else {
                result.notImplemented()
            }
        }
    }
}
