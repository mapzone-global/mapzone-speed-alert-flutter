/// Emitted by the native `onResult` callback to report success / errors of the
/// alert engine (zone loading, credential validation, etc.).
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
  static const int codeSuccess = 0;

  /// Invalid parameter passed to the engine.
  static const int codeInvalidParameter = 1001;

  /// API key expired / rejected.
  static const int codeExpiredApiKey = 2003;

  /// Vehicle type not supported for speed alerts.
  static const int codeUnsupportedVehicleType = 3003;

  bool get isExpiredApiKey => errorCode == codeExpiredApiKey;
  bool get isUnsupportedVehicleType => errorCode == codeUnsupportedVehicleType;

  /// Network / parsing errors are reported with negative codes.
  bool get isNetworkError => errorCode < 0;

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
