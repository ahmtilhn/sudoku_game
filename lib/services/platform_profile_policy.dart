enum PlatformProfileNameDecision { preserveCustom, adoptPlatform, keepCurrent }

class PlatformProfilePolicy {
  const PlatformProfilePolicy._();

  static PlatformProfileNameDecision decideNameUpdate({
    required bool profileConfirmed,
    required String currentNameSource,
    required String currentDisplayName,
    required String platformDisplayName,
  }) {
    final platformName = platformDisplayName.trim();
    if (profileConfirmed && currentNameSource == 'custom') {
      return PlatformProfileNameDecision.preserveCustom;
    }
    if (platformName.isEmpty ||
        platformName == currentDisplayName.trim()) {
      return PlatformProfileNameDecision.keepCurrent;
    }
    return PlatformProfileNameDecision.adoptPlatform;
  }

  static String? normalizedAvatarUrl(String? avatarUrl) {
    final value = avatarUrl?.trim();
    if (value == null || value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    return uri.toString();
  }
}
