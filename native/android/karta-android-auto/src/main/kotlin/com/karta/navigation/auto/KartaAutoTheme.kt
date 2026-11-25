package com.karta.navigation.auto

import android.graphics.Rect
import kotlin.math.max

/** Vehicle head-unit aspect-ratio classification for panoramic & ultra-wide dashboards. */
enum class KartaAutoViewportClass {
    STANDARD,   // < 1.65 (e.g. 800x480, 1024x600)
    WIDE,       // 1.65 ..< 2.05 (e.g. 1280x720, 1920x1080)
    ULTRA_WIDE, // >= 2.05 (e.g. 1920x720, 2400x720 panoramic dashes)
}

/**
 * Computed layout metrics maximizing map canvas lookahead and legibility across
 * standard, wide, and ultra-wide Android Auto head units.
 */
data class KartaAutoViewportMetrics(
    val widthPx: Int,
    val heightPx: Int,
    val densityScale: Float,
) {
    val aspectRatio: Float
        get() = if (heightPx > 0) widthPx.toFloat() / heightPx.toFloat() else 1.66f

    val viewportClass: KartaAutoViewportClass
        get() = when {
            aspectRatio >= 2.05f -> KartaAutoViewportClass.ULTRA_WIDE
            aspectRatio >= 1.65f -> KartaAutoViewportClass.WIDE
            else -> KartaAutoViewportClass.STANDARD
        }

    /**
     * Lower-third camera padding shifts the vehicle puck toward the bottom ~34% of the
     * unobstructed `stableArea` so drivers gain maximum forward expressway lookahead.
     * Returns `[left, top, right, bottom]` in pixels for `CameraUpdateFactory.paddingTo`.
     */
    fun navigationPadding(
        stableOrVisible: Rect,
        isLeftHandTraffic: Boolean,
    ): DoubleArray {
        val safeLeft = max(0, stableOrVisible.left)
        val safeTop = max(0, stableOrVisible.top)
        val safeRight = max(0, widthPx - stableOrVisible.right)
        val safeBottom = max(0, heightPx - stableOrVisible.bottom)

        val usableHeight = max(120, stableOrVisible.height())
        val forwardBiasRatio = if (viewportClass == KartaAutoViewportClass.ULTRA_WIDE) 0.24f else 0.28f
        val forwardBiasTop = (usableHeight * forwardBiasRatio).toInt()
        val extraLateral = (if (viewportClass == KartaAutoViewportClass.ULTRA_WIDE) 28f else 12f) *
            max(1f, densityScale)
        val extraBottom = 14f * max(1f, densityScale)

        val leftPad = safeLeft + if (isLeftHandTraffic) 12.0 * max(1f, densityScale) else extraLateral.toDouble()
        val rightPad = safeRight + if (isLeftHandTraffic) extraLateral.toDouble() else 12.0 * max(1f, densityScale)

        return doubleArrayOf(
            leftPad,
            safeTop + forwardBiasTop.toDouble(),
            rightPad,
            safeBottom + extraBottom.toDouble(),
        )
    }

    val routeLineWidth: Float
        get() = when (viewportClass) {
            KartaAutoViewportClass.ULTRA_WIDE -> 10.0f
            KartaAutoViewportClass.WIDE -> 8.5f
            KartaAutoViewportClass.STANDARD -> 7.4f
        }

    val routeCasingWidth: Float
        get() = routeLineWidth + 5.2f

    val speedBadgeScale: Float
        get() = when (viewportClass) {
            KartaAutoViewportClass.ULTRA_WIDE -> 1.12f
            KartaAutoViewportClass.WIDE -> 1.04f
            KartaAutoViewportClass.STANDARD -> 0.96f
        }
}

/**
 * Dual-lighting automotive design token palette mirroring Karta's `KartaPalette`
 * (`ObsidianNight` for headlights-on / tunnel driving; `TropicalDaylight` for
 * high-glare midday equatorial sun across MY / SG / BN).
 */
data class KartaAutoTheme(
    val isDarkMode: Boolean,
    val backgroundPrimary: Int,
    val surfaceCard: Int,
    val surfaceElevated: Int,
    val borderSubtle: Int,
    val accentPrimary: Int,
    val accentBright: Int,
    val textPrimary: Int,
    val textSecondary: Int,
    val arrowInk: Int,
    val statusClear: Int,
    val statusCaution: Int,
    val statusAlert: Int,
    val statusInfo: Int,
    val rotaryFocusRing: Int,
    val routeCoreHex: String,
    val routeCasingHex: String,
    val puckCoreHex: String,
    val puckHaloHex: String,
    val puckStrokeHex: String,
    val hazardFillHex: String,
    val hazardStrokeHex: String,
) {
    companion object {
        /** Obsidian Night Mode — low-glare cockpit palette (#0D0F12 / #181C22 / #5B9A94). */
        val ObsidianNight = KartaAutoTheme(
            isDarkMode = true,
            backgroundPrimary = 0xFF0D0F12.toInt(),
            surfaceCard = 0xFF181C22.toInt(),
            surfaceElevated = 0xFF20262F.toInt(),
            borderSubtle = 0xFF2B3340.toInt(),
            accentPrimary = 0xFF5B9A94.toInt(),
            accentBright = 0xFF74C4BC.toInt(),
            textPrimary = 0xFFF4F6F8.toInt(),
            textSecondary = 0xFF8E96A0.toInt(),
            arrowInk = 0xFFFFFFFF.toInt(),
            statusClear = 0xFF42B883.toInt(),
            statusCaution = 0xFFF5A623.toInt(),
            statusAlert = 0xFFFF5A52.toInt(),
            statusInfo = 0xFF5A9DF0.toInt(),
            rotaryFocusRing = 0xFF74C4BC.toInt(),
            routeCoreHex = "#62B3AB",
            routeCasingHex = "#090B0E",
            puckCoreHex = "#74C4BC",
            puckHaloHex = "#5B9A94",
            puckStrokeHex = "#F4F6F8",
            hazardFillHex = "#FF5A52",
            hazardStrokeHex = "#F4F6F8",
        )

        /** High-Glare Tropical Daylight Mode — warm limestone canvas (#F5F2EB) & WCAG AAA ink (#11161C). */
        val TropicalDaylight = KartaAutoTheme(
            isDarkMode = false,
            backgroundPrimary = 0xFFF5F2EB.toInt(),
            surfaceCard = 0xFFFCFBF8.toInt(),
            surfaceElevated = 0xFFEFECE4.toInt(),
            borderSubtle = 0xFFD5D0C5.toInt(),
            accentPrimary = 0xFF2F756F.toInt(),
            accentBright = 0xFF1E5C57.toInt(),
            textPrimary = 0xFF11161C.toInt(),
            textSecondary = 0xFF4A5563.toInt(),
            arrowInk = 0xFF11161C.toInt(),
            statusClear = 0xFF137D4E.toInt(),
            statusCaution = 0xFFB86B00.toInt(),
            statusAlert = 0xFFC82822.toInt(),
            statusInfo = 0xFF1C5DB0.toInt(),
            rotaryFocusRing = 0xFF1E5C57.toInt(),
            routeCoreHex = "#246E68",
            routeCasingHex = "#102F2C",
            puckCoreHex = "#1E5C57",
            puckHaloHex = "#2F756F",
            puckStrokeHex = "#FCFBF8",
            hazardFillHex = "#C82822",
            hazardStrokeHex = "#FCFBF8",
        )

        fun resolve(isDarkMode: Boolean): KartaAutoTheme =
            if (isDarkMode) ObsidianNight else TropicalDaylight
    }
}
