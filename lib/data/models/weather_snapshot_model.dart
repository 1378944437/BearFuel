class WeatherSnapshotModel {
  final String cityKey;
  final String cityName;
  final String? province;
  final DateTime snapshotDate;
  final double? temperature;
  final double? tempHigh;
  final double? tempLow;
  final String? condition;
  final int? aqi;
  final String source;
  final DateTime fetchedAt;

  const WeatherSnapshotModel({
    required this.cityKey,
    required this.cityName,
    this.province,
    required this.snapshotDate,
    this.temperature,
    this.tempHigh,
    this.tempLow,
    this.condition,
    this.aqi,
    required this.source,
    required this.fetchedAt,
  });

  double? get averageTemperature {
    // 有实况温度时优先使用当日记录；历史接口没有实况字段时再用高低温均值。
    if (temperature != null) {
      return temperature;
    }
    if (tempHigh != null && tempLow != null) {
      return (tempHigh! + tempLow!) / 2;
    }
    return null;
  }

  String get dateKey => snapshotDate.toIso8601String().substring(0, 10);

  Map<String, dynamic> toMap() => {
        'id': '$cityKey|$dateKey',
        'city_key': cityKey,
        'city_name': cityName,
        'province': province,
        'snapshot_date': dateKey,
        'temperature': temperature,
        'temp_high': tempHigh,
        'temp_low': tempLow,
        'condition': condition,
        'aqi': aqi,
        'source': source,
        'fetched_at': fetchedAt.toIso8601String(),
      };

  factory WeatherSnapshotModel.fromMap(Map<String, dynamic> map) {
    double? number(dynamic value) =>
        value is num ? value.toDouble() : double.tryParse('$value');
    final date = DateTime.tryParse('${map['snapshot_date'] ?? ''}') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    return WeatherSnapshotModel(
      cityKey: map['city_key'] as String? ?? '',
      cityName: map['city_name'] as String? ?? '',
      province: map['province'] as String?,
      snapshotDate: date,
      temperature: number(map['temperature']),
      tempHigh: number(map['temp_high']),
      tempLow: number(map['temp_low']),
      condition: map['condition'] as String?,
      aqi: map['aqi'] as int?,
      source: map['source'] as String? ?? 'apizero-moji-weather',
      fetchedAt: DateTime.tryParse('${map['fetched_at'] ?? ''}') ?? date,
    );
  }
}
