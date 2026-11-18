import 'map_zone_error_code.dart';

/// Outcome reported by the native engine: each zone load and sign-in on the
/// `onResult` stream, and the result of `MapZoneSpeedAlert.logout`.
///
/// Branch on [errorCode] (see [MapZoneErrorCode]); [errorMessage] is a short
/// English sentence derived from the code alone, meant for logs and fallback
/// UI. Whatever the code, a zone already loaded keeps alerting.
class AlertResult {
  const AlertResult({
    required this.success,
    required this.errorCode,
    this.errorMessage,
  });

  final bool success;
  final int errorCode;
  final String? errorMessage;

  /// No error.
  static const int codeSuccess = MapZoneErrorCode.success;

  /// Vehicle type not enabled for the API key.
  static const int codeUnsupportedVehicleType =
      MapZoneErrorCode.vehicleTypeNotAllowed;

  bool get isUnsupportedVehicleType => errorCode == codeUnsupportedVehicleType;

  factory AlertResult.fromJson(Map<String, dynamic> json) {
    return AlertResult(
      success: json['success'] as bool? ?? false,
      errorCode: (json['errorCode'] as num?)?.toInt() ?? 0,
      errorMessage: json['errorMessage'] as String?,
    );
  }

  @override
  String toString() =>
      'AlertResult(success: $success, code: $errorCode, message: $errorMessage)';
}
