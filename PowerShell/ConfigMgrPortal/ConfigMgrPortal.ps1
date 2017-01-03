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

function Start-Deployment($agentPowerShellLocation, $powershellDirectoryName, $dependentPackages){
	$ErrorActionPreference = "Stop"
	Write-Host "************************************************************************"
	Write-Host "Start-Deployment Version 1.0.3" -ForegroundColor Yellow

	$deploymentVariables = @{
		targetMachineHostName = $Env:targetMachineHostName
		targetMachineUserName = $Env:targetMachineUserName
		targetMachinePassword = $Env:targetMachinePassword
		resourceGroupName = $Env:resourceGroupName 
		storageAccountName = $Env:storageAccountName  
		storageTempContainerName = $Env:storageTempContainerName
		agentReleaseDirectory = $Env:AGENT_RELEASEDIRECTORY
		buildDefinitionName = $Env:BUILD_DEFINITIONNAME
		targetVersion = $env:BUILD_BUILDNUMBER
		vstsAccountName = $Env:vstsAccountName
		vstsApiUserName = $Env:vstsApiUserName
		vstsApiPassword = $Env:vstsApiPassword
	}

	Write-Host "Environment Variables Copied to HashTable`r`n" -ForegroundColor Green
	foreach($key in $deploymentVariables.keys){
		$value = $deploymentVariables[$key]
		Write-Host "$key`: $value" -ForegroundColor Green
	}

	$deploymentScripts = @(
		[System.Uri]"https://raw.githubusercontent.com/Cireson/DeploymentTools/master/PowerShell/ConfigMgrPortal/WebsiteSetup.ps1"
		[System.Uri]"https://raw.githubusercontent.com/Cireson/DeploymentTools/master/PowerShell/Utility.ps1"
		[System.Uri]"https://raw.githubusercontent.com/Cireson/DeploymentTools/master/PowerShell/CommonDeployment.ps1"
	)

	Get-DeploymentScripts $agentPowerShellLocation $deploymentScripts

	foreach($uri in $deploymentScripts){
		$fileName = $uri.Segments[$uri.Segments.Count-1]
		$module = "$agentPowerShellLocation\$fileName"
		Write-Host "`tImporting module $module" -ForegroundColor Green
		Import-Module $module
	}

	$remotePowerShellLocation = "c:\$powershellDirectoryName"
	$session = Create-RemoteSession $deploymentVariables.targetMachineHostName $deploymentVariables.targetMachineUserName $deploymentVariables.targetMachinePassword

	Ensure-EmptyRemoteDirectoryExists -session $session -directory $remotePowerShellLocation 

	Push-RemoteDeploymentScripts $session $deploymentScripts $remotePowerShellLocation

	$remoteScript = $remotePowerShellLocation + "\WebsiteSetup.ps1"
	$remoteValues = @{
		"Version" = $deploymentVariables.targetVersion
	}

	Invoke-Command -Session $session -FilePath $remoteScript
}