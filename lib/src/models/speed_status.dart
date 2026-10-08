/// Driver speed compliance status reported with each [AlertEvent].
enum SpeedStatus {
  /// Driving at or below the current speed limit.
  compliant(0),

  /// Approaching / close to the speed limit (warning zone).
  approaching(1),

  /// Exceeding the current speed limit.
  exceeding(2);

  const SpeedStatus(this.value);

  final int value;

  static SpeedStatus fromValue(int? value) {
    switch (value) {
      case 1:
        return SpeedStatus.approaching;
      case 2:
        return SpeedStatus.exceeding;
      default:
        return SpeedStatus.compliant;
    }
  }
}
