package com.bting.audio.focus

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/** Owned by the shared audio_service FlutterEngine, never by an Activity. */
class BlistenAudioFocusPlugin : FlutterPlugin {
    private lateinit var context: Context
    private lateinit var manager: AudioManager
    private lateinit var methods: MethodChannel
    private lateinit var events: EventChannel
    private var sink: EventChannel.EventSink? = null
    private var request: AudioFocusRequest? = null
    private var listener: AudioManager.OnAudioFocusChangeListener? = null
    private var requestId: Long? = null
    private var receiverRegistered = false

    private val noisyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) emit("noisy")
        }
    }

    private fun emit(event: String, id: Long? = requestId) {
        if (id != null && id == requestId) {
            sink?.success(mapOf("event" to event, "requestId" to id))
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        manager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        methods = MethodChannel(binding.binaryMessenger, "abts/audio_focus")
        events = EventChannel(binding.binaryMessenger, "abts/audio_focus_events")
        methods.setMethodCallHandler { call, result ->
            when (call.method) {
                "request" -> {
                    val id = call.argument<Number>("requestId")?.toLong()
                    if (id == null) result.success("failed")
                    else result.success(requestFocus(id, call.argument<Boolean>("speech") == true))
                }
                "abandon" -> {
                    if (call.argument<Number>("requestId")?.toLong() == requestId) abandonFocus()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        events.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sink = events }
            override fun onCancel(arguments: Any?) { sink = null }
        })
        val filter = IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(noisyReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(noisyReceiver, filter)
        }
        receiverRegistered = true
    }

    private fun requestFocus(id: Long, speech: Boolean): String {
        abandonFocus()
        requestId = id
        val callback = AudioManager.OnAudioFocusChangeListener { change ->
            if (requestId == id) when (change) {
                AudioManager.AUDIOFOCUS_GAIN -> emit("gained", id)
                AudioManager.AUDIOFOCUS_LOSS -> emit("lost", id)
                AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> emit("interrupted", id)
                AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> emit("ducked", id)
            }
        }
        listener = callback
        val outcome = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val focus = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                    .setAudioAttributes(AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(if (speech) AudioAttributes.CONTENT_TYPE_SPEECH
                            else AudioAttributes.CONTENT_TYPE_MUSIC).build())
                    .setAcceptsDelayedFocusGain(true)
                    .setWillPauseWhenDucked(speech)
                    .setOnAudioFocusChangeListener(callback, Handler(Looper.getMainLooper()))
                    .build()
                request = focus
                manager.requestAudioFocus(focus)
            } else {
                @Suppress("DEPRECATION")
                manager.requestAudioFocus(callback, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN)
            }
        } catch (_: Exception) {
            AudioManager.AUDIOFOCUS_REQUEST_FAILED
        }
        return when (outcome) {
            AudioManager.AUDIOFOCUS_REQUEST_GRANTED -> "granted"
            AudioManager.AUDIOFOCUS_REQUEST_DELAYED -> "delayed"
            else -> { abandonFocus(); "failed" }
        }
    }

    private fun abandonFocus() {
        requestId = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            request?.let { manager.abandonAudioFocusRequest(it) }
        } else {
            @Suppress("DEPRECATION")
            listener?.let { manager.abandonAudioFocus(it) }
        }
        request = null
        listener = null
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        abandonFocus()
        if (receiverRegistered) {
            context.unregisterReceiver(noisyReceiver)
            receiverRegistered = false
        }
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        sink = null
    }
}
