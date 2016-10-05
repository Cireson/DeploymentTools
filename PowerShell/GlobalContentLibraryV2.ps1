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
	Write-Host "Start-Deployment Version 2.0.7" -ForegroundColor Yellow

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
		vstsAccountName = $Env:vstsAccountName
		vstsApiUserName = $Env:vstsApiUserName
		vstsApiPassword = $Env:vstsApiPassword
		dependentPackages = $dependentPackages
	}

	Write-Host "Environment Variables Copied to HashTable`r`n" -ForegroundColor Green
	foreach($key in $deploymentVariables.keys){
		$value = $deploymentVariables[$key]
		Write-Host "$key`: $value" -ForegroundColor Green
	}

	$deploymentScripts = @(
		[System.Uri]"https://raw.githubusercontent.com/Cireson/DeploymentTools/master/PowerShell/UserRights.ps1"
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

	$adminConnectionString = Create-PlatformConnectionString -sqlServer $deploymentVariables.azureSqlServerName -sqlDatabase $deploymentVariables.azureSqlDatabase -sqlUserName $deploymentVariables.azureSqlAdministratorUserName -sqlPassword $deploymentVariables.azureSqlAdministratorPassword

	Create-ContainedDatabaseUser -connectionString $adminConnectionString -sqlServiceUserName $deploymentVariables.azureSqlUserName -sqlServiceUserPassword $deploymentVariables.azureSqlUserPassword

	Invoke-Command -Session $session -ScriptBlock{
		Write-Host "************************************************************************"
		
        $ErrorActionPreference = "Stop"
        $onDeploymentVariables = $Using:deploymentVariables
        $onRemotePowerShellLocation = $Using:remotePowerShellLocation
		$onDeploymentScripts = $Using:deploymentScripts

		$targetMachineHostName = $onDeploymentVariables.targetMachineHostName
		Write-Host "Running on remote machine, $targetMachineHostName."

        $productDirectory = $onDeploymentVariables.productRoot
        $serviceName = $onDeploymentVariables.serviceName

        foreach($uri in $onDeploymentScripts){
			$fileName = $uri.Segments[$uri.Segments.Count-1]
			$module = "$onRemotePowerShellLocation\$fileName"
			Write-Host "`tImporting module $module" -ForegroundColor Green
			Import-Module $module
		}

        Get-PowerShellVersion

        Create-DestinationDirectories -root $productDirectory -targetVersion $onDeploymentVariables.targetVersion

        $connectionString = Create-PlatformConnectionString -sqlServer $onDeploymentVariables.azureSqlServerName -sqlDatabase $onDeploymentVariables.azureSqlDatabase -sqlUserName $onDeploymentVariables.azureSqlUserName -sqlPassword $onDeploymentVariables.azureSqlUserPassword
        $targetDirectory = Create-TargetDirectory $productDirectory $onDeploymentVariables.targetVersion

        Remove-RunningService -serviceName "Platform_$serviceName"

        Create-InboundFirewallRule "Http 80" "80"
        Create-InboundFirewallRule "Https 443" "443"

        Create-ServiceUser -serviceUserName $onDeploymentVariables.serviceUserName -servicePassword $onDeploymentVariables.serviceUserPassword

        Download-Platform -baseDirectory $productDirectory -platformVersion $onDeploymentVariables.platformVersion -targetDirectory $targetDirectory

		Download-Extension -name "" -version "" -feed "prerelease" -account "Cireson"

        Update-PlatformConfig -targetDirectory $targetDirectory -connectionString $connectionString

		$vstsAuth = Create-AuthForVsts -userName $vstsApiUserName -password $vstsApiPassword
		foreach($package in $onDeploymentVariables.dependentPackages){
			Download-Extension -name $package.Name -version $package.Version -feedName $package.FeedName -account $vstsAccountName -vstsAuth $vstsAuth    
		}

		Write-Host "End running on remote machine, $targetMachineHostName."
    }

	Copy-NuGets $deploymentVariables.resourceGroupName $deploymentVariables.storageAccountName $deploymentVariables.productRoot $deploymentVariables.storageTempContainerName $session $deploymentVariables.agentReleaseDirectory $deploymentVariables.buildDefinitionName

	Start-RemotePlatform -session $session -deploymentVariables $deploymentVariables
}