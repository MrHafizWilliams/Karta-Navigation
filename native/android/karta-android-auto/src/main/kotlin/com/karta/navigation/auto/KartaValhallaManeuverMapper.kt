package com.karta.navigation.auto

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.DashPathEffect
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import androidx.car.app.model.CarIcon
import androidx.car.app.model.Distance
import androidx.car.app.navigation.model.Lane
import androidx.car.app.navigation.model.LaneDirection
import androidx.car.app.navigation.model.Maneuver
import androidx.core.graphics.drawable.IconCompat
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.round
import kotlin.math.sin

/** Vector symbol kinds rendered inside double-contrast rotary-controller focus rings. */
enum class KartaRotaryActionKind {
    VOICE_MIC,
    AUDIO_ON,
    AUDIO_MUTED,
    ROUTE_OVERVIEW,
    END_TRIP,
    RECENTER,
    REPORT_HAZARD,
}

/**
 * Flagship high-contrast automotive renderer translating Valhalla maneuver types (1..37),
 * compound OSM turn-lanes (`through;right`), MY/SG/BN toll payment chips, and rotary-safe
 * action controls into Android for Cars App Library [Maneuver], [Lane], [Distance], and
 * WCAG AAA dual-lighting [CarIcon] bitmaps.
 */
object KartaValhallaManeuverMapper {

    fun toCarManeuver(
        valhallaType: Int,
        isLeftHandTraffic: Boolean,
        theme: KartaAutoTheme = KartaAutoTheme.ObsidianNight,
        isSecondary: Boolean = false,
    ): Maneuver {
        val type = when (valhallaType) {
            1, 2, 3 -> Maneuver.TYPE_DEPART
            4 -> Maneuver.TYPE_DESTINATION
            5 -> Maneuver.TYPE_DESTINATION_RIGHT
            6 -> Maneuver.TYPE_DESTINATION_LEFT
            9 -> Maneuver.TYPE_TURN_SLIGHT_RIGHT
            10 -> Maneuver.TYPE_TURN_NORMAL_RIGHT
            11 -> Maneuver.TYPE_TURN_SHARP_RIGHT
            12 -> Maneuver.TYPE_U_TURN_RIGHT
            13 -> Maneuver.TYPE_U_TURN_LEFT
            14 -> Maneuver.TYPE_TURN_SHARP_LEFT
            15 -> Maneuver.TYPE_TURN_NORMAL_LEFT
            16 -> Maneuver.TYPE_TURN_SLIGHT_LEFT
            17 -> Maneuver.TYPE_STRAIGHT
            18 -> Maneuver.TYPE_ON_RAMP_NORMAL_RIGHT
            19 -> Maneuver.TYPE_ON_RAMP_NORMAL_LEFT
            20 -> Maneuver.TYPE_OFF_RAMP_NORMAL_RIGHT
            21 -> Maneuver.TYPE_OFF_RAMP_NORMAL_LEFT
            22 -> Maneuver.TYPE_STRAIGHT
            23 -> Maneuver.TYPE_KEEP_RIGHT
            24 -> Maneuver.TYPE_KEEP_LEFT
            25 -> Maneuver.TYPE_MERGE_RIGHT
            26 -> Maneuver.TYPE_MERGE_LEFT
            27 -> if (isLeftHandTraffic) {
                Maneuver.TYPE_ROUNDABOUT_ENTER_CW
            } else {
                Maneuver.TYPE_ROUNDABOUT_ENTER_CCW
            }
            28 -> if (isLeftHandTraffic) {
                Maneuver.TYPE_ROUNDABOUT_EXIT_CW
            } else {
                Maneuver.TYPE_ROUNDABOUT_EXIT_CCW
            }
            29 -> Maneuver.TYPE_FERRY_BOAT
            else -> Maneuver.TYPE_STRAIGHT
        }
        return Maneuver.Builder(type)
            .setIcon(
                renderManeuverIcon(
                    valhallaType = valhallaType,
                    isLeftHandTraffic = isLeftHandTraffic,
                    theme = theme,
                    isSecondary = isSecondary,
                ),
            )
            .build()
    }

    fun toCarDistance(meters: Double): Distance {
        val safe = max(0.0, meters)
        return when {
            safe >= 100_000.0 -> Distance.create(round(safe / 1000.0), Distance.UNIT_KILOMETERS)
            safe >= 1_000.0 -> Distance.create(safe / 1000.0, Distance.UNIT_KILOMETERS_P1)
            else -> Distance.create(round(safe / 10.0) * 10.0, Distance.UNIT_METERS)
        }
    }

    fun toCarLane(item: KartaAutoLane): Lane {
        val tokens = item.laneSpec
            .lowercase()
            .split(';')
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .ifEmpty { listOf("through") }

        val builder = Lane.Builder()
        for (token in tokens) {
            val shape = when {
                token.contains("sharp_left") -> LaneDirection.SHAPE_SHARP_LEFT
                token.contains("slight_left") -> LaneDirection.SHAPE_SLIGHT_LEFT
                token.contains("left") -> LaneDirection.SHAPE_NORMAL_LEFT
                token.contains("sharp_right") -> LaneDirection.SHAPE_SHARP_RIGHT
                token.contains("slight_right") -> LaneDirection.SHAPE_SLIGHT_RIGHT
                token.contains("right") -> LaneDirection.SHAPE_NORMAL_RIGHT
                token.contains("reverse") -> LaneDirection.SHAPE_U_TURN_LEFT
                else -> LaneDirection.SHAPE_STRAIGHT
            }
            builder.addDirection(LaneDirection.create(shape, item.isRecommended))
        }
        return builder.build()
    }

    /**
     * Renders a crisp 360x64 dual-lighting compound lane-guidance & MY/SG/BN toll strip
     * for `Step.Builder.setLanesImage`, drawing ALL semicolon-separated lane directions,
     * filled arrowheads, dashed vertical lane dividers, and toll payment chips.
     */
    fun renderLanesImage(
        lanes: List<KartaAutoLane>,
        theme: KartaAutoTheme = KartaAutoTheme.ObsidianNight,
        approachingTollPayments: List<String> = emptyList(),
        approachingTollName: String? = null,
    ): CarIcon? {
        if (lanes.isEmpty() && approachingTollPayments.isEmpty()) return null

        val width = 360
        val height = 64
        val bmp = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)

        // Container background & high-contrast accent border
        val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = theme.surfaceElevated
            style = Paint.Style.FILL
        }
        val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = if (!approachingTollName.isNullOrBlank()) theme.statusCaution else theme.borderSubtle
            strokeWidth = 2.0f
            style = Paint.Style.STROKE
        }
        val cardRect = RectF(1.5f, 1.5f, width - 1.5f, height - 1.5f)
        canvas.drawRoundRect(cardRect, 12f, 12f, bgPaint)
        canvas.drawRoundRect(cardRect, 12f, 12f, borderPaint)

        val displayLanes = lanes.take(5)
        val badges = approachingTollPayments.take(3)
        val badgeAreaW = if (badges.isEmpty()) 0f else badges.size * 54f + 10f
        val laneAreaW = max(130f, width - 20f - badgeAreaW)
        val slotW = if (displayLanes.isEmpty()) 0f else min(54f, laneAreaW / displayLanes.size)

        val activeFill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = theme.accentPrimary
            alpha = if (theme.isDarkMode) 88 else 48
            style = Paint.Style.FILL
        }
        val activeBorder = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = theme.accentBright
            strokeWidth = 2.0f
            style = Paint.Style.STROKE
        }
        val dividerPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = theme.borderSubtle
            strokeWidth = 1.5f
            style = Paint.Style.STROKE
            pathEffect = DashPathEffect(floatArrayOf(5f, 5f), 0f)
        }

        var xCursor = 10f
        displayLanes.forEachIndexed { idx, lane ->
            val boxRect = RectF(xCursor, 7f, xCursor + slotW - 5f, height - 7f)
            if (lane.isRecommended) {
                canvas.drawRoundRect(boxRect, 9f, 9f, activeFill)
                canvas.drawRoundRect(boxRect, 9f, 9f, activeBorder)
            }

            val arrowColor = if (lane.isRecommended) {
                theme.arrowInk
            } else {
                withAlpha(theme.textSecondary, 86)
            }
            val innerRect = RectF(
                boxRect.left + 6f,
                boxRect.top + 6f,
                boxRect.right - 6f,
                boxRect.bottom - 6f,
            )
            drawCompoundLaneTokens(
                canvas = canvas,
                laneSpec = lane.laneSpec,
                rect = innerRect,
                color = arrowColor,
                strokeWidth = if (lane.isRecommended) 3.8f else 2.6f,
            )

            if (idx < displayLanes.size - 1) {
                val divX = xCursor + slotW - 2.5f
                canvas.drawLine(divX, 11f, divX, height - 11f, dividerPaint)
            }
            xCursor += slotW
        }

        if (badges.isNotEmpty()) {
            xCursor = max(xCursor + 6f, 12f)
            val chipTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = theme.textPrimary
                textAlign = Paint.Align.CENTER
                textSize = 11.5f
                typeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
                isFakeBoldText = true
            }
            for (wire in badges) {
                val chipRect = RectF(xCursor, 17f, xCursor + 50f, height - 17f)
                if (chipRect.right > width - 8f) break
                val accent = paymentAccentColor(wire, theme)
                val chipFill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = accent
                    alpha = if (theme.isDarkMode) 74 else 48
                    style = Paint.Style.FILL
                }
                val chipStroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = accent
                    strokeWidth = 1.6f
                    style = Paint.Style.STROKE
                }
                canvas.drawRoundRect(chipRect, 7f, 7f, chipFill)
                canvas.drawRoundRect(chipRect, 7f, 7f, chipStroke)
                val label = shortPaymentBadge(wire)
                val textY = chipRect.centerY() - (chipTextPaint.descent() + chipTextPaint.ascent()) * 0.5f
                canvas.drawText(label, chipRect.centerX(), textY, chipTextPaint)
                xCursor += 54f
            }
        }

        return CarIcon.Builder(IconCompat.createWithBitmap(bmp)).build()
    }

    /**
     * Renders a WCAG AAA heavy-stroke (14.5%) vector maneuver arrow distinguishing
     * slight (45°), normal (90°), sharp (135°), U-turn, ramp/merge, destination, and
     * clockwise MY/SG/BN left-hand-traffic roundabouts across Night & Daylight themes.
     */
    fun renderManeuverIcon(
        valhallaType: Int,
        isLeftHandTraffic: Boolean = true,
        theme: KartaAutoTheme = KartaAutoTheme.ObsidianNight,
        sizePx: Int = 112,
        isSecondary: Boolean = false,
    ): CarIcon {
        val bmp = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        val w = sizePx.toFloat()
        val h = sizePx.toFloat()
        val primaryInk = if (isSecondary) theme.textSecondary else theme.arrowInk
        val strokeW = w * if (isSecondary) 0.11f else 0.145f

        val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = primaryInk
            strokeWidth = strokeW
            style = Paint.Style.STROKE
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
        }
        val ghostPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = withAlpha(theme.textSecondary, 98)
            strokeWidth = strokeW * 0.72f
            style = Paint.Style.STROKE
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
        }
        val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = primaryInk
            style = Paint.Style.FILL
        }

        when (valhallaType) {
            // Destination (4, 5, 6)
            4, 5, 6 -> {
                strokePaint.color = theme.accentBright
                fillPaint.color = theme.accentBright
                canvas.drawCircle(w * 0.5f, h * 0.38f, w * 0.22f, strokePaint)
                canvas.drawCircle(w * 0.5f, h * 0.38f, w * 0.10f, fillPaint)
                canvas.drawLine(w * 0.5f, h * 0.62f, w * 0.5f, h * 0.88f, strokePaint)
            }

            // Slight right (9), Ramp/Exit/Keep/Merge right (18, 20, 23, 25) -> 45° right
            9, 18, 20, 23, 25 -> {
                if (valhallaType == 23 || valhallaType == 25) {
                    canvas.drawLine(w * 0.34f, h * 0.86f, w * 0.34f, h * 0.20f, ghostPaint)
                }
                val p = Path().apply {
                    moveTo(w * 0.34f, h * 0.86f)
                    lineTo(w * 0.34f, h * 0.52f)
                    lineTo(w * 0.68f, h * 0.22f)
                }
                canvas.drawPath(p, strokePaint)
                drawArrowHead(canvas, w * 0.77f, h * 0.14f, (-PI / 4.0).toFloat(), w * 0.27f, fillPaint)
            }

            // Normal right turn (10) -> 90° right with smooth shoulder
            10 -> {
                val p = Path().apply {
                    moveTo(w * 0.28f, h * 0.86f)
                    lineTo(w * 0.28f, h * 0.42f)
                    quadTo(w * 0.28f, h * 0.30f, w * 0.44f, h * 0.30f)
                    lineTo(w * 0.70f, h * 0.30f)
                }
                canvas.drawPath(p, strokePaint)
                drawArrowHead(canvas, w * 0.85f, h * 0.30f, 0f, w * 0.27f, fillPaint)
            }

            // Sharp right turn (11) -> 135° hairpin right
            11 -> {
                val p = Path().apply {
                    moveTo(w * 0.26f, h * 0.86f)
                    lineTo(w * 0.26f, h * 0.28f)
                    lineTo(w * 0.68f, h * 0.62f)
                }
                canvas.drawPath(p, strokePaint)
                drawArrowHead(canvas, w * 0.78f, h * 0.70f, (PI / 4.0).toFloat(), w * 0.27f, fillPaint)
            }

            // U-turn right (12) / U-turn left (13)
            12, 13 -> {
                val isLeft = (valhallaType == 13)
                val xStart = if (isLeft) w * 0.70f else w * 0.30f
                val xEnd = if (isLeft) w * 0.28f else w * 0.72f
                val cx = (xStart + xEnd) * 0.5f
                val radius = kotlin.math.abs(xEnd - xStart) * 0.5f
                val arcRect = RectF(cx - radius, h * 0.36f - radius, cx + radius, h * 0.36f + radius)
                val p = Path().apply {
                    moveTo(xStart, h * 0.86f)
                    lineTo(xStart, h * 0.36f)
                    arcTo(arcRect, if (isLeft) 0f else 180f, if (isLeft) -180f else 180f, false)
                    lineTo(xEnd, h * 0.62f)
                }
                canvas.drawPath(p, strokePaint)
                drawArrowHead(canvas, xEnd, h * 0.77f, (PI / 2.0).toFloat(), w * 0.27f, fillPaint)
            }

            // Sharp left turn (14) -> 135° hairpin left
            14 -> {
                val p = Path().apply {
                    moveTo(w * 0.74f, h * 0.86f)
                    lineTo(w * 0.74f, h * 0.28f)
                    lineTo(w * 0.32f, h * 0.62f)
                }
                canvas.drawPath(p, strokePaint)
                drawArrowHead(canvas, w * 0.22f, h * 0.70f, (3.0 * PI / 4.0).toFloat(), w * 0.27f, fillPaint)
            }

            // Normal left turn (15) -> 90° left with smooth shoulder
            15 -> {
                val p = Path().apply {
                    moveTo(w * 0.72f, h * 0.86f)
                    lineTo(w * 0.72f, h * 0.42f)
                    quadTo(w * 0.72f, h * 0.30f, w * 0.56f, h * 0.30f)
                    lineTo(w * 0.30f, h * 0.30f)
                }
                canvas.drawPath(p, strokePaint)
                drawArrowHead(canvas, w * 0.15f, h * 0.30f, PI.toFloat(), w * 0.27f, fillPaint)
            }

            // Slight left (16), Ramp/Exit/Keep/Merge left (19, 21, 24, 26) -> 45° left
            16, 19, 21, 24, 26 -> {
                if (valhallaType == 24 || valhallaType == 26) {
                    canvas.drawLine(w * 0.66f, h * 0.86f, w * 0.66f, h * 0.20f, ghostPaint)
                }
                val p = Path().apply {
                    moveTo(w * 0.66f, h * 0.86f)
                    lineTo(w * 0.66f, h * 0.52f)
                    lineTo(w * 0.32f, h * 0.22f)
                }
                canvas.drawPath(p, strokePaint)
                drawArrowHead(canvas, w * 0.23f, h * 0.14f, (-3.0 * PI / 4.0).toFloat(), w * 0.27f, fillPaint)
            }

            // Roundabout (27, 28) — clockwise LHT path for MY / SG / BN
            27, 28 -> {
                val cx = w * 0.5f
                val cy = h * 0.48f
                val r = w * 0.20f
                canvas.drawCircle(cx, cy, r, ghostPaint)

                val arcRect = RectF(cx - r, cy - r, cx + r, cy + r)
                val p = Path().apply {
                    moveTo(cx, h * 0.88f)
                    lineTo(cx, cy + r)
                    // Canvas angles: 90° is bottom; clockwise sweeps +180° via left (180°) to top (270°)
                    arcTo(arcRect, 90f, if (isLeftHandTraffic) 180f else -180f, false)
                    lineTo(cx, h * 0.16f)
                }
                canvas.drawPath(p, strokePaint)
                drawArrowHead(canvas, cx, h * 0.08f, (-PI / 2.0).toFloat(), w * 0.27f, fillPaint)
            }

            // Straight / Continue / Depart
            else -> {
                canvas.drawLine(w * 0.5f, h * 0.86f, w * 0.5f, h * 0.24f, strokePaint)
                drawArrowHead(canvas, w * 0.5f, h * 0.12f, (-PI / 2.0).toFloat(), w * 0.27f, fillPaint)
            }
        }

        return CarIcon.Builder(IconCompat.createWithBitmap(bmp)).build()
    }

    /**
     * Renders a crisp vector icon inside a double-contrast rotary-controller focus ring
     * for Android Auto's streamlined 3-action strip and conditional map controls.
     */
    fun renderRotaryActionIcon(
        kind: KartaRotaryActionKind,
        theme: KartaAutoTheme,
        highlighted: Boolean = false,
        destructive: Boolean = false,
        sizePx: Int = 96,
    ): CarIcon {
        val bmp = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        val w = sizePx.toFloat()
        val h = sizePx.toFloat()
        val cx = w * 0.5f
        val cy = h * 0.5f
        val radius = w * 0.43f

        val ringColor = when {
            destructive -> theme.statusAlert
            highlighted -> theme.rotaryFocusRing
            else -> theme.borderSubtle
        }
        val glyphColor = when {
            destructive -> theme.statusAlert
            highlighted -> theme.rotaryFocusRing
            else -> theme.textPrimary
        }

        // Inner high-contrast backing disk so icons remain crisp under rotary highlight halos
        val bgFill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = when {
                destructive -> withAlpha(theme.statusAlert, if (theme.isDarkMode) 68 else 42)
                highlighted -> withAlpha(theme.rotaryFocusRing, if (theme.isDarkMode) 68 else 42)
                else -> withAlpha(theme.surfaceElevated, 210)
            }
            style = Paint.Style.FILL
        }
        val ringStroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = ringColor
            strokeWidth = w * if (highlighted || destructive) 0.065f else 0.045f
            style = Paint.Style.STROKE
        }
        canvas.drawCircle(cx, cy, radius, bgFill)
        canvas.drawCircle(cx, cy, radius, ringStroke)

        val glyphStroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = glyphColor
            strokeWidth = w * 0.068f
            style = Paint.Style.STROKE
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
        }
        val glyphFill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = glyphColor
            style = Paint.Style.FILL
        }

        when (kind) {
            KartaRotaryActionKind.VOICE_MIC -> {
                val capsule = RectF(w * 0.41f, h * 0.24f, w * 0.59f, h * 0.54f)
                canvas.drawRoundRect(capsule, w * 0.09f, w * 0.09f, glyphFill)
                val arcRect = RectF(w * 0.31f, h * 0.34f, w * 0.69f, h * 0.65f)
                canvas.drawArc(arcRect, 0f, 180f, false, glyphStroke)
                canvas.drawLine(cx, h * 0.65f, cx, h * 0.77f, glyphStroke)
                canvas.drawLine(w * 0.39f, h * 0.77f, w * 0.61f, h * 0.77f, glyphStroke)
            }
            KartaRotaryActionKind.AUDIO_ON, KartaRotaryActionKind.AUDIO_MUTED -> {
                val speaker = Path().apply {
                    moveTo(w * 0.27f, h * 0.42f)
                    lineTo(w * 0.40f, h * 0.42f)
                    lineTo(w * 0.55f, h * 0.29f)
                    lineTo(w * 0.55f, h * 0.71f)
                    lineTo(w * 0.40f, h * 0.58f)
                    lineTo(w * 0.27f, h * 0.58f)
                    close()
                }
                canvas.drawPath(speaker, glyphFill)
                if (kind == KartaRotaryActionKind.AUDIO_ON) {
                    val wave1 = RectF(w * 0.53f, h * 0.38f, w * 0.68f, h * 0.62f)
                    val wave2 = RectF(w * 0.56f, h * 0.28f, w * 0.77f, h * 0.72f)
                    canvas.drawArc(wave1, -55f, 110f, false, glyphStroke)
                    canvas.drawArc(wave2, -55f, 110f, false, glyphStroke)
                } else {
                    canvas.drawLine(w * 0.63f, h * 0.41f, w * 0.77f, h * 0.59f, glyphStroke)
                    canvas.drawLine(w * 0.77f, h * 0.41f, w * 0.63f, h * 0.59f, glyphStroke)
                }
            }
            KartaRotaryActionKind.ROUTE_OVERVIEW -> {
                // Stylized folded map / corridor overview polyline + endpoints
                val routePath = Path().apply {
                    moveTo(w * 0.30f, h * 0.70f)
                    cubicTo(w * 0.30f, h * 0.44f, w * 0.70f, h * 0.56f, w * 0.70f, h * 0.30f)
                }
                canvas.drawPath(routePath, glyphStroke)
                canvas.drawCircle(w * 0.30f, h * 0.70f, w * 0.065f, glyphFill)
                canvas.drawCircle(w * 0.70f, h * 0.30f, w * 0.065f, glyphFill)
            }
            KartaRotaryActionKind.END_TRIP -> {
                canvas.drawLine(w * 0.33f, h * 0.33f, w * 0.67f, h * 0.67f, glyphStroke)
                canvas.drawLine(w * 0.67f, h * 0.33f, w * 0.33f, h * 0.67f, glyphStroke)
            }
            KartaRotaryActionKind.RECENTER -> {
                canvas.drawCircle(cx, cy, w * 0.16f, glyphStroke)
                canvas.drawCircle(cx, cy, w * 0.055f, glyphFill)
                canvas.drawLine(cx, h * 0.22f, cx, h * 0.31f, glyphStroke)
                canvas.drawLine(cx, h * 0.69f, cx, h * 0.78f, glyphStroke)
                canvas.drawLine(w * 0.22f, cy, w * 0.31f, cy, glyphStroke)
                canvas.drawLine(w * 0.69f, cy, w * 0.78f, cy, glyphStroke)
            }
            KartaRotaryActionKind.REPORT_HAZARD -> {
                val tri = Path().apply {
                    moveTo(cx, h * 0.25f)
                    lineTo(w * 0.75f, h * 0.72f)
                    lineTo(w * 0.25f, h * 0.72f)
                    close()
                }
                canvas.drawPath(tri, glyphStroke)
                canvas.drawLine(cx, h * 0.42f, cx, h * 0.56f, glyphStroke)
                canvas.drawCircle(cx, h * 0.65f, w * 0.036f, glyphFill)
            }
        }

        return CarIcon.Builder(IconCompat.createWithBitmap(bmp)).build()
    }

    /** Renders a high-contrast circular badge [CarIcon] for the 6-sector Quick Hazard Grid. */
    fun renderBadgeIcon(
        label: String,
        accentArgb: Int,
        theme: KartaAutoTheme = KartaAutoTheme.ObsidianNight,
        sizePx: Int = 96,
    ): CarIcon {
        val bmp = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        val r = sizePx * 0.44f
        val cx = sizePx * 0.5f
        val cy = sizePx * 0.5f

        val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = accentArgb
            alpha = if (theme.isDarkMode) 68 else 42
            style = Paint.Style.FILL
        }
        val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = accentArgb
            strokeWidth = sizePx * 0.06f
            style = Paint.Style.STROKE
        }
        val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = theme.textPrimary
            textAlign = Paint.Align.CENTER
            textSize = sizePx * 0.30f
            isFakeBoldText = true
        }
        canvas.drawCircle(cx, cy, r, fill)
        canvas.drawCircle(cx, cy, r, ring)
        val yOffset = cy - (text.descent() + text.ascent()) * 0.5f
        canvas.drawText(label, cx, yOffset, text)
        return CarIcon.Builder(IconCompat.createWithBitmap(bmp)).build()
    }

    private fun drawArrowHead(
        canvas: Canvas,
        tipX: Float,
        tipY: Float,
        angleRad: Float,
        len: Float,
        paint: Paint,
    ) {
        val spread = 0.54f
        val p1x = tipX - len * cos((angleRad - spread).toDouble()).toFloat()
        val p1y = tipY - len * sin((angleRad - spread).toDouble()).toFloat()
        val p2x = tipX - len * cos((angleRad + spread).toDouble()).toFloat()
        val p2y = tipY - len * sin((angleRad + spread).toDouble()).toFloat()
        val head = Path().apply {
            moveTo(tipX, tipY)
            lineTo(p1x, p1y)
            lineTo(p2x, p2y)
            close()
        }
        canvas.drawPath(head, paint)
    }

    private fun drawCompoundLaneTokens(
        canvas: Canvas,
        laneSpec: String,
        rect: RectF,
        color: Int,
        strokeWidth: Float,
    ) {
        val tokens = laneSpec
            .lowercase()
            .split(';')
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .ifEmpty { listOf("through") }

        val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color
            this.strokeWidth = strokeWidth
            style = Paint.Style.STROKE
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
        }
        val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color
            style = Paint.Style.FILL
        }

        val midX = rect.centerX()
        val bottomY = rect.bottom
        val stemY = rect.centerY() + 2f

        for (raw in tokens) {
            when {
                raw.contains("left") -> {
                    val slight = raw.contains("slight")
                    val tipX = if (slight) rect.left + 3f else rect.left + 1f
                    val tipY = if (slight) rect.top + 3f else stemY - 5f
                    val p = Path().apply {
                        moveTo(midX, bottomY)
                        lineTo(midX, stemY)
                        lineTo(tipX, tipY)
                    }
                    canvas.drawPath(p, strokePaint)
                    drawArrowHead(
                        canvas,
                        tipX,
                        tipY,
                        if (slight) (-3.0 * PI / 4.0).toFloat() else PI.toFloat(),
                        7.5f,
                        fillPaint,
                    )
                }
                raw.contains("right") -> {
                    val slight = raw.contains("slight")
                    val tipX = if (slight) rect.right - 3f else rect.right - 1f
                    val tipY = if (slight) rect.top + 3f else stemY - 5f
                    val p = Path().apply {
                        moveTo(midX, bottomY)
                        lineTo(midX, stemY)
                        lineTo(tipX, tipY)
                    }
                    canvas.drawPath(p, strokePaint)
                    drawArrowHead(
                        canvas,
                        tipX,
                        tipY,
                        if (slight) (-PI / 4.0).toFloat() else 0f,
                        7.5f,
                        fillPaint,
                    )
                }
                else -> {
                    val tipY = rect.top + 2f
                    canvas.drawLine(midX, bottomY, midX, tipY, strokePaint)
                    drawArrowHead(canvas, midX, tipY, (-PI / 2.0).toFloat(), 7.5f, fillPaint)
                }
            }
        }
    }

    private fun shortPaymentBadge(wire: String): String = when (wire.uppercase()) {
        "RFID" -> "RFID"
        "SMARTTAG" -> "SmTAG"
        "TNG_CARD" -> "TnG"
        "OPEN_PAYMENT_CARD" -> "CARD"
        "ERP2_OBU", "ERP_IU" -> "ERP"
        "BRUNEI_TOLL_CARD" -> "BN"
        else -> wire.take(5)
    }

    private fun paymentAccentColor(wire: String, theme: KartaAutoTheme): Int = when (wire.uppercase()) {
        "RFID" -> theme.accentPrimary
        "SMARTTAG", "TNG_CARD" -> theme.statusInfo
        "ERP2_OBU", "ERP_IU" -> theme.statusCaution
        "BRUNEI_TOLL_CARD" -> 0xFFD4AF37.toInt()
        else -> theme.accentBright
    }

    private fun withAlpha(argb: Int, alpha: Int): Int {
        return (argb and 0x00FFFFFF) or ((alpha.coerceIn(0, 255)) shl 24)
    }
}
