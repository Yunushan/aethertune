import 'package:aethertune/src/ui/library_stats_sections.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats playback history timestamps for display', () {
    expect(formatLibraryHistoryTime(null), '');
    expect(
      formatLibraryHistoryTime(DateTime(2025, 1, 2, 3, 4)),
      '2025-01-02 03:04',
    );
    expect(
      formatLibraryHistoryTime(DateTime(2025, 12, 31, 23, 59)),
      '2025-12-31 23:59',
    );
  });
}
