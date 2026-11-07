param([Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_-]{0,70}$')][string]$Milestone)
$ErrorActionPreference = 'Stop'
$project = (Resolve-Path (Split-Path $PSScriptRoot -Parent)).Path
$backupRoot = Join-Path $project '.project-backups'
if (-not (Test-Path -LiteralPath $backupRoot)) { New-Item -ItemType Directory -Path $backupRoot | Out-Null }
$target = Get-Item -LiteralPath $backupRoot
if (($target.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $target.Parent.FullName -ne $project) {
    throw 'Backup destination must be a real directory directly inside the workspace.'
}
$acl = [System.Security.AccessControl.DirectorySecurity]::new()
$acl.SetAccessRuleProtection($true, $false)
$owner = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
$acl.SetOwner($owner)
$inherit = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
foreach ($sid in @($owner, [System.Security.Principal.SecurityIdentifier]::new('S-1-5-18'))) {
    $acl.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new($sid, 'FullControl', $inherit, 'None', 'Allow'))
}
Set-Acl -LiteralPath $target.FullName -AclObject $acl
& python (Join-Path $project 'tools/project_backup.py') --project $project --milestone $Milestone
exit $LASTEXITCODE
