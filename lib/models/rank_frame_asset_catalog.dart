/// Canonical asset mapping for every visible ranked division.
///
/// `assets/frames/` is the sole visual source for rank frames. Keep the public
/// rank keys stable even when an asset filename differs (Bronze III currently
/// ships as `bronz_3.png`).
class RankFrameAssetCatalog {
  RankFrameAssetCatalog._();

  static const String fallbackKey = 'bronze_3';

  static const Map<String, String> _assetPaths = <String, String>{
    'bronze_3': 'assets/frames/bronz_3.png',
    'bronze_2': 'assets/frames/bronze_2.png',
    'bronze_1': 'assets/frames/bronze_1.png',
    'silver_3': 'assets/frames/silver_3.png',
    'silver_2': 'assets/frames/silver_2.png',
    'silver_1': 'assets/frames/silver_1.png',
    'gold_3': 'assets/frames/gold_3.png',
    'gold_2': 'assets/frames/gold_2.png',
    'gold_1': 'assets/frames/gold_1.png',
    'platinum_3': 'assets/frames/platinum_3.png',
    'platinum_2': 'assets/frames/platinum_2.png',
    'platinum_1': 'assets/frames/platinum_1.png',
    'master_3': 'assets/frames/master_3.png',
    'master_2': 'assets/frames/master_2.png',
    'master_1': 'assets/frames/master_1.png',
  };

  static List<String> get keys =>
      List<String>.unmodifiable(_assetPaths.keys);

  static List<String> get assetPaths =>
      List<String>.unmodifiable(_assetPaths.values);

  static bool contains(String? key) =>
      key != null && _assetPaths.containsKey(key.trim().toLowerCase());

  static String normalizeKey(String? key) {
    final normalized = key?.trim().toLowerCase();
    return normalized != null && _assetPaths.containsKey(normalized)
        ? normalized
        : fallbackKey;
  }

  static String assetPathForKey(String? key) =>
      _assetPaths[normalizeKey(key)]!;
}
