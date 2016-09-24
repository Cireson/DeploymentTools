function Start-Deployment($agentPowerShellLocation, $powershellDirectoryName){
	$ErrorActionPreference = "Stop"
	Write-Host "Version 1.0.1" -ForegroundColor Yellow

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
        $ErrorActionPreference = "Stop"
        $onDeploymentVariables = $Using:deploymentVariables
        $onRemotePowerShellLocation = $Using:remotePowerShellLocation
		$onDeploymentScripts = $Using:deploymentScripts

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

        Update-PlatformConfig -targetDirectory $targetDirectory -connectionString $connectionString
    }

	Copy-NuGets $deploymentVariables.resourceGroupName $deploymentVariables.storageAccountName $deploymentVariables.productRoot $deploymentVariables.storageTempContainerName $session $deploymentVariables.agentReleaseDirectory $deploymentVariables.buildDefinitionName

	Start-RemotePlatform -session $session -deploymentVariables $deploymentVariables
}