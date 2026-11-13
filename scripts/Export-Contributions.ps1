param([switch]$RegisterWeekly, [switch]$Scheduled)
$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
$script = Join-Path $project 'cloud/tools/export.mjs'
if ($RegisterWeekly) {
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -NonInteractive -WindowStyle Hidden -File "{0}" -Scheduled' -f $PSCommandPath) -WorkingDirectory $project
    $weekly = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At '10:00'
    $login = New-ScheduledTaskTrigger -AtLogOn -User ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -RunOnlyIfNetworkAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 20)
    $principal = New-ScheduledTaskPrincipal -UserId ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName 'Linqo private contribution export' -Action $action -Trigger @($weekly, $login) -Settings $settings -Principal $principal -Description 'Pull consented Linqo examples and deletion requests; never starts model training.' -Force | Out-Null
    Write-Output 'Weekly local export registered for Sunday 10:00 in this laptop time zone. Missed runs start when the user is logged in and network is available.'
    exit
}
if ($Scheduled) {
    $dataDirectory = if ($env:LINQO_DATA_DIRECTORY) { $env:LINQO_DATA_DIRECTORY } else { Join-Path $project '.private/linqo-training' }
    $checkpoint = Join-Path $dataDirectory 'checkpoint.json'
    if (Test-Path -LiteralPath $checkpoint) {
        $state = Get-Content -LiteralPath $checkpoint -Raw | ConvertFrom-Json
        $now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        # Six days leaves room for last week's export to have finished after its trigger time.
        if ($now -ge $state.last_success -and ($now - $state.last_success) -lt 518400000) { exit }
    }
}
Push-Location $project
try {
    # Wrangler uses its protected per-user OAuth credentials. Never pass tokens in
    # scheduled-task arguments. Authenticate once with npx wrangler login in cloud/.
    & node $script
    if ($LASTEXITCODE -ne 0) { throw 'Private export failed; checkpoint was preserved. Check Cloudflare authentication and retry.' }
} finally { Pop-Location }
