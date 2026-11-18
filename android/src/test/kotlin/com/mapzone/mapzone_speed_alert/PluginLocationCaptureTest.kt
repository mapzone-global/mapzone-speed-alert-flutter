package com.mapzone.mapzone_speed_alert

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class LocationSourceSelectorTest {

    @Test
    fun startsWithPlayServicesWhenUsable() {
        assertEquals(LocationSource.PLAY_SERVICES, LocationSourceSelector.initial(true, true))
        assertEquals(LocationSource.PLAY_SERVICES, LocationSourceSelector.initial(true, false))
    }

    @Test
    fun startsWithPlatformWithoutPlayServices() {
        assertEquals(LocationSource.PLATFORM, LocationSourceSelector.initial(false, true))
        assertEquals(LocationSource.NONE, LocationSourceSelector.initial(false, false))
    }

    @Test
    fun onlyStepsDown() {
        assertEquals(LocationSource.PLATFORM, LocationSourceSelector.next(LocationSource.PLAY_SERVICES, true))
        assertEquals(LocationSource.NONE, LocationSourceSelector.next(LocationSource.PLAY_SERVICES, false))
        assertEquals(LocationSource.NONE, LocationSourceSelector.next(LocationSource.PLATFORM, true))
        assertEquals(LocationSource.NONE, LocationSourceSelector.next(LocationSource.NONE, true))
    }
}

class GnssFixFilterTest {

    @Test
    fun networkFixesPassBeforeAnyGpsFix() {
        val filter = GnssFixFilter()
        assertTrue(filter.accept("network", 1_000))
        assertTrue(filter.accept("network", 2_000))
    }

    @Test
    fun gpsFixesAlwaysPass() {
        val filter = GnssFixFilter()
        assertTrue(filter.accept("gps", 1_000))
        assertTrue(filter.accept("gps", 1_100))
    }

    @Test
    fun networkFixesAreDroppedWhileGpsIsLive() {
        val filter = GnssFixFilter(gpsHoldMillis = 5_000)
        filter.accept("gps", 10_000)
        assertFalse(filter.accept("network", 12_000))
        assertFalse(filter.accept("network", 15_000), "exactly the hold is still GPS time")
    }

    @Test
    fun networkTakesOverOnceGpsIsSilent() {
        val filter = GnssFixFilter(gpsHoldMillis = 5_000)
        filter.accept("gps", 10_000)
        assertTrue(filter.accept("network", 15_001))
        // GPS back: network is held off again.
        filter.accept("gps", 20_000)
        assertFalse(filter.accept("network", 21_000))
    }
}

class BearingHoldTest {

    @Test
    fun startsAtZeroWithoutAnyHeading() {
        assertEquals(0.0, BearingHold().bearingFor(false, 0.0, 0.0))
    }

    @Test
    fun takesTheHeadingWhenMoving() {
        val hold = BearingHold()
        assertEquals(90.0, hold.bearingFor(true, 90.0, 10.0))
    }

    @Test
    fun keepsTheLastHeadingWhenStoppedOrWithoutHeading() {
        val hold = BearingHold()
        hold.bearingFor(true, 135.0, 8.0)
        assertEquals(135.0, hold.bearingFor(true, 0.0, 0.2), "noise while standing still")
        assertEquals(135.0, hold.bearingFor(false, 0.0, 8.0), "fix without a heading")
        assertEquals(200.0, hold.bearingFor(true, 200.0, 1.0), "1 m/s counts as moving")
    }
}
