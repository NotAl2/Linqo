param([ValidateRange(5554, 5584)][int]$Port = 5554)
$ErrorActionPreference = 'Stop'
& "$PSScriptRoot/start-ui-emulator.ps1" -Port $Port
Write-Host 'Flutter UI session: r = hot reload, R = hot restart, q = stop app session.'
& "$PSScriptRoot/flutter.ps1" run --debug -d "emulator-$Port" --target=lib/main.dart
exit $LASTEXITCODE
