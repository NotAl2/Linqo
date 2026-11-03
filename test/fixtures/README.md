# Local TLS test fixtures

The localhost certificate and private key in this directory are intentionally public, self-signed test data. They are used only by the loopback HTTPS preview tests with an explicit test SecurityContext. They are not credentials, Android signing keys or production TLS material, and must never be reused for a live service.

They are not declared as Flutter assets and are not packaged in the release APK.
