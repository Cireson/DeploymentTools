Param(
    [string]$deploymentScriptFileName,
    [string]$powershellDirectoryName
)

Get-ChildItem Env:

Write-Host "************************************************************************" -ForegroundColor Green
Write-Host "Environment Variables Written" -ForegroundColor Green
Write-Host "************************************************************************" -ForegroundColor Green

function DownloadFile([System.Uri]$uri, $destinationDirectory){
  $fileName = $uri.Segments[$uri.Segments.Count-1]
  $destinationFile = Join-Path $destinationDirectory $fileName

  Write-Host "Downloading $uri to $destinationFile"  -ForegroundColor Green

  $webclient = New-Object System.Net.WebClient
  $webclient.DownloadFile($uri,$destinationFile)
}

$agentPowerShellLocation = "$Env:AGENT_RELEASEDIRECTORY\$powershellDirectoryName"

if((Test-Path $agentPowerShellLocation  ) -ne $true){
  $result = New-Item $agentPowerShellLocation -Type Directory
  Write-Host "Created $agentPowerShellLocation"
}else{
  Remove-Item "$agentPowerShellLocation\*" -recurse -force
  Write-Host "Cleaned $agentPowerShellLocation"
}

Write-Host "************************************************************************" -ForegroundColor Green
Write-Host "Agent Powershell Repo Created" -ForegroundColor Green
Write-Host "************************************************************************" -ForegroundColor Green

$start= [System.Uri]"https://raw.githubusercontent.com/Cireson/DeploymentTools/master/PowerShell/$deploymentScriptFileName.ps1"
DownloadFile -uri $start -destinationDirectory $agentPowerShellLocation

Write-Host "************************************************************************" -ForegroundColor Green
Write-Host "Deployment Powershell Script Downloaded" -ForegroundColor Green
Write-Host "************************************************************************" -ForegroundColor Green

Import-Module "$agentPowerShellLocation\$deploymentScriptFileName.ps1"

$dependentPackages = @(
    @{
        Name = "Cireson.Platform.Extension.WebUi"
        Version = $null
        FeedName = "Extensions-Integration"
    },
  @{
        Name = "Cireson.AssetManagement.ContentLibrary"
        Version = $null
        FeedName = "Extensions-Integration"
    },
  @{
        Name = "Cireson.AssetManagement.Calculation.Microsoft"
        Version = $null
        FeedName = "Extensions-Integration"
    }
)

Start-Deployment $agentPowerShellLocation $powershellDirectoryName $dependentPackages