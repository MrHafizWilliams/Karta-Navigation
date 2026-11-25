package com.karta.navigation.auto

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.car.app.CarContext
import androidx.car.app.CarToast
import androidx.car.app.media.CarAudioRecord
import androidx.core.content.ContextCompat

/**
 * Hands-free voice reporting controller for Android Auto.
 *
 * - Requests transient navigation audio focus (`USAGE_ASSISTANCE_NAVIGATION_GUIDANCE`,
 *   `AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK`) to cleanly duck cabin media.
 * - Uses `CarAudioRecord` (Car App API >= 5) readiness probe + on-device `SpeechRecognizer`
 *   to capture EN / BM / Manglish / Singlish hazard phrases and forward them across
 *   [KartaAutoStateStore] into Dart's sub-15ms `RegionalVoiceIntentParser`.
 */
class KartaAutoVoiceController(
    private val carContext: CarContext,
) {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val audioManager = carContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var speechRecognizer: SpeechRecognizer? = null
    private var activeFocusRequest: AudioFocusRequest? = null
    private var isListening = false

    fun triggerHandsFreeVoiceReport(countryCode: String) {
        val localeTag = when (countryCode.uppercase()) {
            "SG" -> "en-SG"
            "BN" -> "ms-BN"
            else -> "en-MY"
        }

        if (isListening) {
            stop()
            return
        }

        // Notify Dart immediately so companion HUD / voice engine reflects listening state.
        KartaAutoStateStore.emitVoiceReportTriggered(localeTag)

        val hasAudioPerm = ContextCompat.checkSelfPermission(
            carContext,
            Manifest.permission.RECORD_AUDIO,
        ) == PackageManager.PERMISSION_GRANTED
        if (!hasAudioPerm) {
            CarToast.makeText(
                carContext,
                "Enable Microphone permission on phone for hands-free voice reports",
                CarToast.LENGTH_SHORT,
            ).show()
            return
        }

        requestNavigationAudioDucking()

        // Verify Car Head-Unit microphone support on Car App API >= 5
        if (carContext.carAppApiLevel >= 5) {
            try {
                val carAudio = CarAudioRecord.create(carContext)
                carAudio.startRecording()
                carAudio.stopRecording()
            } catch (_: SecurityException) {
                // Fall back gracefully to phone/Bluetooth HFP SpeechRecognizer
            } catch (_: Exception) {
            }
        }

        mainHandler.post {
            startSpeechRecognition(localeTag)
        }
    }

    private fun startSpeechRecognition(localeTag: String) {
        if (!SpeechRecognizer.isRecognitionAvailable(carContext)) {
            abandonAudioFocus()
            return
        }

        val recognizer = speechRecognizer ?: SpeechRecognizer.createSpeechRecognizer(carContext).also {
            speechRecognizer = it
        }

        recognizer.setRecognitionListener(
            object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) {
                    isListening = true
                    CarToast.makeText(
                        carContext,
                        "Listening — say Police, Accident, Pothole, Banjir...",
                        CarToast.LENGTH_SHORT,
                    ).show()
                }

                override fun onBeginningOfSpeech() {}
                override fun onRmsChanged(rmsdB: Float) {}
                override fun onBufferReceived(buffer: ByteArray?) {}
                override fun onEndOfSpeech() {
                    isListening = false
                }

                override fun onError(error: Int) {
                    isListening = false
                    abandonAudioFocus()
                }

                override fun onResults(results: Bundle?) {
                    isListening = false
                    abandonAudioFocus()
                    val best = results
                        ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                        ?.firstOrNull()
                        ?.trim()
                    if (!best.isNullOrEmpty()) {
                        KartaAutoStateStore.emitVoiceTranscript(best, localeTag)
                        CarToast.makeText(
                            carContext,
                            "Reported: $best",
                            CarToast.LENGTH_SHORT,
                        ).show()
                    }
                }

                override fun onPartialResults(partialResults: Bundle?) {}
                override fun onEvent(eventType: Int, params: Bundle?) {}
            },
        )

        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, localeTag)
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true) // Privacy-first on-device ASR
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        }
        recognizer.startListening(intent)
    }

    private fun requestNavigationAudioDucking() {
        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .build()
        val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
            .setAudioAttributes(attrs)
            .setWillPauseWhenDucked(false)
            .build()
        activeFocusRequest = req
        audioManager.requestAudioFocus(req)
    }

    private fun abandonAudioFocus() {
        activeFocusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
        activeFocusRequest = null
    }

    fun stop() {
        isListening = false
        mainHandler.post {
            speechRecognizer?.cancel()
            speechRecognizer?.destroy()
            speechRecognizer = null
        }
        abandonAudioFocus()
    }
}
