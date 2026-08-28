enum HistoryGranularity { day, week, month, quarter }

class HistoricalDataWindow {
  final DateTime? startDate;
  final DateTime? endDate;
  final int pointCount;
  final HistoryGranularity granularity;

  const HistoricalDataWindow({
    required this.startDate,
    required this.endDate,
    required this.pointCount,
    required this.granularity,
  });

  bool get isEmpty => pointCount == 0;

  String get granularityLabel {
    switch (granularity) {
      case HistoryGranularity.day:
        return '按日';
      case HistoryGranularity.week:
        return '按周';
      case HistoryGranularity.month:
        return '按月';
      case HistoryGranularity.quarter:
        return '按季度';
    }
  }

  String get coverageLabel {
    if (startDate == null || endDate == null) return '暂无历史覆盖';
    String date(DateTime value) =>
        '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
    return '${date(startDate!)} 至 ${date(endDate!)} · $pointCount 条 · $granularityLabel';
  }

  static HistoricalDataWindow fromDates(Iterable<DateTime> dates) {
    final normalized = dates
        .map((date) => DateTime(date.year, date.month, date.day))
        .toList()
      ..sort();
    if (normalized.isEmpty) {
      return const HistoricalDataWindow(
        startDate: null,
        endDate: null,
        pointCount: 0,
        granularity: HistoryGranularity.day,
      );
    }

    final spanDays = normalized.last.difference(normalized.first).inDays;
    final granularity = normalized.length <= 30 && spanDays <= 90
        ? HistoryGranularity.day
        : normalized.length <= 180 && spanDays <= 730
            ? HistoryGranularity.week
            : spanDays <= 1095
                ? HistoryGranularity.month
                : HistoryGranularity.quarter;
    return HistoricalDataWindow(
      startDate: normalized.first,
      endDate: normalized.last,
      pointCount: normalized.length,
      granularity: granularity,
    );
  }

  static List<String> weatherMonthKeysToFetch({
    required DateTime now,
    required Iterable<DateTime> referenceDates,
    required Iterable<DateTime> existingDates,
    int maxHistoryDays = 40,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    final earliestAllowed = today.subtract(Duration(days: maxHistoryDays));
    final existing = existingDates
        .map((date) => DateTime(date.year, date.month, date.day))
        .where(
            (date) => !date.isBefore(earliestAllowed) && !date.isAfter(today))
        .toSet();
    final recentReferences = referenceDates
        .map((date) => DateTime(date.year, date.month, date.day))
        .where(
            (date) => !date.isBefore(earliestAllowed) && !date.isAfter(today))
        .toList();

    final keys = <String>{_monthKey(today)};
    // Initial or sparse data needs the previous month to fill the API's
    // limited historical window. Once enough recent snapshots exist, only
    // refresh the current month.
    if (existing.length < 30 ||
        recentReferences.any((date) {
          return date.year != today.year || date.month != today.month;
        })) {
      keys.add(_monthKey(DateTime(today.year, today.month - 1, 1)));
    }
    return keys.toList()..sort();
  }

  static String _monthKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}${date.month.toString().padLeft(2, '0')}';
}
