function DownloadFile([System.Uri]$uri, $destinationDirectory){
    $fileName = $uri.Segments[$uri.Segments.Count-1]
    $destinationFile = Join-Path $destinationDirectory $fileName

    "Downloading $uri to $destinationFile"

    $webclient = New-Object System.Net.WebClient
    $webclient.DownloadFile($uri,$destinationFile)
}

function Get-DeploymentScripts($destinationFolder, $uris){
	Write-Host "Start Get-DeploymentScripts" -ForegroundColor Green
	if((Test-Path $destinationFolder) -ne $true){
        $newItem = New-Item $destinationFolder -ItemType Directory
		Write-Host "Created destination $destinationFolder" -ForegroundColor Green
    }else{
        Remove-Item -Path "$destinationFolder\*" -Recurse -Force
		Write-Host "Cleaned destination $destinationFolder" -ForegroundColor Green
    }

	foreach($uri in $uris){
		DownloadFile -uri $uri -destinationDirectory $destinationFolder
	}

	Write-Host "End Get-DeploymentScripts" -ForegroundColor Green
}

function Import-DeploymentScripts($agentPowerShellLocation, $uris){
	foreach($uri in $uris){
		$fileName = $uri.Segments[$uri.Segments.Count-1]
		Import-Module "$agentPowerShellLocation\$fileName"
	}
}

function Start-Deployment($agentPowerShellLocation, $powershellDirectoryName){
	$ErrorActionPreference = "Stop"
	Write-Host "Version 2.0.3" -ForegroundColor Yellow

	$deploymentVariables = @{
		targetMachineHostName = $Env:targetMachineHostName
		targetMachineUserName = $Env:targetMachineUserName
		targetMachinePassword = $Env:targetMachinePassword
		resourceGroupName = $Env:resourceGroupName 
		storageAccountName = $Env:storageAccountName 
		productRoot = $Env:productRoot 
		storageTempContainerName = $Env:storageTempContainerName
		serviceName = $Env:serviceName
		agentReleaseDirectory = $Env:AGENT_RELEASEDIRECTORY
		buildDefinitionName = $Env:BUILD_DEFINITIONNAME
		serviceUserName = $Env:serviceUserName
		serviceUserPassword = $Env:serviceUserPassword
		azureSqlServerName = $Env:azureSqlServerName
		azureSqlUserName = $Env:azureSqlUserName
		azureSqlUserPassword = $Env:azureSqlUserPassword
		azureSqlDatabase = $Env:azureSqlDatabase
		platformVersion = $Env:platformVersion
		azureSqlAdministratorUserName = $Env:azureSqlAdministratorUserName
		azureSqlAdministratorPassword = $Env:azureSqlAdministratorPassword
		targetVersion = $env:BUILD_BUILDNUMBER
	}

	Write-Host "Environment Variables Copied to HashTable`r`n" -ForegroundColor Green
	foreach($key in $deploymentVariables.keys){
		$value = $deploymentVariables[$key]
		Write-Host "$key`: $value" -ForegroundColor Green
	}

	$deploymentScripts = @(
		[System.Uri]"https://raw.githubusercontent.com/Cireson/DeploymentTools/master/PowerShell/UserRights.ps1"
		[System.Uri]"https://raw.githubusercontent.com/Cireson/DeploymentTools/master/PowerShell/Utility.ps1"
		[System.Uri]"https://raw.githubusercontent.com/Cireson/DeploymentTools/master/PowerShell/GlobalContentLibrary-Components.ps1"
	)

	Get-DeploymentScripts $agentPowerShellLocation $deploymentScripts

	Import-DeploymentScripts $agentPowerShellLocation $deploymentScripts

	$remotePowerShellLocation = "c:\$powershellDirectoryName"
	$session = Create-RemoteSession $deploymentVariables.targetMachineHostName $deploymentVariables.targetMachineUserName $deploymentVariables.targetMachinePassword

	Ensure-EmptyRemoteDirectoryExists -session $session -directory $remotePowerShellLocation 

	Ready-DeploymentEnvironment $session $deploymentScripts $remotePowerShellLocation

	Ready-TargetEnvironment $session $agentPowerShellLocation $remotePowerShellLocation $deploymentVariables
}