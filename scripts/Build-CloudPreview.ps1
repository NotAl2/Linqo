param([Parameter(Mandatory=$true)][string]$ConfigFile, [switch]$Qa)
$ErrorActionPreference = 'Stop'
$configPath = (Resolve-Path -LiteralPath $ConfigFile).Path
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$allowed = @('LINQO_FIREBASE_PROJECT_ID','LINQO_FIREBASE_API_KEY','LINQO_FIREBASE_APP_ID','LINQO_FIREBASE_SENDER_ID','LINQO_GOOGLE_WEB_CLIENT_ID','LINQO_CLOUD_URL','LINQO_ENTITLEMENT_PUBLIC_KEY','LINQO_PAID_LIMITS_ENABLED','LINQO_CHECKOUT_ENABLED','LINQO_POLAR_SANDBOX')
foreach ($entry in $config.PSObject.Properties) {
    if ($entry.Name -notin $allowed) { throw ('Unexpected client configuration field: {0}. Never embed payment/provider secrets in an APK.' -f $entry.Name) }
}
if ([string]$config.LINQO_CHECKOUT_ENABLED -eq 'true') {
    throw 'This prebuild keeps payments disabled. Checkout requires a separately qualified paid-release build.'
}
if (-not $Qa -and [string]$config.LINQO_PAID_LIMITS_ENABLED -eq 'false') {
    throw 'The public prebuild enforces tier limits. Unlimited development configurations require the separate QA identity.'
}
if (([string]$config.LINQO_POLAR_SANDBOX -eq 'true') -and -not $Qa) { throw 'Polar sandbox controls require the separate QA identity.' }
$buildArgs = @('build','apk','--release','--target-platform','android-arm64',"--dart-define-from-file=$configPath")
if ($Qa) { $buildArgs += '--android-project-arg=linqoQa=true' }
& "$PSScriptRoot/flutter.ps1" @buildArgs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
if ($Qa) {
    $projectRoot = Split-Path $PSScriptRoot -Parent
    $aapt = Get-ChildItem -LiteralPath "$projectRoot/.tools/android-sdk/build-tools" -Filter aapt.exe -Recurse | Sort-Object FullName -Descending | Select-Object -First 1
    if (-not $aapt) { throw 'QA package verification requires aapt. Do not install the APK.' }
    $badging = & $aapt.FullName dump badging "$projectRoot/build/app/outputs/flutter-apk/app-release.apk"
    if ($LASTEXITCODE -ne 0 -or ($badging -join "`n") -notmatch "(?m)^package: name='dev\.linqo\.linqo\.qa' " -or ($badging -join "`n") -notmatch "(?m)^application-label:'Linqo QA'") {
        throw 'QA APK identity verification failed. Do not install the APK.'
    }
}
exit 0
