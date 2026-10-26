package com.cleanstreamlaundrysolutions.clean_stream_laundry_app

import android.app.UiModeManager
import android.content.SharedPreferences
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity() {
    private val themePreferences by lazy {
        getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
    }
    private val themeListener = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
        if (key == "flutter.themeData" || key == null) syncNativeTheme()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        syncNativeTheme()
        super.onCreate(savedInstanceState)
        themePreferences.registerOnSharedPreferenceChangeListener(themeListener)
    }

    private fun syncNativeTheme() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        val dark = try {
            themePreferences.getString("flutter.themeData", null) == "darkMode"
        } catch (_: ClassCastException) {
            false
        }
        val mode = if (dark) UiModeManager.MODE_NIGHT_YES else UiModeManager.MODE_NIGHT_NO
        val manager = getSystemService(UiModeManager::class.java)
        // Persist the app's existing choice so Android's next splash matches Flutter.
        manager.setApplicationNightMode(mode)
    }

    override fun onDestroy() {
        themePreferences.unregisterOnSharedPreferenceChangeListener(themeListener)
        super.onDestroy()
    }
}
