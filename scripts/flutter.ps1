param([Parameter(ValueFromRemainingArguments = $true)][string[]]$FlutterArgs)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$localSdk = Join-Path $projectRoot '.tools/flutter'
if (Test-Path "$localSdk/bin/flutter.bat") {
    # Native build hooks can fail with spaces in the SDK path. Use its short alias.
    $shortRoot = (& cmd /c "for %I in (`"$projectRoot`") do @echo %~sI").Trim()
    $env:PUB_CACHE = Join-Path $shortRoot '.tools/pub-cache'
    $env:FLUTTER_ROOT = Join-Path $shortRoot '.tools/flutter'
    $javaRoot = Join-Path $projectRoot '.tools/java'
    if (Test-Path $javaRoot) {
        $localJava = Get-ChildItem -LiteralPath $javaRoot -Directory | Select-Object -First 1
        if ($localJava) { $env:JAVA_HOME = $localJava.FullName }
    }
    if (Test-Path "$projectRoot/.tools/android-sdk") {
        $env:ANDROID_HOME = Join-Path $shortRoot '.tools/android-sdk'
        $env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
    }
    $env:GRADLE_USER_HOME = Join-Path $shortRoot '.tools/gradle-cache'
    & "$env:FLUTTER_ROOT/bin/flutter.bat" @FlutterArgs
} else {
    & flutter @FlutterArgs
}
exit $LASTEXITCODE
