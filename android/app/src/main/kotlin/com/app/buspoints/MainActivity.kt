package com.app.buspoints

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
	private val CHANNEL = "com.app.buspoints/streetview"

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
			when (call.method) {
				"openStreetView" -> {
					val lat = call.argument<Double>("lat") ?: 0.0
					val lng = call.argument<Double>("lng") ?: 0.0
					val intent = Intent(this, StreetViewActivity::class.java)
					intent.putExtra("lat", lat)
					intent.putExtra("lng", lng)
					startActivity(intent)
					result.success(null)
				}
				else -> result.notImplemented()
			}
		}
	}
}
