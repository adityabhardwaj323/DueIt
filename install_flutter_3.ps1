$ErrorActionPreference = 'Stop'

Write-Host "Fetching latest Flutter stable release info..."
$json = Invoke-RestMethod -Uri "https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json"
$latest = $json.releases | Where-Object { $_.channel -eq 'stable' } | Select-Object -First 1
$url = $json.base_url + "/" + $latest.archive
$dest = "C:\src\flutter_sdk.zip"

Write-Host "Creating C:\src directory..."
New-Item -ItemType Directory -Force -Path "C:\src" | Out-Null

Write-Host "Downloading Flutter from $url ..."
curl.exe -L $url -o $dest

Write-Host "Extracting Flutter SDK to C:\src ..."
Expand-Archive -Path $dest -DestinationPath "C:\src" -Force

Write-Host "Cleaning up zip file..."
Remove-Item $dest

Write-Host "Updating User PATH..."
$userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
if ($userPath -notlike "*C:\src\flutter\bin*") {
    $newPath = $userPath + ";C:\src\flutter\bin"
    [Environment]::SetEnvironmentVariable('PATH', $newPath, 'User')
    Write-Host "Added C:\src\flutter\bin to User PATH."
} else {
    Write-Host "C:\src\flutter\bin is already in User PATH."
}

Write-Host "Flutter installation script completed."
