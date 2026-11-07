$ErrorActionPreference = 'Stop'
$project = (Resolve-Path (Split-Path $PSScriptRoot -Parent)).Path
$private = Join-Path $project '.private'
if (-not (Test-Path -LiteralPath $private)) { New-Item -ItemType Directory -Path $private | Out-Null }
$target = Get-Item -LiteralPath $private
if ($target.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Private data path must be a real workspace directory, not a link.' }
if (-not $target.FullName.StartsWith($project + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Private data path escaped the project.' }
$acl = [System.Security.AccessControl.DirectorySecurity]::new()
$acl.SetAccessRuleProtection($true, $false)
$owner = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
$acl.SetOwner($owner)
$inherit = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
foreach ($sid in @($owner, [System.Security.Principal.SecurityIdentifier]::new('S-1-5-18'))) {
    $rule = [System.Security.AccessControl.FileSystemAccessRule]::new($sid, [System.Security.AccessControl.FileSystemRights]::FullControl, $inherit, [System.Security.AccessControl.PropagationFlags]::None, [System.Security.AccessControl.AccessControlType]::Allow)
    $acl.AddAccessRule($rule)
}
Set-Acl -LiteralPath $target.FullName -AclObject $acl
Write-Output 'Private keys and datasets are restricted to this Windows user and SYSTEM. Keep encrypted external backups separately.'
