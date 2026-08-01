import 'dart:typed_data';

class PlatformPlayerIdentity {
  const PlatformPlayerIdentity({
    required this.platform,
    required this.platformPlayerId,
    required this.displayName,
    required this.authenticated,
    required this.lastUpdatedAt,
    this.localAvatarBytes,
    this.avatarUrl,
  });

  final String platform;
  final String platformPlayerId;
  final String displayName;
  final bool authenticated;
  final DateTime lastUpdatedAt;
  final Uint8List? localAvatarBytes;
  final String? avatarUrl;

  bool get hasAvatar =>
      (localAvatarBytes?.isNotEmpty ?? false) ||
      (avatarUrl?.trim().isNotEmpty ?? false);
}
