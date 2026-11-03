param(
    [ValidateRange(5554, 5584)][int]$Port = 5554,
    [switch]$ColdBoot
)
$ErrorActionPreference = 'Stop'
if ($Port % 2) { throw 'Choose an even emulator port.' }
$projectRoot = Split-Path $PSScriptRoot -Parent
# Some emulator subprocesses mishandle spaces in SDK/AVD paths on Windows.
$shortRoot = (& cmd /c "for %I in (`"$projectRoot`") do @echo %~sI").Trim()
$env:ANDROID_HOME = Join-Path $shortRoot '.tools/android-sdk'
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
$env:ANDROID_AVD_HOME = Join-Path $shortRoot '.tools/avd'
$env:ANDROID_EMULATOR_HOME = Join-Path $shortRoot '.tools/emulator-home'
$adb = Join-Path $env:ANDROID_HOME 'platform-tools/adb.exe'
$emulator = Join-Path $env:ANDROID_HOME 'emulator/emulator.exe'
$avdName = 'Linqo_UI'
$serial = "emulator-$Port"
if (!(Test-Path -LiteralPath $emulator) -or !(Test-Path -LiteralPath "$env:ANDROID_AVD_HOME/$avdName.ini")) {
    throw 'The local Linqo_UI emulator is not installed. See docs/UI_EMULATOR.md.'
}
$devices = & $adb devices
$running = $devices | Where-Object { $_ -match "^$serial\s+device$" }
if ($running) {
    $runningName = & $adb -s $serial emu avd name
    if ($runningName -notcontains $avdName) { throw "$serial belongs to another AVD. Choose another even -Port." }
    Write-Host "Linqo UI emulator is ready: $serial"
    return
}
if ($devices | Where-Object { $_ -match "^$serial\s" }) {
    throw "$serial is still starting or offline. Wait for it, or choose another even -Port."
}
$check = & $emulator -accel-check 2>&1
if ($LASTEXITCODE -ne 0) { throw "Hardware acceleration is unavailable: $check" }
$launchArgs = @('-avd', $avdName, '-port', "$Port", '-memory', '2048', '-cores', '4', '-gpu', 'auto', '-no-boot-anim', '-netdelay', 'none', '-netspeed', 'full')
if ($ColdBoot) { $launchArgs += '-no-snapshot-load' }
$emulatorProcess = Start-Process -FilePath $emulator -ArgumentList $launchArgs -WindowStyle Normal -PassThru -RedirectStandardOutput "$projectRoot/.tools/ui-emulator.log" -RedirectStandardError "$projectRoot/.tools/ui-emulator-error.log"
Write-Host 'Starting the Linqo Android UI device (2 GB RAM, no AI model)...'
$bootWatch = [Diagnostics.Stopwatch]::StartNew()
while ($bootWatch.Elapsed.TotalSeconds -lt 240) {
    $booted = & $adb -s $serial shell getprop sys.boot_completed 2>$null
    if ($booted -contains '1') {
        & $adb -s $serial shell input keyevent KEYCODE_WAKEUP
        & $adb -s $serial shell wm dismiss-keyguard
        Write-Host "Linqo UI emulator is ready: $serial"
        return
    }
    if ($emulatorProcess.HasExited) { throw 'Emulator exited. Check .tools/ui-emulator-error.log and .tools/ui-emulator.log.' }
    Start-Sleep -Seconds 2
}
throw 'Emulator boot timed out. Check .tools/ui-emulator.log, or try -ColdBoot.'
