param([Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_-]{0,70}$')][string]$Milestone)
$ErrorActionPreference = 'Stop'
$project = (Resolve-Path (Split-Path $PSScriptRoot -Parent)).Path
$projectsRoot = Split-Path $project -Parent
$backupRoot = Join-Path $projectsRoot 'Linqo Backups'
if (-not (Test-Path -LiteralPath $backupRoot)) { New-Item -ItemType Directory -Path $backupRoot | Out-Null }
$target = Get-Item -LiteralPath $backupRoot
if (($target.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $target.Parent.FullName -ne $projectsRoot) {
    throw 'Backup destination must be the real Linqo Backups directory beside the project.'
}
$acl = [System.Security.AccessControl.DirectorySecurity]::new()
$acl.SetAccessRuleProtection($true, $false)
$owner = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
$acl.SetOwner($owner)
$inherit = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
foreach ($sid in @($owner, [System.Security.Principal.SecurityIdentifier]::new('S-1-5-18'))) {
    $acl.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new($sid, 'FullControl', $inherit, 'None', 'Allow'))
}
$current = Get-Acl -LiteralPath $target.FullName
$rules = @($current.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]))
$expectedSids = @($owner.Value, 'S-1-5-18')
$privateAlready = $current.AreAccessRulesProtected -and $current.GetOwner([System.Security.Principal.SecurityIdentifier]).Value -eq $owner.Value -and $rules.Count -eq 2
foreach ($rule in $rules) {
    if ($rule.IdentityReference.Value -notin $expectedSids -or $rule.AccessControlType -ne 'Allow' -or $rule.FileSystemRights -ne 'FullControl' -or $rule.InheritanceFlags -ne $inherit -or $rule.PropagationFlags -ne 'None') { $privateAlready = $false }
}
if (-not $privateAlready) {
    [System.IO.FileSystemAclExtensions]::SetAccessControl($target, $acl)
}
& python (Join-Path $project 'tools/project_backup.py') --project $project --milestone $Milestone
exit $LASTEXITCODE
