param(
    [Parameter(Mandatory=$true)][string]$GoogleServicesFile,
    [string]$ExpectedProject='linqo-app-notal2',
    [string]$Backend='https://linqo-cloud.aryandurgude123.workers.dev'
)
$ErrorActionPreference = 'Stop'
$backendUri = $null
if (-not [Uri]::TryCreate($Backend, [UriKind]::Absolute, [ref]$backendUri) -or $backendUri.Scheme -ne 'https' -or $backendUri.UserInfo -or $backendUri.Query -or $backendUri.Fragment) { throw 'Cloud backend must be an HTTPS URL without credentials, query or fragment.' }
$project = Split-Path $PSScriptRoot -Parent
$sdkPath = (Resolve-Path -LiteralPath $GoogleServicesFile).Path
$sdk = Get-Content -LiteralPath $sdkPath -Raw | ConvertFrom-Json
if ($sdk.project_info.project_id -ne $ExpectedProject) { throw 'Firebase file belongs to a different project. No configuration was written.' }
$clients = @($sdk.client | Where-Object { $_.client_info.android_client_info.package_name -eq 'dev.linqo.linqo' })
if ($clients.Count -ne 1) { throw 'Expected exactly one Firebase Android client for dev.linqo.linqo.' }
$client = $clients[0]
$webClients = @($client.oauth_client | Where-Object { $_.client_type -eq 3 })
if ($webClients.Count -ne 1) { throw 'Enable Google sign-in in Firebase and download a fresh google-services.json with a Web OAuth client.' }
$apiKeys = @($client.api_key | Where-Object { $_.current_key })
if ($apiKeys.Count -ne 1) { throw 'Expected one Firebase client API key.' }
$appId = [string]$client.client_info.mobilesdk_app_id
$sender = [string]$sdk.project_info.project_number
if (-not $appId.StartsWith("1:${sender}:android:")) { throw 'Firebase app and project number disagree.' }
$webClient = [string]$webClients[0].client_id
if ($webClient -notmatch '^\d+-[A-Za-z0-9_-]+\.apps\.googleusercontent\.com$') { throw 'Invalid Web OAuth client ID.' }
$keyPath = Join-Path $project '.private/linqo-cloud/public-key.txt'
$publicKey = (Get-Content -LiteralPath $keyPath -Raw).Trim()
if ($publicKey -notmatch '^[A-Za-z0-9_-]{43}$') { throw 'Invalid entitlement public key.' }
$destination = Join-Path $project '.private/linqo-cloud/flutter-config.json'
$config = [ordered]@{
    LINQO_FIREBASE_PROJECT_ID=$ExpectedProject
    LINQO_FIREBASE_API_KEY=[string]$apiKeys[0].current_key
    LINQO_FIREBASE_APP_ID=$appId
    LINQO_FIREBASE_SENDER_ID=$sender
    LINQO_GOOGLE_WEB_CLIENT_ID=$webClient
    LINQO_CLOUD_URL=$Backend
    LINQO_ENTITLEMENT_PUBLIC_KEY=$publicKey
    LINQO_PAID_LIMITS_ENABLED=$false
    LINQO_CHECKOUT_ENABLED=$false
}
[IO.File]::WriteAllText(($destination + '.tmp'), ($config | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath ($destination + '.tmp') -Destination $destination -Force
$savedSdk = Join-Path $project '.private/linqo-cloud/google-services.json'
if (-not $sdkPath.Equals($savedSdk, [StringComparison]::OrdinalIgnoreCase)) { [IO.File]::Copy($sdkPath, $savedSdk, $true) }
Write-Output "Firebase client configured for $ExpectedProject / dev.linqo.linqo. Checkout and paid limits remain off. No secret or client-key values printed."
