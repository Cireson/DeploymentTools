function Create-RemoteSession($machineHostName, $machineUserName, $machinePassword){
    $password = ConvertTo-SecureString –String $machinePassword –AsPlainText -Force
    $credential = New-Object –TypeName "System.Management.Automation.PSCredential" –ArgumentList $machineUserName, $password
    $SessionOptions = New-PSSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck
    $targetMachine = "https://${machineHostName}:5986"
    return New-PSSession -ConnectionUri $targetMachine -Credential $credential –SessionOption $SessionOptions
}

function DownloadFile([System.Uri]$uri, $destinationDirectory){
    $fileName = $uri.Segments[$uri.Segments.Count-1]
    $destinationFile = Join-Path $destinationDirectory $fileName

    "Downloading $uri to $destinationFile"

    $webclient = New-Object System.Net.WebClient
    $webclient.DownloadFile($uri,$destinationFile)
}

$addExtensionVersion = "1.0.1"

function Ready-DeploymentEnvironment([hashtable]$deploymentVariables){
	Write-Host "Version $addExtensionVersion"
    $session = Create-RemoteSession $deploymentVariables.targetMachineHostName $deploymentVariables.targetMachineUserName $deploymentVariables.targetMachinePassword
    
	$agentReleaseDirectory = $deploymentVariables.agentReleaseDirectory
	$agentDeploymentToolsPath = "$agentReleaseDirectory\DeploymentTools"

	if((Test-Path $agentDeploymentToolsPath) -ne $true){
        New-Item $agentDeploymentToolsPath -ItemType Directory
    }else{
        Remove-Item -Path "$agentDeploymentToolsPath\*" -Recurse -Force
    }

	$userRights = [System.Uri]"https://raw.githubusercontent.com/Cireson/DeploymentTools/master/PowerShell/UserRights.ps1"
	$utility = [System.Uri]"https://raw.githubusercontent.com/Cireson/DeploymentTools/master/PowerShell/Utility.ps1"
	$components = [System.Uri]"https://raw.githubusercontent.com/Cireson/DeploymentTools/master/PowerShell/AddExtension-Components.ps1"
	
	DownloadFile -uri $userRights -destinationDirectory $agentDeploymentToolsPath
	DownloadFile -uri $utility -destinationDirectory $agentDeploymentToolsPath
    DownloadFile -uri $components -destinationDirectory $agentDeploymentToolsPath

	Invoke-Command -Session $session -ScriptBlock{ 
        $ErrorActionPreference = "Stop"
        $deploymentToolsPath = "c:\DeploymentTools"
		$onDeploymentVariables = $Using:deploymentVariables
		$onUserRights = $Using:userRights
        $onUtility = $Using:utility
		$onComponents = $Using:components

        if((Test-Path $deploymentToolsPath) -ne $true){
            New-Item $deploymentToolsPath -ItemType Directory
        }else{
            Remove-Item -Path "$deploymentToolsPath\*" -Recurse -Force
        }

        Get-ChildItem $deploymentToolsPath
  
        function DownloadFile([System.Uri]$uri, $destinationDirectory){
            $fileName = $uri.Segments[$uri.Segments.Count-1]
            $destinationFile = Join-Path $destinationDirectory $fileName

            "Downloading $uri to $destinationFile"

            $webclient = New-Object System.Net.WebClient
            $webclient.DownloadFile($uri,$destinationFile)
        }

        DownloadFile -uri $onUserRights -destinationDirectory $deploymentToolsPath
        DownloadFile -uri $onUtility -destinationDirectory $deploymentToolsPath
        DownloadFile -uri $onComponents -destinationDirectory $deploymentToolsPath
	}
}

function Ready-TargetEnvironment([hashtable]$deploymentVariables){
    $session = Create-RemoteSession $deploymentVariables.targetMachineHostName $deploymentVariables.targetMachineUserName $deploymentVariables.targetMachinePassword

	$agentReleaseDirectory = $deploymentVariables.agentReleaseDirectory
	$agentDeploymentToolsPath = "$agentReleaseDirectory\DeploymentTools"

	Import-Module "$agentDeploymentToolsPath\Utility.ps1"
    Import-Module "$agentDeploymentToolsPath\AddExtension-Components.ps1"

	Copy-NuGets $deploymentVariables.resourceGroupName $deploymentVariables.storageAccountName $deploymentVariables.productRoot $deploymentVariables.storageTempContainerName $session $deploymentVariables.agentReleaseDirectory $deploymentVariables.buildDefinitionName

    Invoke-Command -Session $session -ScriptBlock{ 
        $ErrorActionPreference = "Stop"
		$onDeploymentVariables = $Using:deploymentVariables
		$serviceName = $onDeploymentVariables.serviceName
		$deploymentToolsPath = "c:\DeploymentTools"

		Import-Module "$deploymentToolsPath\Utility.ps1"

        Get-PowerShellVersion

		try{
			Restart-Service -DisplayName "Platform_$serviceName"
		}catch{
			Stop-Process -processname "Cireson.Platform.Host" -Force
			Restart-Service -DisplayName "Platform_$serviceName"
		}
    }
}