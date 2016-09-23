function DownloadFile([System.Uri]$uri, $destinationDirectory){
    $fileName = $uri.Segments[$uri.Segments.Count-1]
    $destinationFile = Join-Path $destinationDirectory $fileName

    "Downloading $uri to $destinationFile"

    $webclient = New-Object System.Net.WebClient
    $webclient.DownloadFile($uri,$destinationFile)
}

function Ensure-EmptyRemoteDirectoryExists($session, $directory){
	Invoke-Command -Session $session -ScriptBlock{ 
		$ErrorActionPreference = "Stop"
		if((Test-Path $directory) -ne $true){
			$result = New-Item $directory -ItemType Directory
			Write-Host "Created $directory" -ForegroundColor Green
		}else{
			Remove-Item -Path "$directory\*" -Recurse -Force
			Write-Host "Cleaned $directory" -ForegroundColor Yellow
		}
	}
}

function Ready-DeploymentEnvironment($session, $uris, $remotePowerShellLocation){
	Invoke-Command -Session $session -ScriptBlock{ 
        $ErrorActionPreference = "Stop"
		$onUris = $Using:uris
		$onRemotePowerShellLocation = $Using:remotePowerShellLocation

        function DownloadFile([System.Uri]$uri, $destinationDirectory){
            $fileName = $uri.Segments[$uri.Segments.Count-1]
            $destinationFile = Join-Path $destinationDirectory $fileName

            Write-Host "Downloading $uri to $destinationFile" -ForegroundColor Green

            $webclient = New-Object System.Net.WebClient
            $webclient.DownloadFile($uri,$destinationFile)
        }

        foreach($uri in $onUris){
			DownloadFile -uri $uri -destinationDirectory $onRemotePowerShellLocation
		}
    }
}

function Ready-TargetEnvironment($session, $agentPowerShellLocation, $remotePowerShellLocation, [hashtable]$deploymentVariables){
	Import-Module "$agentPowerShellLocation\Utility.ps1"
    Import-Module "$agentPowerShellLocation\GlobalContentLibrary-Components.ps1"

    Invoke-Command -Session $session -ScriptBlock{ 
        $ErrorActionPreference = "Stop"
        $onDeploymentVariables = $Using:deploymentVariables
        $onRemotePowerShellLocation = $Using:remotePowerShellLocation

        $productDirectory = $onDeploymentVariables.productRoot
        $serviceName = $onDeploymentVariables.serviceName

        Import-Module "$onRemotePowerShellLocation\Utility.ps1"
        Import-Module "$onRemotePowerShellLocation\UserRights.ps1"
        Import-Module "$onRemotePowerShellLocation\GlobalContentLibrary-Components.ps1"

        Get-PowerShellVersion

        Create-DestinationDirectories -root $productDirectory -targetVersion $onDeploymentVariables.targetVersion

        $adminConnectionString = Create-PlatformConnectionString -sqlServer $onDeploymentVariables.azureSqlServerName -sqlDatabase $onDeploymentVariables.azureSqlDatabase -sqlUserName $onDeploymentVariables.azureSqlAdministratorUserName -sqlPassword $onDeploymentVariables.azureSqlAdministratorPassword
        $connectionString = Create-PlatformConnectionString -sqlServer $onDeploymentVariables.azureSqlServerName -sqlDatabase $onDeploymentVariables.azureSqlDatabase -sqlUserName $onDeploymentVariables.azureSqlUserName -sqlPassword $onDeploymentVariables.azureSqlUserPassword
        $targetDirectory = Create-TargetDirectory $productDirectory $onDeploymentVariables.targetVersion

        Create-ContainedDatabaseUser -connectionString $adminConnectionString -sqlServiceUserName $onDeploymentVariables.azureSqlUserName -sqlServiceUserPassword $onDeploymentVariables.azureSqlUserPassword

        Remove-RunningService -serviceName "Platform_$serviceName"

        Create-InboundFirewallRule "Http 80" "80"
        Create-InboundFirewallRule "Https 443" "443"

        Create-ServiceUser -serviceUserName $onDeploymentVariables.serviceUserName -servicePassword $onDeploymentVariables.serviceUserPassword

        Download-Platform -baseDirectory $productDirectory -platformVersion $onDeploymentVariables.platformVersion -targetDirectory $targetDirectory

        Update-PlatformConfig -targetDirectory $targetDirectory -connectionString $connectionString
    }

	Copy-NuGets $deploymentVariables.resourceGroupName $deploymentVariables.storageAccountName $deploymentVariables.productRoot $deploymentVariables.storageTempContainerName $session $deploymentVariables.agentReleaseDirectory $deploymentVariables.buildDefinitionName

	Invoke-Command -Session $session -ScriptBlock{ 
        $ErrorActionPreference = "Stop"
        $onDeploymentVariables = $Using:deploymentVariables
		$onRemotePowerShellLocation = $Using:remotePowerShellLocation

        $productDirectory = $onDeploymentVariables.productRoot

		Start-Platform $onDeploymentVariables.azureSqlUserName $onDeploymentVariables.azureSqlUserPassword $productDirectory $onDeploymentVariables.targetVersion
    }
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

function Start-Deployment($agentPowerShellLocation, $powershellDirectoryName){
	Write-Host "Version 2.0.1" -ForegroundColor Yellow

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

	Import-Module "$agentPowerShellLocation\Utility.ps1"

	$remotePowerShellLocation = "c:\$powershellDirectoryName"
	$session = Create-RemoteSession $deploymentVariables.targetMachineHostName $deploymentVariables.targetMachineUserName $deploymentVariables.targetMachinePassword

	Ensure-EmptyRemoteDirectoryExists $session $remotePowerShellLocation

	Ready-DeploymentEnvironment $session $deploymentScripts $remotePowerShellLocation

	Ready-TargetEnvironment $session $agentPowerShellLocation $remotePowerShellLocation $deploymentVariables
}