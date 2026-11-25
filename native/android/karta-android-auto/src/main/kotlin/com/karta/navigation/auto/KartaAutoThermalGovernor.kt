package com.karta.navigation.auto

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager

/**
 * Monitors Android SoC thermal status (`PowerManager.OnThermalStatusChangedListener`, API 29+)
 * and battery temperature/charging telemetry during extended Android Auto navigation sessions.
 *
 * Streams thermal pressure reports to Dart's `ThermalAdaptationController` and applies
 * an immediate local FPS / 3D shedding fail-safe if `THERMAL_STATUS_CRITICAL` is hit.
 */
class KartaAutoThermalGovernor(
    private val context: Context,
) {
    private val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
    private var isStarted = false
    private var lastThermalStatus: Int = 0
    private var lastBatteryPct: Int? = null
    private var lastIsCharging: Boolean = false
    private var lastBatteryTempC: Double? = null

    private val thermalListener: PowerManager.OnThermalStatusChangedListener? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            PowerManager.OnThermalStatusChangedListener { status ->
                lastThermalStatus = status
                emitCurrentSnapshot()
            }
        } else {
            null
        }

    private val batteryReceiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context?, intent: Intent?) {
            if (intent == null) return
            val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
            val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, 100)
            if (level >= 0 && scale > 0) {
                lastBatteryPct = ((level * 100f) / scale).toInt()
            }
            val status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
            lastIsCharging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                status == BatteryManager.BATTERY_STATUS_FULL

            val tenthsC = intent.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, Int.MIN_VALUE)
            if (tenthsC != Int.MIN_VALUE) {
                lastBatteryTempC = tenthsC / 10.0
            }
            emitCurrentSnapshot()
        }
    }

    fun start() {
        if (isStarted) return
        isStarted = true

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            lastThermalStatus = powerManager.currentThermalStatus
            thermalListener?.let { powerManager.addThermalStatusListener(it) }
        }

        val sticky = context.registerReceiver(
            batteryReceiver,
            IntentFilter(Intent.ACTION_BATTERY_CHANGED),
        )
        if (sticky != null) {
            batteryReceiver.onReceive(context, sticky)
        } else {
            emitCurrentSnapshot()
        }
    }

    fun stop() {
        if (!isStarted) return
        isStarted = false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            thermalListener?.let { powerManager.removeThermalStatusListener(it) }
        }
        try {
            context.unregisterReceiver(batteryReceiver)
        } catch (_: Exception) {
        }
    }

    private fun emitCurrentSnapshot() {
        val wireLevel = mapAndroidThermalStatus(lastThermalStatus)
        if (wireLevel == "critical") {
            // Immediate fail-safe local cap even before Dart responds.
            KartaAutoStateStore.updateThermalProfile(KartaAutoThermalProfile.CRITICAL_FAILSAFE)
        }
        KartaAutoStateStore.emitThermalState(
            thermalLevel = wireLevel,
            batteryLevelPercent = lastBatteryPct,
            isCharging = lastIsCharging,
            batteryTempCelsius = lastBatteryTempC,
            isLowPowerMode = powerManager.isPowerSaveMode,
        )
    }

    private fun mapAndroidThermalStatus(status: Int): String = when {
        status <= 1 -> "nominal" // NONE, LIGHT
        status == 2 -> "fair"    // MODERATE
        status == 3 -> "serious" // SEVERE
        else -> "critical"       // CRITICAL, EMERGENCY, SHUTDOWN
    }
}
