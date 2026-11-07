enum AppTier { free, xl, xxl }

class LibraryLimits {
  const LibraryLimits(this.tier, {required this.enforced});
  final AppTier tier;
  final bool enforced;
  int? get saves => !enforced || tier == AppTier.xxl
      ? null
      : tier == AppTier.xl
      ? 150
      : 50;
  int? get collections => !enforced || tier == AppTier.xxl
      ? null
      : tier == AppTier.xl
      ? 30
      : 5;
  bool get customModels => !enforced || tier == AppTier.xxl;
}

class TierLimitException implements Exception {
  const TierLimitException(this.message);
  final String message;
  @override
  String toString() => message;
}
