package com.example.karta_app

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Karta Navigation Android Activity binding real hardware GPS + fused network
 * location streams (`com.karta.navigation/location` and `location_stream`)
 * with runtime permission handling so smartphones lock onto live GPS cleanly.
 */
class MainActivity : FlutterActivity() {
    companion object {
        private const val LOCATION_METHOD_CHANNEL = "com.karta.navigation/location"
        private const val LOCATION_EVENT_CHANNEL = "com.karta.navigation/location_stream"
        private const val REQ_LOCATION_PERMISSION = 4201
    }

    private var locationManager: LocationManager? = null
    private var locationEventSink: EventChannel.EventSink? = null
    private var activeListener: LocationListener? = null
    private var pendingPositionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        locationManager = getSystemService(Context.LOCATION_SERVICE) as? LocationManager

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LOCATION_METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getCurrentPosition" -> handleGetCurrentPosition(result)
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, LOCATION_EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    locationEventSink = events
                    if (hasLocationPermission()) {
                        startLocationUpdates()
                    } else {
                        requestLocationPermission()
                    }
                }

                override fun onCancel(arguments: Any?) {
                    stopLocationUpdates()
                    locationEventSink = null
                }
            })
    }

    private fun hasLocationPermission(): Boolean {
        val fine = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        val coarse = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_COARSE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        return fine || coarse
    }

    private fun requestLocationPermission() {
        ActivityCompat.requestPermissions(
            this,
            arrayOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION
            ),
            REQ_LOCATION_PERMISSION
        )
    }

    private fun handleGetCurrentPosition(result: MethodChannel.Result) {
        if (!hasLocationPermission()) {
            pendingPositionResult = result
            requestLocationPermission()
            return
        }
        val best = getBestLastKnownLocation()
        if (best != null) {
            result.success(locationToMap(best))
        } else {
            result.success(null)
        }
    }

    private fun getBestLastKnownLocation(): Location? {
        val lm = locationManager ?: return null
        var best: Location? = null
        val providers = listOf(
            LocationManager.GPS_PROVIDER,
            LocationManager.NETWORK_PROVIDER,
            LocationManager.PASSIVE_PROVIDER
        )
        for (provider in providers) {
            try {
                if (!lm.isProviderEnabled(provider)) continue
                val loc = lm.getLastKnownLocation(provider) ?: continue
                if (best == null || loc.accuracy < best.accuracy || loc.time > best.time + 30_000L) {
                    best = loc
                }
            } catch (_: SecurityException) {
                // Ignore provider if permission revoked mid-call
            } catch (_: Exception) {
                // Provider not available on device
            }
        }
        return best
    }

    private fun startLocationUpdates() {
        val lm = locationManager ?: return
        stopLocationUpdates()

        // Emit immediate last-known fix if present so map centers quickly
        getBestLastKnownLocation()?.let { last ->
            locationEventSink?.success(locationToMap(last))
        }

        val listener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                locationEventSink?.success(locationToMap(location))
            }

            @Deprecated("Deprecated in Android API 29")
            override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
            override fun onProviderEnabled(provider: String) {}
            override fun onProviderDisabled(provider: String) {}
        }
        activeListener = listener

        val providers = listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)
        var attached = false
        for (provider in providers) {
            try {
                if (lm.isProviderEnabled(provider)) {
                    lm.requestLocationUpdates(
                        provider,
                        1500L,
                        2.0f,
                        listener,
                        Looper.getMainLooper()
                    )
                    attached = true
                }
            } catch (_: SecurityException) {
            } catch (_: Exception) {
            }
        }
        if (!attached) {
            locationEventSink?.error("unavailable", "Enable device GPS / Location services.", null)
        }
    }

    private fun stopLocationUpdates() {
        val lm = locationManager ?: return
        val listener = activeListener ?: return
        try {
            lm.removeUpdates(listener)
        } catch (_: Exception) {
        }
        activeListener = null
    }

    private fun locationToMap(loc: Location): Map<String, Any> {
        return mapOf(
            "lat" to loc.latitude,
            "lon" to loc.longitude,
            "bearing" to (if (loc.hasBearing()) loc.bearing.toDouble() else 0.0),
            "speed_kmh" to (if (loc.hasSpeed()) (loc.speed * 3.6).toDouble() else 0.0),
            "accuracy_m" to (if (loc.hasAccuracy()) loc.accuracy.toDouble() else 12.0)
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_LOCATION_PERMISSION) {
            val granted = grantResults.any { it == PackageManager.PERMISSION_GRANTED }
            val pending = pendingPositionResult
            pendingPositionResult = null
            if (granted) {
                val loc = getBestLastKnownLocation()
                pending?.success(loc?.let { locationToMap(it) })
                if (locationEventSink != null) {
                    startLocationUpdates()
                }
            } else {
                pending?.success(null)
                locationEventSink?.error("denied", "Location permission denied by user.", null)
            }
        }
    }

    override fun onDestroy() {
        stopLocationUpdates()
        super.onDestroy()
    }
}
