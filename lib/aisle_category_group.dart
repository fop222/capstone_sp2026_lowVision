/// Bucket for items with no real category (empty, [Other], etc.).
const String categoryOtherBucketKey = '__other__';

/// Case-insensitive category key so e.g. [Drinks] and [drinks] group together.
/// Trims and collapses internal whitespace. [Other] and empty do not group-expand.
String categoryGroupKeyForMatching(String category) {
  final c =
      category.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  if (c.isEmpty || c == 'other') return '';
  return c;
}

/// Map key for grouping items in UI and aisle logic (never empty).
String categoryBucketKeyFromRaw(String category) {
  final k = categoryGroupKeyForMatching(category);
  return k.isEmpty ? categoryOtherBucketKey : k;
}

/// Section heading: [bucketKey] is lowercase canonical or [categoryOtherBucketKey].
String displayCategorySectionTitle(String bucketKey) {
  if (bucketKey.isEmpty || bucketKey == categoryOtherBucketKey) {
    return 'Other';
  }
  return bucketKey
      .split(' ')
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

/// Reads [category] from Supabase/JSON maps (String or other); never throws.
String categoryFromItemMap(Map<String, dynamic> m) {
  final raw = m['category'];
  final s0 = raw is String
      ? raw
      : raw == null
          ? ''
          : raw.toString();
  final trimmed = s0.trim();
  return trimmed.isEmpty ? 'Other' : trimmed;
}
