/// School years start on June 1. Stored historical spelling is never rewritten.
class SchoolYear {
  static String current({DateTime? date}) {
    final today = date ?? DateTime.now();
    final start = today.month >= 6 ? today.year : today.year - 1;
    return '$start–${start + 1}';
  }

  static String normalize(Object? value) =>
      (value?.toString() ?? '').trim().replaceAll(RegExp(r'\s*[-–]\s*'), '-');

  static List<String> options({DateTime? date, String? stored}) {
    final start = int.parse(current(date: date).substring(0, 4));
    final years = List.generate(5, (i) => '${start - i}–${start - i + 1}');
    if (stored != null && !years.contains(stored)) {
      final equivalent =
          years.indexWhere((year) => normalize(year) == normalize(stored));
      if (equivalent >= 0) {
        years[equivalent] = stored;
      } else {
        years.add(stored);
      }
    }
    return years;
  }
}

String normalizedSchoolName(Object? value) => (value?.toString() ?? '')
    .trim()
    .replaceAll(RegExp(r'\s+'), ' ')
    .toLowerCase();

String normalizedGrade(Object? value) => (value?.toString() ?? '')
    .trim()
    .replaceFirst(RegExp(r'^grade\s*', caseSensitive: false), '')
    .toUpperCase();
