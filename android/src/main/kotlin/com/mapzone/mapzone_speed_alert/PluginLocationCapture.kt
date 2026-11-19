package com.mapzone.mapzone_speed_alert

import android.annotation.SuppressLint
import android.content.Context
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import android.os.Looper
import android.util.Log
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority

/**
 * Where native GPS capture (Approach A) reads positions from, in the order it
 * tries them. The same ladder as the MapZone Android app.
 */
internal enum class LocationSource {
    /** Google's Fused Location: GPS + Wi-Fi + cell, so it also works indoors. */
    PLAY_SERVICES,

    /** The OS `LocationManager`: `gps` and `network` together, see [GnssFixFilter]. */
    PLATFORM,

    /** Nothing left to try. */
    NONE,
}

/** Source choice, kept free of Android APIs so it runs in JVM tests. */
internal object LocationSourceSelector {

    fun initial(playServicesUsable: Boolean, platformHasProvider: Boolean): LocationSource = when {
        playServicesUsable -> LocationSource.PLAY_SERVICES
        platformHasProvider -> LocationSource.PLATFORM
        else -> LocationSource.NONE
    }

    /** Only ever steps down: Play Services failed → platform; platform failed → nothing. */
    fun next(failed: LocationSource, platformHasProvider: Boolean): LocationSource = when (failed) {
        LocationSource.PLAY_SERVICES ->
            if (platformHasProvider) LocationSource.PLATFORM else LocationSource.NONE
        LocationSource.PLATFORM, LocationSource.NONE -> LocationSource.NONE
    }
}

/**
 * Picks fixes while `gps` and `network` run together: a GPS fix is always taken;
 * a network fix (tens to hundreds of metres off) only once GPS has been silent
 * for more than [gpsHoldMillis]. Mixing the two while GPS is live makes the
 * position jump back and forth; without GPS (indoors, tunnels) the network
 * carries on until GPS returns.
 *
 * Times are the fixes' `elapsedRealtime` in milliseconds.
 */
internal class GnssFixFilter(private val gpsHoldMillis: Long = GPS_HOLD_MILLIS) {

    private var lastGpsAtMillis: Long? = null

    fun accept(provider: String?, atMillis: Long): Boolean {
        if (provider == LocationManager.GPS_PROVIDER) {
            lastGpsAtMillis = atMillis
            return true
        }
        val gpsAtMillis = lastGpsAtMillis ?: return true
        return atMillis - gpsAtMillis > gpsHoldMillis
    }

    companion object {
        /** A few 1 Hz ticks: missing one or two GPS fixes is not losing GPS. */
        const val GPS_HOLD_MILLIS = 5_000L
    }
}

/**
 * Heading sent to the engine. The engine snaps the fix to a road along this
 * heading, and `0` means "driving north": sending `0` (or the noise a phone
 * reports while standing still) makes it snap onto the opposite carriageway or
 * a crossing street. So without a heading, or below [MIN_BEARING_SPEED_MPS],
 * the last real heading is kept.
 */
internal class BearingHold {

    private var lastBearingDegrees = 0.0

    fun bearingFor(hasBearing: Boolean, bearingDegrees: Double, speedMetersPerSecond: Double): Double {
        if (hasBearing && speedMetersPerSecond >= MIN_BEARING_SPEED_MPS) {
            lastBearingDegrees = bearingDegrees
        }
        return lastBearingDegrees
    }

    companion object {
        /** About 3.6 km/h — slower than walking, the reported heading is noise. */
        const val MIN_BEARING_SPEED_MPS = 1.0
    }
}

/**
 * Native GPS capture for Approach A, modelled on the MapZone Android app:
 * Fused Location when Play Services is usable, otherwise the OS `gps` +
 * `network` providers (filtered by [GnssFixFilter]), otherwise `passive`.
 *
 * A source that fails to start (Play Services reports it through its `Task`)
 * hands over to the next one. A source that is merely silent is kept: indoors
 * the GPS chip is silent too, and switching away would only lose Google's
 * Wi-Fi/cell positioning.
 *
 * Main thread only — no locking.
 */
internal class PluginLocationCapture(
    context: Context,
    private val onLocation: (Location) -> Unit,
    /**
     * Every source failed after [start] had already returned true (Play
     * Services reported usable, then failed its request, and no OS provider
     * could take over). No fixes will arrive.
     */
    private val onExhausted: () -> Unit = {},
) {
    private val appContext = context.applicationContext
    private val locationManager: LocationManager? =
        appContext.getSystemService(Context.LOCATION_SERVICE) as? LocationManager

    /** The source currently delivering; [LocationSource.NONE] when stopped or exhausted. */
    var activeSource: LocationSource = LocationSource.NONE
        private set

    // Identifies the running source, so a late failure or fix from one already
    // replaced (or stopped) is ignored.
    private var generation = 0
    private var stopActive: () -> Unit = {}

    /**
     * Start delivering fixes. Returns false when no source could be started at
     * all (nothing is running then).
     */
    fun start(): Boolean {
        stop()
        val playServicesUsable = runCatching {
            GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(appContext) ==
                ConnectionResult.SUCCESS
        }.getOrDefault(false)
        startFrom(LocationSourceSelector.initial(playServicesUsable, platformHasProvider()))
        return activeSource != LocationSource.NONE
    }

    fun stop() {
        generation++
        val stopping = stopActive
        stopActive = {}
        activeSource = LocationSource.NONE
        runCatching { stopping() }
    }

    private fun startFrom(source: LocationSource) {
        val started = when (source) {
            LocationSource.PLAY_SERVICES -> startPlayServices()
            LocationSource.PLATFORM -> startPlatform()
            LocationSource.NONE -> false
        }
        if (source == LocationSource.NONE) {
            Log.e(TAG, "No location source could be started")
            val wasRunning = activeSource != LocationSource.NONE
            activeSource = LocationSource.NONE
            if (wasRunning) onExhausted()
            return
        }
        if (!started) {
            fallBackFrom(source, null)
            return
        }
        Log.d(TAG, "location source=$source")
    }

    private fun fallBackFrom(source: LocationSource, cause: Throwable?) {
        Log.w(TAG, "location source $source failed; trying the next one", cause)
        runCatching { stopActive() }
        stopActive = {}
        startFrom(LocationSourceSelector.next(source, platformHasProvider()))
    }

    @SuppressLint("MissingPermission")
    private fun startPlayServices(): Boolean {
        val client: FusedLocationProviderClient =
            runCatching { LocationServices.getFusedLocationProviderClient(appContext) }.getOrNull()
                ?: return false
        val myGeneration = ++generation
        val callback = object : LocationCallback() {
            override fun onLocationResult(result: LocationResult) {
                if (generation != myGeneration) return
                result.lastLocation?.let(onLocation)
            }
        }
        val request = LocationRequest.Builder(UPDATE_INTERVAL_MILLIS)
            .setPriority(Priority.PRIORITY_HIGH_ACCURACY)
            .setMinUpdateIntervalMillis(FASTEST_UPDATE_INTERVAL_MILLIS)
            .build()
        return runCatching {
            // Play Services does not throw on a device where it cannot run: it
            // fails the returned Task later.
            client.requestLocationUpdates(request, callback, Looper.getMainLooper())
                .addOnFailureListener { error ->
                    if (generation == myGeneration) fallBackFrom(LocationSource.PLAY_SERVICES, error)
                }
            stopActive = { client.removeLocationUpdates(callback) }
            activeSource = LocationSource.PLAY_SERVICES
        }.isSuccess
    }

    /**
     * Register every active provider the device has — even a disabled one: the
     * OS keeps the registration and starts delivering when the user turns
     * location back on. Falls back to `passive` when neither can be registered.
     */
    @SuppressLint("MissingPermission")
    private fun startPlatform(): Boolean {
        val manager = locationManager ?: return false
        val myGeneration = ++generation
        val filter = GnssFixFilter()
        val listener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                if (generation != myGeneration) return
                val atMillis = location.elapsedRealtimeNanos / 1_000_000
                if (filter.accept(location.provider, atMillis)) onLocation(location)
            }

            // Android 10 and older have no default bodies for these.
            @Deprecated("Required on Android 10 and older")
            override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) = Unit
            override fun onProviderEnabled(provider: String) = Unit
            override fun onProviderDisabled(provider: String) = Unit
        }
        val available = runCatching { manager.allProviders }.getOrNull().orEmpty()
        val registered = ACTIVE_PROVIDERS.filter { it in available }.filter { provider ->
            runCatching {
                manager.requestLocationUpdates(
                    provider, UPDATE_INTERVAL_MILLIS, 0f, listener, Looper.getMainLooper()
                )
            }.onFailure { Log.w(TAG, "could not register $provider", it) }.isSuccess
        }
        val passiveRegistered = registered.isEmpty() && runCatching {
            Log.e(TAG, "Neither gps nor network could be registered; listening passively")
            manager.requestLocationUpdates(
                LocationManager.PASSIVE_PROVIDER, UPDATE_INTERVAL_MILLIS, 0f, listener,
                Looper.getMainLooper()
            )
        }.isSuccess
        if (registered.isEmpty() && !passiveRegistered) return false
        stopActive = { manager.removeUpdates(listener) }
        activeSource = LocationSource.PLATFORM
        return true
    }

    private fun platformHasProvider(): Boolean {
        val providers = runCatching { locationManager?.allProviders }.getOrNull().orEmpty()
        return ACTIVE_PROVIDERS.any(providers::contains)
    }

    private companion object {
        const val TAG = "MapZoneSpeedAlert"
        const val UPDATE_INTERVAL_MILLIS = 1_000L
        const val FASTEST_UPDATE_INTERVAL_MILLIS = 500L
        val ACTIVE_PROVIDERS = listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)
    }
}
