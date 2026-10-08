package com.mapzone.mapzone_speed_alert

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry.RequestPermissionsResultListener
import map.zone.speedalertsdk.AccessRestrictionCallback
import map.zone.speedalertsdk.BitmapCallback
import map.zone.speedalertsdk.BuildupAreaCallback
import map.zone.speedalertsdk.ReadyCallback
import map.zone.speedalertsdk.ResultCallback
import map.zone.speedalertsdk.StopRestrictionCallback
import map.zone.speedalertsdk.VoiceAlertType
import map.zone.speedalertsdk.VoiceCallback
import map.zone.speedalertsdk.VoiceProfile
import map.zone.speedalertsdk.ZoneNetworkManager
import java.io.ByteArrayOutputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Flutter bridge over the MapZone Speed Alert SDK ([ZoneNetworkManager]).
 *
 * The native engine is process-wide, so the plugin keeps one manager for its
 * whole lifetime: `initialize` / `configureVehicle` reset and re-configure it
 * instead of building a new one.
 *
 * GPS is captured with the Android framework [LocationManager].
 *
 * Voice: the SDK plays clips through its built-in player until Dart listens to
 * the `voice` channel; while that listener exists the clips are forwarded to
 * Dart instead, and cancelling it hands playback back to the SDK.
 */
class MapzoneSpeedAlertPlugin :
    FlutterPlugin, MethodCallHandler, ActivityAware, RequestPermissionsResultListener {

    private companion object {
        const val CHANNEL = "mapzone_speed_alert"
        const val TAG = "MapZoneSpeedAlert"
        const val PERMISSION_REQUEST_CODE = 4021
        const val MIN_TIME_MS = 1000L
        const val MIN_DISTANCE_M = 0f
    }

    private lateinit var appContext: Context
    private lateinit var methodChannel: MethodChannel
    private var activity: Activity? = null
    private val main = Handler(Looper.getMainLooper())

    private lateinit var mgr: ZoneNetworkManager

    // Restriction images are PNG-encoded off the main thread; one thread keeps
    // the group updates in order and owns [restriction].
    private lateinit var encoder: ExecutorService

    private val eventChannels = mutableListOf<EventChannel>()
    private val streams = mutableListOf<CallbackStream>()
    private lateinit var alertStream: CallbackStream
    private lateinit var readyStream: CallbackStream
    private lateinit var resultStream: CallbackStream
    private lateinit var locationStream: CallbackStream
    private lateinit var voiceStream: CallbackStream
    private lateinit var restrictionStream: CallbackStream

    private var systemLocationManager: LocationManager? = null
    private var locationListener: LocationListener? = null

    // Whether this engine configured the native engine. Flutter attaches the
    // plugin to every engine (background isolates too), so teardown must only
    // reset what this instance set up.
    private var configured = false

    // Whether this engine installed the SDK's process-wide (static) bitmap and
    // restriction callbacks. They are installed on the first configure, not on
    // attach, so a background engine that never configures cannot take them
    // over — or clear them on detach.
    private var callbacksInstalled = false

    // Cached engine config so configureVehicle can re-configure.
    private var baseUrl = ""
    private var apiKeyId = ""
    private var apiKey = ""
    private var vehicleId = ""
    private var vehicleType = 1
    private var seats = 4
    private var weight = 1500.0

    // Voice preferences live here as well as in the engine and are re-applied
    // after every configure, so a configureVehicle can never silently undo
    // what Dart believes is set.
    private var mutedTypes = emptySet<VoiceAlertType>()
    private var voiceProfile = VoiceProfile.FULL

    // Last bitmap references, for change detection (avoid re-encoding PNGs).
    private var lastCur: Bitmap? = null
    private var lastNext: Bitmap? = null
    private var lastCam: Bitmap? = null
    private var lastToll: Bitmap? = null

    // Merged restriction signs. The SDK reports each group only when it
    // changes, so the latest state is kept here and replayed to new listeners.
    // Only touched on [encoder].
    private var restriction = RestrictionSnapshot()

    // Pending permission request result (single-shot).
    private var pendingPermissionResult: Result? = null

    // MARK: - FlutterPlugin

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        mgr = ZoneNetworkManager()
        encoder = Executors.newSingleThreadExecutor()
        val messenger = binding.binaryMessenger
        methodChannel = MethodChannel(messenger, CHANNEL)
        methodChannel.setMethodCallHandler(this)

        alertStream = stream(messenger, "alert")
        readyStream = stream(messenger, "ready")
        resultStream = stream(messenger, "result")
        locationStream = stream(messenger, "location")
        voiceStream = stream(
            messenger, "voice",
            onOpen = { mgr.setVoiceCallback(voiceCallback) },
            onClose = { mgr.setVoiceCallback(null) },
        )
        restrictionStream = stream(
            messenger, "restriction",
            onOpen = { encoder.execute { restrictionStream.send(restriction.toMap()) } },
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannels.forEach { it.setStreamHandler(null) }
        eventChannels.clear()
        // Drop the voice callback this engine installed so the built-in player
        // is not left muted by a detached engine.
        streams.forEach { it.release() }
        streams.clear()
        stopLocationUpdates()
        if (callbacksInstalled) {
            mgr.setBitmapCallback(null)
            mgr.setAccessRestrictionCallback(null)
            mgr.setStopRestrictionCallback(null)
            mgr.setBuildupAreaCallback(null)
            callbacksInstalled = false
        }
        if (configured) {
            mgr.reset()
            configured = false
        }
        encoder.shutdown()
    }

    // MARK: - MethodCallHandler

    override fun onMethodCall(call: MethodCall, result: Result) {
        Log.d(TAG, "call: ${call.method}")
        when (call.method) {
            "getPlatformVersion" ->
                result.success("Android ${Build.VERSION.RELEASE}")

            "initialize" -> {
                readConfig(call)
                applyConfig(result)
            }

            "configureVehicle" -> {
                vehicleType = call.argument<Number>("vehicleType")?.toInt() ?: vehicleType
                seats = call.argument<Number>("seats")?.toInt() ?: seats
                weight = call.argument<Number>("weight")?.toDouble() ?: weight
                applyConfig(result)
            }

            "start" -> startTracking(result)

            "stop" -> {
                stopLocationUpdates()
                result.success(null)
            }

            "reset" -> {
                stopLocationUpdates()
                mgr.reset()
                configured = false
                resetImageCache()
                clearRestriction()
                result.success(null)
            }

            "processExternalLocation" -> {
                val lat = call.argument<Number>("lat")?.toDouble() ?: 0.0
                val lng = call.argument<Number>("lng")?.toDouble() ?: 0.0
                val bearing = call.argument<Number>("bearing")?.toDouble() ?: 0.0
                val speedKmh = call.argument<Number>("speedKmh")?.toDouble() ?: 0.0
                val accuracy = call.argument<Number>("accuracy")?.toDouble() ?: 0.0
                // Dart always sends the fix time; the fallback only guards
                // against a malformed call.
                val fixTime = call.argument<Number>("fixTimeMillis")?.toLong()
                    ?: System.currentTimeMillis()
                // Before initialize there is no engine of ours to feed.
                if (configured) {
                    mgr.updateLocation(lat, lng, speedKmh, bearing)
                    mgr.processGps(lat, lng, bearing, speedKmh, accuracy, fixTime)
                }
                result.success(null)
            }

            "updateZoneLocation" -> {
                val lat = call.argument<Number>("lat")?.toDouble() ?: 0.0
                val lng = call.argument<Number>("lng")?.toDouble() ?: 0.0
                if (configured) mgr.updateLocation(lat, lng)
                result.success(null)
            }

            "setMutedAlertTypes" -> {
                val triggers = call.argument<List<Int>>("triggers") ?: emptyList()
                mutedTypes = VoiceAlertType.values()
                    .filter { it.triggerValue in triggers }
                    .toSet()
                Log.d(TAG, "setMutedAlertTypes ${mutedTypes.map { it.triggerValue }.sorted()}")
                mgr.setMutedAlertTypes(mutedTypes)
                result.success(null)
            }

            "setVoiceProfile" -> {
                val value = call.argument<Number>("profile")?.toInt() ?: 0
                voiceProfile = VoiceProfile.values()
                    .firstOrNull { it.profileValue == value } ?: VoiceProfile.FULL
                mgr.setVoiceProfile(voiceProfile)
                result.success(null)
            }

            "setVoiceSpeed" -> {
                val speed = call.argument<Number>("speed")?.toFloat() ?: 1f
                mgr.setVoiceSpeed(speed)
                result.success(null)
            }

            // Removed from the native SDK in 2.0.2; kept so old callers get null.
            "getLinkCoords" -> result.success(null)

            "hasLocationPermissions" -> result.success(hasLocationPermission())

            "requestLocationPermissions" -> requestPermissions(result)

            "onAppBackground", "onAppForeground" -> result.success(null)

            else -> result.notImplemented()
        }
    }

    // MARK: - Engine setup & SDK callbacks

    private fun readConfig(call: MethodCall) {
        baseUrl = call.argument<String>("baseUrl") ?: ""
        apiKeyId = call.argument<String>("apiKeyId") ?: ""
        apiKey = call.argument<String>("apiKey") ?: ""
        vehicleId = call.argument<String>("vehicleId") ?: ""
        vehicleType = call.argument<Number>("vehicleType")?.toInt() ?: 1
        seats = call.argument<Number>("seats")?.toInt() ?: 4
        // Dart sends weight as int; configure() wants Double.
        weight = call.argument<Number>("weight")?.toDouble() ?: 1500.0
    }

    /**
     * Reset the engine and configure it with the cached config. The SDK
     * resolves the host application id itself, so it must match the id
     * registered for the API key.
     */
    private fun applyConfig(result: Result) {
        if (!callbacksInstalled) {
            wireCallbacks()
            callbacksInstalled = true
        }
        mgr.reset()
        resetImageCache()
        clearRestriction()
        Log.d(
            TAG,
            "configure baseUrl=$baseUrl vehicleId=$vehicleId " +
                "type=$vehicleType seats=$seats weight=$weight"
        )
        try {
            mgr.configure(baseUrl, apiKeyId, apiKey, vehicleId, vehicleType, seats, weight)
        } catch (e: RuntimeException) {
            // IllegalArgumentException (non-https baseUrl) or
            // IllegalStateException (host application id unresolvable).
            configured = false
            result.error("CONFIGURE_FAILED", e.message, null)
            return
        }
        // Re-apply the host's voice preferences before any GPS reaches it.
        mgr.setMutedAlertTypes(mutedTypes)
        mgr.setVoiceProfile(voiceProfile)
        configured = true
        result.success(null)
    }

    /** Register the SDK callbacks; they stay wired until the engine detaches. */
    private fun wireCallbacks() {
        mgr.setBitmapCallback(object : BitmapCallback {
            override fun onBitmap(
                current: Bitmap?, status: Int,
                next: Bitmap?, nextDist: Int,
                camera: Bitmap?, cameraDist: Int,
                toll: Bitmap?, tollDist: Int,
                voiceWav: ByteArray?
            ) {
                val map = HashMap<String, Any?>()
                map["speedStatus"] = status
                lastCur = putSign(map, "cur", current, lastCur, null)
                lastNext = putSign(map, "next", next, lastNext, nextDist)
                lastCam = putSign(map, "cam", camera, lastCam, cameraDist)
                lastToll = putSign(map, "toll", toll, lastToll, tollDist)
                alertStream.send(map)
            }
        })
        mgr.setReadyCallback(object : ReadyCallback {
            override fun onReady(isReady: Boolean, linkCount: Int, alertCount: Int) {
                Log.d(TAG, "onReady isReady=$isReady links=$linkCount alerts=$alertCount")
                readyStream.send(
                    mapOf(
                        "isReady" to isReady,
                        "linkCount" to linkCount,
                        "alertCount" to alertCount
                    )
                )
            }
        })
        mgr.setResultCallback(object : ResultCallback {
            override fun onResult(success: Boolean, errorCode: Int, errorMessage: String?) {
                Log.d(TAG, "onResult success=$success code=$errorCode message=$errorMessage")
                resultStream.send(
                    mapOf(
                        "success" to success,
                        "errorCode" to errorCode,
                        "errorMessage" to errorMessage
                    )
                )
            }
        })
        mgr.setAccessRestrictionCallback(object : AccessRestrictionCallback {
            override fun onAccessRestriction(bmp: Bitmap?, kind: Int, distMeters: Int) =
                updateRestriction { it.withAccess(png(bmp), kind, distMeters) }
        })
        mgr.setStopRestrictionCallback(object : StopRestrictionCallback {
            override fun onStopRestriction(bmp: Bitmap?, kind: Int, distMeters: Int) =
                updateRestriction { it.withStop(png(bmp), kind, distMeters) }
        })
        mgr.setBuildupAreaCallback(object : BuildupAreaCallback {
            override fun onBuildupArea(bmp: Bitmap?, kind: Int, distMeters: Int) =
                updateRestriction { it.withBuildupArea(png(bmp), kind, distMeters) }
        })
    }

    // Explicit object, not a lambda: a SAM lambda would bind the 1-arg
    // overload and lose trigger/priority.
    private val voiceCallback = object : VoiceCallback {
        override fun onVoice(wavBytes: ByteArray?) = emitVoice(wavBytes, 0, 1)

        override fun onVoice(wavBytes: ByteArray?, trigger: Int, priority: Int) =
            emitVoice(wavBytes, trigger, priority)
    }

    private fun emitVoice(wav: ByteArray?, trigger: Int, priority: Int) {
        if (wav == null || wav.isEmpty()) return
        voiceStream.send(mapOf("wav" to wav, "trigger" to trigger, "priority" to priority))
    }

    // MARK: - Restriction signs

    /**
     * Apply one group update on [encoder] (the PNG encode inside [update]
     * runs there too) and forward the merged snapshot.
     */
    private fun updateRestriction(update: (RestrictionSnapshot) -> RestrictionSnapshot) {
        encoder.execute {
            restriction = update(restriction)
            restrictionStream.send(restriction.toMap())
        }
    }

    /** Forget every restriction sign and tell Dart the slots are now empty. */
    private fun clearRestriction() = updateRestriction { RestrictionSnapshot() }

    // MARK: - Sign image encoding (change-detected PNG)

    /**
     * Populate [map] for one sign slot, only encoding a PNG when the bitmap
     * reference changed since last frame. Returns the bitmap to cache.
     */
    private fun putSign(
        map: HashMap<String, Any?>,
        key: String,
        bmp: Bitmap?,
        last: Bitmap?,
        dist: Int?
    ): Bitmap? {
        val present = bmp != null
        map["${key}Present"] = present
        if (!present) {
            map["${key}Changed"] = false
            return null
        }
        val changed = bmp !== last
        map["${key}Changed"] = changed
        if (changed) map["${key}Sign"] = png(bmp)
        if (dist != null) map["${key}Dist"] = dist
        return bmp
    }

    private fun png(bmp: Bitmap?): ByteArray? = bmp?.let {
        val out = ByteArrayOutputStream()
        it.compress(Bitmap.CompressFormat.PNG, 100, out)
        out.toByteArray()
    }

    private fun resetImageCache() {
        lastCur = null
        lastNext = null
        lastCam = null
        lastToll = null
    }

    // MARK: - GPS capture (Approach A)

    @SuppressLint("MissingPermission")
    private fun startTracking(result: Result) {
        if (!configured) {
            result.error("NOT_INITIALIZED", "Call initialize() before start().", null)
            return
        }
        if (!hasLocationPermission()) {
            result.error("PERMISSION_DENIED", "Location permission not granted.", null)
            return
        }
        stopLocationUpdates()
        val lm = appContext.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
        if (lm == null) {
            result.error("NO_LOCATION_SERVICE", "LocationManager unavailable.", null)
            return
        }
        val listener = object : LocationListener {
            override fun onLocationChanged(location: Location) = handleLocation(location)
            override fun onProviderEnabled(provider: String) {}
            override fun onProviderDisabled(provider: String) {}

            @Deprecated("Deprecated in Java")
            override fun onStatusChanged(provider: String?, status: Int, extras: android.os.Bundle?) {
            }
        }
        try {
            lm.requestLocationUpdates(
                LocationManager.GPS_PROVIDER, MIN_TIME_MS, MIN_DISTANCE_M,
                listener, Looper.getMainLooper()
            )
        } catch (e: Exception) {
            result.error("LOCATION_ERROR", e.message, null)
            return
        }
        systemLocationManager = lm
        locationListener = listener
        result.success(null)
    }

    private fun handleLocation(location: Location) {
        val lat = location.latitude
        val lng = location.longitude
        val bearing = location.bearing.toDouble()
        val accuracy = location.accuracy.toDouble()
        // Location.speed is m/s; the SDK expects km/h.
        val speed = location.speed.toDouble() * 3.6
        Log.d(TAG, "gps lat=$lat lng=$lng spd=$speed acc=$accuracy")
        mgr.updateLocation(lat, lng, speed, bearing)
        // The engine times voice throttling and stop detection against the
        // fix's own clock, never the time this callback ran.
        mgr.processGps(lat, lng, bearing, speed, accuracy, location.time)
        locationStream.send(
            mapOf(
                "lat" to lat,
                "lng" to lng,
                "speedKmh" to speed,
                "bearing" to bearing,
                "accuracy" to accuracy,
                "timestamp" to location.time
            )
        )
    }

    private fun stopLocationUpdates() {
        locationListener?.let { systemLocationManager?.removeUpdates(it) }
        locationListener = null
        systemLocationManager = null
    }

    // MARK: - Permissions

    private fun hasLocationPermission(): Boolean {
        val fine = appContext.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION)
        val coarse = appContext.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION)
        return fine == PackageManager.PERMISSION_GRANTED ||
            coarse == PackageManager.PERMISSION_GRANTED
    }

    private fun requestPermissions(result: Result) {
        val act = activity
        if (act == null) {
            result.error("NO_ACTIVITY", "Plugin is not attached to an Activity.", null)
            return
        }
        if (hasLocationPermission()) {
            result.success(true)
            return
        }
        pendingPermissionResult = result
        act.requestPermissions(
            arrayOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION
            ),
            PERMISSION_REQUEST_CODE
        )
    }

    // MARK: - Event channels

    /**
     * Register an event channel. [onOpen] runs when Dart starts listening and
     * [onClose] when it stops (or the engine detaches while listening).
     */
    private fun stream(
        messenger: BinaryMessenger,
        name: String,
        onOpen: () -> Unit = {},
        onClose: () -> Unit = {},
    ): CallbackStream {
        val channel = EventChannel(messenger, "$CHANNEL/$name")
        val handler = CallbackStream(main, onOpen, onClose)
        channel.setStreamHandler(handler)
        eventChannels += channel
        streams += handler
        return handler
    }

    // MARK: - ActivityAware & permission results

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        if (requestCode != PERMISSION_REQUEST_CODE) return false
        val granted = grantResults.isNotEmpty() &&
            grantResults.any { it == PackageManager.PERMISSION_GRANTED }
        pendingPermissionResult?.success(granted)
        pendingPermissionResult = null
        return true
    }
}

/**
 * The restriction slots Dart sees, merged from the SDK's three independent
 * groups (access, stop, built-up area). An image without artwork arrives as
 * `null` and leaves its slot empty.
 */
private data class RestrictionSnapshot(
    val stop: ByteArray? = null,
    val stopDist: Int = 0,
    val closed: ByteArray? = null,
    val closedDist: Int = 0,
    val vehicle: ByteArray? = null,
    val vehicleDist: Int = 0,
    val bua: ByteArray? = null,
    val buaDist: Int = 0,
    val inBua: Boolean = false,
) {
    /** Access group: one of road-closed / vehicle-restricted, or neither. */
    fun withAccess(png: ByteArray?, kind: Int, dist: Int) = copy(
        closed = png.takeIf { kind == AccessRestrictionCallback.KIND_ROAD_CLOSED },
        closedDist = if (kind == AccessRestrictionCallback.KIND_ROAD_CLOSED) dist else 0,
        vehicle = png.takeIf { kind == AccessRestrictionCallback.KIND_VEHICLE_RESTRICTED },
        vehicleDist = if (kind == AccessRestrictionCallback.KIND_VEHICLE_RESTRICTED) dist else 0,
    )

    /** Stop group: no-parking or no-stopping share the one slot. */
    fun withStop(png: ByteArray?, kind: Int, dist: Int) = copy(
        stop = png.takeIf { kind != StopRestrictionCallback.KIND_NONE },
        stopDist = if (kind != StopRestrictionCallback.KIND_NONE) dist else 0,
    )

    /** Built-up area: entry or end sign; `dist == 0` with START means inside. */
    fun withBuildupArea(png: ByteArray?, kind: Int, dist: Int) = copy(
        bua = png.takeIf { kind != BuildupAreaCallback.KIND_NONE },
        buaDist = if (kind != BuildupAreaCallback.KIND_NONE) dist else 0,
        inBua = kind == BuildupAreaCallback.KIND_START && dist == 0,
    )

    fun toMap(): Map<String, Any?> = mapOf(
        "stop" to stop,
        "stopDistMeters" to stopDist,
        "closed" to closed,
        "closedDistMeters" to closedDist,
        "vehicle" to vehicle,
        "vehicleDistMeters" to vehicleDist,
        "bua" to bua,
        "buaDistMeters" to buaDist,
        "inBua" to inBua,
    )
}

/**
 * [EventChannel.StreamHandler] that keeps a sink, posts events on the main
 * thread, and runs open/close hooks around the Dart subscription.
 */
private class CallbackStream(
    private val main: Handler,
    private val onOpen: () -> Unit,
    private val onClose: () -> Unit,
) : EventChannel.StreamHandler {
    @Volatile
    private var sink: EventChannel.EventSink? = null

    // Whether [onOpen] ran without a matching [onClose].
    private var active = false

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        active = true
        onOpen()
    }

    override fun onCancel(arguments: Any?) = release()

    /** Undo [onOpen] if it is still in effect. */
    fun release() {
        sink = null
        if (active) {
            active = false
            onClose()
        }
    }

    fun send(data: Any?) {
        main.post { sink?.success(data) }
    }
}
