class CloudConfig {
  static const projectId = String.fromEnvironment('LINQO_FIREBASE_PROJECT_ID');
  static const apiKey = String.fromEnvironment('LINQO_FIREBASE_API_KEY');
  static const appId = String.fromEnvironment('LINQO_FIREBASE_APP_ID');
  static const senderId = String.fromEnvironment('LINQO_FIREBASE_SENDER_ID');
  static const googleClientId = String.fromEnvironment(
    'LINQO_GOOGLE_WEB_CLIENT_ID',
  );
  static const backend = String.fromEnvironment('LINQO_CLOUD_URL');
  static const entitlementKey = String.fromEnvironment(
    'LINQO_ENTITLEMENT_PUBLIC_KEY',
  );
  // Turn on only for a build that passed real payment/restore/refund acceptance.
  static const paidLimits = bool.fromEnvironment('LINQO_PAID_LIMITS_ENABLED');
  static const checkout = bool.fromEnvironment('LINQO_CHECKOUT_ENABLED');
  // Enable only after Google-data provenance and consent review. Rejecting an
  // upload on the server alone does not prevent source text leaving the phone.
  static const contributionsEnabled = false;
  static bool get identityReady => [
    projectId,
    apiKey,
    appId,
    senderId,
    googleClientId,
  ].every((s) => s.isNotEmpty);
  static bool get backendReady {
    final uri = Uri.tryParse(backend);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        uri.query.isEmpty &&
        uri.fragment.isEmpty;
  }

  static bool get limitsEnabled =>
      paidLimits && identityReady && backendReady && entitlementKey.isNotEmpty;
  static bool get checkoutEnabled =>
      checkout && identityReady && backendReady && entitlementKey.isNotEmpty;
}
