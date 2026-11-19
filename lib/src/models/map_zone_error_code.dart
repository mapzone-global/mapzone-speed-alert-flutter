/// Result codes reported through [AlertResult.errorCode] — on the `onResult`
/// stream and by [MapZoneSpeedAlert.logout].
///
/// The values are the native SDK 3.0.1 codes (`MapZoneError` on Android and
/// iOS), plus this plugin's own codes in the `-100`…`-199` range. Branch on the exact code: ranges such as `2000`–`2999` no longer have
/// one single meaning. Codes that stop or pause zone fetching are reported
/// once, not on every GPS fix, and the zone already loaded keeps alerting.
abstract final class MapZoneErrorCode {
  /// Success — zone data loaded, or logged out.
  static const int success = 0;

  // ── Local (negative) ──────────────────────────────────────────────────────

  /// The server response could not be verified.
  static const int responseNotVerified = -1;

  /// Map data empty, malformed or unusable.
  static const int mapDataInvalid = -2;

  /// A secure session could not be established; the SDK retries.
  static const int secureSessionFailed = -3;

  /// Server unreachable — check connectivity.
  static const int serverUnreachable = -4;

  /// The native bridge failed (e.g. library missing for this device's ABI).
  /// Reported once per outage.
  static const int bridgeFailed = -5;

  /// Nobody is signed in: [MapZoneSpeedAlert.logout] was called, or
  /// `initialize` never was. Zone fetches stop until `initialize`.
  static const int notLoggedIn = -6;

  /// The device cannot be read yet (e.g. an iPhone not unlocked since
  /// restart), so no zone is fetched. The SDK re-reads it about once a minute;
  /// show a notice. `logout` also completes with this code then — call it
  /// again later.
  static const int deviceNotReady = -8;

  /// Legacy spelling of [bridgeFailed] from older engine builds.
  static const int bridgeFailedLegacy = -99;

  // ── Server ────────────────────────────────────────────────────────────────

  /// Sign-in: identity or vehicle rejected (stops until `initialize`).
  /// Zone: request rejected, e.g. location outside the served area.
  static const int invalidRequest = 1001;

  /// A required parameter is missing.
  static const int missingParameter = 1002;

  /// The device clock is wrong — fix the time.
  static const int deviceClockWrong = 2000;

  /// The request signature was not accepted.
  static const int invalidSignature = 2002;

  /// The API key is unknown or disabled.
  static const int apiKeyNotAccepted = 2003;

  /// The application id is not registered for the API key.
  static const int applicationIdNotAccepted = 2004;

  /// The service plan has expired.
  static const int planExpired = 2005;

  /// The identity is now in use on another device. Show a notice, call
  /// [MapZoneSpeedAlert.logout] and send the user back to sign in.
  static const int sessionMoved = 2006;

  /// The device or identity was locked by an administrator.
  static const int locked = 2007;

  /// The account on this device changed too recently; the SDK pauses for
  /// 20 minutes, then resumes on its own.
  static const int switchTooSoon = 2008;

  /// Too many new sessions for the API key; the SDK backs off.
  static const int tooManyNewSessions = 2009;

  /// Trial API key: the identity is not one of the key's sample identities.
  static const int trialIdentityNotAllowed = 2010;

  /// The vehicle type is not enabled for the API key.
  static const int vehicleTypeNotAllowed = 3003;

  /// Device limit of the API key reached (older servers).
  static const int enterprisePlanRequired = 3011;

  /// The API key cannot register more new devices.
  static const int newDeviceLimit = 3012;

  /// Too many requests; the SDK waits for the server's `Retry-After`.
  static const int tooManyRequests = 4000;

  /// The API key's request quota is used up.
  static const int requestQuotaExceeded = 4001;

  /// Server error; the SDK backs off.
  static const int internalError = 5000;

  /// The service is starting up; the SDK backs off.
  static const int serviceStarting = 5004;

  // ── Plugin (-100 … -199) ──────────────────────────────────────────────────
  // Reported by this plugin's native GPS capture (`start()`), never by the
  // native SDK, so they cannot clash with its codes.

  /// Native GPS capture cannot get a position: a location error on iOS, or on
  /// Android no location source left after `start()` succeeded.
  static const int locationUnavailable = -100;

  /// iOS only: native GPS capture lost location permission (denied or
  /// restricted). Capture stops; send the user to the system settings, then
  /// call `start()` again once permission is back.
  static const int locationPermissionDenied = -101;
}
