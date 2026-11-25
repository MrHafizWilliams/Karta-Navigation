package com.karta.navigation.auto

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.view.View
import kotlin.math.roundToInt

/**
 * High-contrast, non-interactive MY / SG / BN Speed-Limit & Live Speedometer HUD
 * mounted inside Android Auto's map `Presentation` and anchored inside the
 * unobstructed `stableArea` bottom-right corner.
 *
 * Automatically mirrors Obsidian Night and Tropical Daylight vehicle headlight
 * dimmer states and scales proportionally across standard, wide, and ultra-wide
 * panoramic head units.
 */
class KartaAutoSpeedBadgeView(context: Context) : View(context) {

    private var theme: KartaAutoTheme = KartaAutoTheme.ObsidianNight
    private var currentSpeedKmh: Int = 0
    private var speedLimitText: String = "--"
    private var countryCaption: String = "km/h · MY RM"
    private var alertLevel: String = "normal"
    private var badgeScale: Float = 1.0f

    private val density: Float = maxOf(1.0f, context.resources.displayMetrics.density)
    private val cardRect = RectF()

    private val cardFillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
    }
    private val cardBorderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
    }
    private val signDiscPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        style = Paint.Style.FILL
    }
    private val signRingPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
    }
    private val signTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0xFF11161C.toInt()
        textAlign = Paint.Align.CENTER
        typeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
        isFakeBoldText = true
    }
    private val speedTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        textAlign = Paint.Align.LEFT
        typeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
        isFakeBoldText = true
    }
    private val captionTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        textAlign = Paint.Align.LEFT
        typeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
    }

    init {
        isClickable = false
        isFocusable = false
        visibility = GONE
    }

    fun applyTheme(next: KartaAutoTheme) {
        theme = next
        invalidate()
    }

    fun updateFrame(frame: KartaAutoFrame, scale: Float) {
        val shouldShow = frame.isNavigating || frame.speedLimitKmh != null
        visibility = if (shouldShow) VISIBLE else GONE
        if (!shouldShow) return

        val scaleChanged = kotlin.math.abs(scale - badgeScale) > 0.01f
        badgeScale = scale
        currentSpeedKmh = frame.currentSpeedKmh.roundToInt().coerceAtLeast(0)
        speedLimitText = frame.speedLimitKmh?.toString() ?: "--"
        countryCaption = "km/h · ${frame.countryCode} ${frame.currencySymbol}"
        alertLevel = frame.speedAlertLevel.lowercase()

        if (scaleChanged) {
            requestLayout()
        }
        invalidate()
    }

    private fun dp(value: Float): Float = value * density * badgeScale

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val w = dp(176f).roundToInt()
        val h = dp(68f).roundToInt()
        setMeasuredDimension(w, h)
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val w = width.toFloat()
        val h = height.toFloat()
        if (w <= 0f || h <= 0f) return

        val stroke = dp(1.8f)
        cardRect.set(stroke, stroke, w - stroke, h - stroke)
        val cornerRadius = dp(16f)

        val (fillColor, borderColor, speedColor) = when (alertLevel) {
            "alert" -> Triple(
                withAlpha(theme.statusAlert, if (theme.isDarkMode) 220 else 235),
                theme.statusAlert,
                Color.WHITE,
            )
            "caution" -> Triple(
                withAlpha(theme.surfaceCard, 242),
                theme.statusCaution,
                theme.statusCaution,
            )
            else -> Triple(
                withAlpha(theme.surfaceCard, 238),
                theme.borderSubtle,
                theme.textPrimary,
            )
        }

        cardFillPaint.color = fillColor
        cardBorderPaint.color = borderColor
        cardBorderPaint.strokeWidth = stroke
        canvas.drawRoundRect(cardRect, cornerRadius, cornerRadius, cardFillPaint)
        canvas.drawRoundRect(cardRect, cornerRadius, cornerRadius, cardBorderPaint)

        // Authentic MY / SG / BN circular white speed-limit sign with bold red ring
        val signRadius = dp(23f)
        val signCx = dp(12f) + signRadius
        val signCy = h * 0.5f
        signRingPaint.color = theme.statusAlert
        signRingPaint.strokeWidth = dp(4.2f)
        canvas.drawCircle(signCx, signCy, signRadius, signDiscPaint)
        canvas.drawCircle(signCx, signCy, signRadius - dp(1.6f), signRingPaint)

        signTextPaint.textSize = if (speedLimitText.length >= 3) dp(15.5f) else dp(17.5f)
        val signTextY = signCy - (signTextPaint.descent() + signTextPaint.ascent()) * 0.5f
        canvas.drawText(speedLimitText, signCx, signTextY, signTextPaint)

        // Live tabular km/h speed + country/currency caption
        val textStartX = signCx + signRadius + dp(11f)
        speedTextPaint.color = speedColor
        speedTextPaint.textSize = dp(27f)
        val speedBaseline = h * 0.54f
        canvas.drawText(currentSpeedKmh.toString(), textStartX, speedBaseline, speedTextPaint)

        captionTextPaint.color = if (alertLevel == "alert") {
            Color.WHITE
        } else {
            theme.textSecondary
        }
        captionTextPaint.textSize = dp(10.5f)
        val captionBaseline = h * 0.80f
        canvas.drawText(countryCaption, textStartX, captionBaseline, captionTextPaint)
    }

    private fun withAlpha(argb: Int, alpha: Int): Int {
        return (argb and 0x00FFFFFF) or ((alpha.coerceIn(0, 255)) shl 24)
    }
}
