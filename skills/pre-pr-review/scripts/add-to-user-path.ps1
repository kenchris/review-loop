# Adds a folder to the current user's PATH (the Windows user environment), once. Used by install.sh --add-to-path on Windows.
#   powershell -NoProfile -File add-to-user-path.ps1 -Dir C:\Users\you\.local\bin
param([Parameter(Mandatory = $true)][string]$Dir)
$current = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($null -eq $current) { $current = '' }
$entries = $current -split ';' | Where-Object { $_ -ne '' }
if ($entries -contains $Dir) {
    Write-Host "already on your user PATH: $Dir"
} else {
    [Environment]::SetEnvironmentVariable('Path', (($entries + $Dir) -join ';'), 'User')
    Write-Host "added to your user PATH: $Dir"
}
