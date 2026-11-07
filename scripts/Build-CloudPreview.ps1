param([Parameter(Mandatory=$true)][string]$ConfigFile)
$ErrorActionPreference = 'Stop'
$configPath = (Resolve-Path -LiteralPath $ConfigFile).Path
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$allowed = @('LINQO_FIREBASE_PROJECT_ID','LINQO_FIREBASE_API_KEY','LINQO_FIREBASE_APP_ID','LINQO_FIREBASE_SENDER_ID','LINQO_GOOGLE_WEB_CLIENT_ID','LINQO_CLOUD_URL','LINQO_ENTITLEMENT_PUBLIC_KEY','LINQO_PAID_LIMITS_ENABLED','LINQO_CHECKOUT_ENABLED')
foreach ($entry in $config.PSObject.Properties) {
    if ($entry.Name -notin $allowed) { throw ('Unexpected client configuration field: {0}. Never embed payment/provider secrets in an APK.' -f $entry.Name) }
}
if ($config.LINQO_PAID_LIMITS_ENABLED -eq $true -or $config.LINQO_PAID_LIMITS_ENABLED -eq 'true') {
    throw 'This preview builder keeps paid limits off. Activate only through a separately verified stable-release build.'
}
& "$PSScriptRoot/flutter.ps1" build apk --release --target-platform android-arm64 --dart-define-from-file=$configPath
exit $LASTEXITCODE
