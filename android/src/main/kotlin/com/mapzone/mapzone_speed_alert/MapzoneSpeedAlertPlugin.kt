package com.mapzone.mapzone_speed_alert

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.location.Location
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
import map.zone.speedalertsdk.SnappedLocationCallback
import map.zone.speedalertsdk.StopRestrictionCallback
import map.zone.speedalertsdk.VehicleType
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
 * GPS (Approach A) is captured by [PluginLocationCapture]: Fused Location when
 * Play Services is usable, otherwise the OS `gps` + `network` providers.
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

        // Plugin-side result codes, mirrored in Dart `MapZoneErrorCode` and the
        // iOS plugin. The -100…-199 range never overlaps the native SDK's codes.
        // -101 (permission lost) is iOS only: revoking a runtime permission on
        // Android kills the process.
        const val ERROR_LOCATION_UNAVAILABLE = -100
        const val MESSAGE_LOCATION_UNAVAILABLE = "Location is unavailable on this device."
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
    private lateinit var snappedLocationStream: CallbackStream

    // Native GPS capture (Approach A) and the heading it last sent.
    private var locationCapture: PluginLocationCapture? = null
    private var bearingHold = BearingHold()

    private val isDebuggable: Boolean by lazy {
        (appContext.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
    }

    // Whether this engine configured the native engine. Flutter attaches the
    // plugin to every engine (background isolates too), so teardown must only
    // reset what this instance set up.
    private var configured = false

    // Whether this engine installed the SDK's process-wide (static) bitmap and
    // restriction callbacks. They are installed on the first configure, not on
    // attach, so a background engine that never configures cannot take them
    // over — or clear them on detach.
    private var callbacksInstalled = false

    // The configuration the engine last accepted, so configureVehicle can
    // re-configure with the same identity. A rejected configure leaves it as
    // it was, matching the SDK, which keeps the previous configuration.
    private var appliedConfig: EngineConfig? = null

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
        // The SDK only makes the snapped-location upcall while a callback is
        // set, so it is installed for as long as Dart listens.
        snappedLocationStream = stream(
            messenger, "snapped",
            onOpen = { mgr.setSnappedLocationCallback(snappedLocationCallback) },
            onClose = { mgr.setSnappedLocationCallback(null) },
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

            "initialize" -> applyConfig(EngineConfig.fromCall(call), result)

            "configureVehicle" -> {
                val applied = appliedConfig
                if (applied == null) {
                    result.error(
                        "NOT_INITIALIZED", "Call initialize() before configureVehicle().", null
                    )
                    return
                }
                applyConfig(applied.withVehicle(call), result)
            }

            "logout" -> {
                // Signed out means configureVehicle can no longer sign anyone
                // back in: only initialize does. Forgotten even if the request
                // fails — the SDK is signed out locally either way.
                appliedConfig = null
                mgr.logout(object : ResultCallback {
                    // The SDK reports on the main thread.
                    override fun onResult(success: Boolean, errorCode: Int, errorMessage: String?) {
                        Log.d(TAG, "logout success=$success code=$errorCode")
                        result.success(resultMap(success, errorCode, errorMessage))
                    }
                })
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

    /**
     * Reset the engine and configure it with [config]. The SDK resolves the
     * host application id itself, so it must match the id registered for the
     * API key. Signing the identity in then runs in the background inside the
     * SDK; its outcome arrives on the `result` channel.
     */
    private fun applyConfig(config: EngineConfig, result: Result) {
        // Unknown codes never reach the SDK, whose enum has no value for them.
        val vehicleType = VehicleType.fromValue(config.vehicleTypeCode)
        if (vehicleType == null) {
            result.error(
                "INVALID_CONFIGURATION",
                "Unsupported vehicle type code ${config.vehicleTypeCode}.",
                null
            )
            return
        }
        if (!callbacksInstalled) {
            wireCallbacks()
            callbacksInstalled = true
        }
        // Identity and metadata are personal data: never logged.
        Log.d(
            TAG,
            "configure type=${config.vehicleTypeCode} seats=${config.seats} " +
                "weightTons=${config.weightTons}"
        )
        val rejection = try {
            mgr.configure(
                config.baseUrl, config.apiKeyId, config.apiKey, config.identity,
                vehicleType, config.seats, config.weightTons, config.metadataJson
            )
        } catch (e: RuntimeException) {
            // IllegalArgumentException (non-https baseUrl) or
            // IllegalStateException (host application id unresolvable).
            configured = false
            result.error("CONFIGURE_FAILED", e.message, null)
            return
        }
        if (rejection != null) {
            // Nothing was applied: the previous configuration (if any) stays
            // in effect, and the loaded zone, signs and what this plugin
            // remembers are left untouched.
            result.error("INVALID_CONFIGURATION", rejection, null)
            return
        }
        // Accepted: drop the zone loaded for the previous profile. The clear
        // runs on the SDK's queue after the sign-in it just queued, and keeps
        // the session.
        mgr.reset()
        resetImageCache()
        clearRestriction()
        appliedConfig = config
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
                resultStream.send(resultMap(success, errorCode, errorMessage))
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

    private val snappedLocationCallback =
        SnappedLocationCallback { latitude, longitude, bearingDegrees ->
            snappedLocationStream.send(
                mapOf("lat" to latitude, "lng" to longitude, "bearing" to bearingDegrees)
            )
        }

    private fun resultMap(success: Boolean, errorCode: Int, errorMessage: String?) =
        mapOf("success" to success, "errorCode" to errorCode, "errorMessage" to errorMessage)

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
        // A new run starts from no heading, like the engine after reset.
        bearingHold = BearingHold()
        if (appContext.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            Log.w(TAG, "Only approximate location granted: fixes will be coarse, without speed or heading")
        }
        val capture = PluginLocationCapture(appContext, ::handleLocation) {
            // Same channel, code and sentence as the iOS plugin.
            resultStream.send(
                resultMap(false, ERROR_LOCATION_UNAVAILABLE, MESSAGE_LOCATION_UNAVAILABLE)
            )
        }
        if (!capture.start()) {
            result.error("NO_LOCATION_SERVICE", "No location source could be started.", null)
            return
        }
        locationCapture = capture
        result.success(null)
    }

    private fun handleLocation(location: Location) {
        val lat = location.latitude
        val lng = location.longitude
        // A fix without speed reports 0 for it anyway, but say so explicitly:
        // the same goes for bearing, where 0 is a real heading (north).
        val speedMetersPerSecond = if (location.hasSpeed()) location.speed.toDouble() else 0.0
        val speedKmh = speedMetersPerSecond * 3.6
        val bearing = bearingHold.bearingFor(
            location.hasBearing(), location.bearing.toDouble(), speedMetersPerSecond
        )
        val accuracy = if (location.hasAccuracy()) location.accuracy.toDouble() else 0.0
        // Coordinates only in debuggable builds: release logs carry no location.
        if (isDebuggable) {
            Log.d(
                TAG,
                "gps provider=${location.provider} lat=$lat lng=$lng spd=$speedKmh acc=$accuracy"
            )
        }
        mgr.updateLocation(lat, lng, speedKmh, bearing)
        // The engine times voice throttling and stop detection against the
        // fix's own clock, never the time this callback ran.
        mgr.processGps(lat, lng, bearing, speedKmh, accuracy, location.time)
        locationStream.send(
            mapOf(
                "lat" to lat,
                "lng" to lng,
                "speedKmh" to speedKmh,
                "bearing" to bearing,
                "accuracy" to accuracy,
                "timestamp" to location.time
            )
        )
    }

    private fun stopLocationUpdates() {
        locationCapture?.stop()
        locationCapture = null
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
 * One `configure` call's inputs, as sent by Dart. [vehicleTypeCode] is the
 * server's vehicle code; [metadataJson] is already JSON-encoded by Dart (the
 * SDK validates it).
 */
private data class EngineConfig(
    val baseUrl: String,
    val apiKeyId: String,
    val apiKey: String,
    val identity: String,
    val vehicleTypeCode: Int,
    val seats: Int,
    val weightTons: Double,
    val metadataJson: String?,
) {
    /** The same identity and keys with the vehicle fields of [call]. */
    fun withVehicle(call: MethodCall) = copy(
        vehicleTypeCode = call.argument<Number>("vehicleType")?.toInt() ?: vehicleTypeCode,
        seats = call.argument<Number>("seats")?.toInt() ?: seats,
        weightTons = call.argument<Number>("weightTons")?.toDouble() ?: weightTons,
    )

    // Credentials and identity must never appear in logs.
    override fun toString() =
        "EngineConfig(type=$vehicleTypeCode, seats=$seats, weightTons=$weightTons)"

    companion object {
        fun fromCall(call: MethodCall) = EngineConfig(
            baseUrl = call.argument<String>("baseUrl") ?: "",
            apiKeyId = call.argument<String>("apiKeyId") ?: "",
            apiKey = call.argument<String>("apiKey") ?: "",
            identity = call.argument<String>("identity") ?: "",
            vehicleTypeCode = call.argument<Number>("vehicleType")?.toInt() ?: 1,
            seats = call.argument<Number>("seats")?.toInt() ?: 4,
            weightTons = call.argument<Number>("weightTons")?.toDouble() ?: 1.5,
            metadataJson = call.argument<String>("metadata"),
        )
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
