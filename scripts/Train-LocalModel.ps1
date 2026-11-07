param(
    [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{40}$')][string]$Revision,
    [ValidateRange(1,1000)][int]$MaxSteps=100,
    [switch]$QLoRA
)
$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
Push-Location $project
try {
    # Manual only: refresh withdrawals, rebuild from approved examples, then
    # explicitly start a bounded GPU experiment. No scheduled task invokes this.
    & "$PSScriptRoot/Export-Contributions.ps1"
    if ($LASTEXITCODE -ne 0) { throw 'Pull/deletion processing failed; training was not started.' }
    & node (Join-Path $project 'cloud/tools/dataset.mjs')
    if ($LASTEXITCODE -ne 0) { throw 'Reviewed dataset validation failed; training was not started.' }
    $data = if ($env:LINQO_DATA_DIRECTORY) { $env:LINQO_DATA_DIRECTORY } else { Join-Path $project '.private/linqo-training' }
    $options = if ($QLoRA) { @('--qlora') } else { @() }
    & python (Join-Path $project 'tools/training/train.py') --data $data --train --revision $Revision --max-steps $MaxSteps @options
    if ($LASTEXITCODE -ne 0) { throw 'Local training did not complete. No model was published.' }
} finally { Pop-Location }
