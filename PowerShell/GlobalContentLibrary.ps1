function Create-RemoteSession($machineHostName, $machineUserName, $machinePassword){
    $password = ConvertTo-SecureString –String $machinePassword –AsPlainText -Force
    $credential = New-Object –TypeName "System.Management.Automation.PSCredential" –ArgumentList $machineUserName, $password
    $SessionOptions = New-PSSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck
    $targetMachine = "https://${machineHostName}:5986"
    return New-PSSession -ConnectionUri $targetMachine -Credential $credential –SessionOption $SessionOptions
}

function Ready-DeploymentEnvironment([string]$targetMachineHostName, [string]$targetMachineUserName, [string]$targetMachinePassword){
    $session = Create-RemoteSession $targetMachineHostName $targetMachineUserName $targetMachinePassword
    Invoke-Command -Session $session -ScriptBlock{ 
        $deploymentToolsPath = "c:\DeploymentTools"
        
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

        $userRights = [System.Uri]"https://raw.githubusercontent.com/Cireson/DeploymentTools/master/PowerShell/UserRights.ps1"
        $utility = [System.Uri]"https://raw.githubusercontent.com/Cireson/DeploymentTools/master/PowerShell/Utility.ps1"

        DownloadFile -uri $userRights -destinationDirectory $deploymentToolsPath
        DownloadFile -uri $utility -destinationDirectory $deploymentToolsPath
    }
}

function Ready-TargetEnvironment([string]$targetMachineHostName, [string]$targetMachineUserName, [string]$targetMachinePassword){
    $session = Create-RemoteSession $targetMachineHostName $targetMachineUserName $targetMachinePassword
    Invoke-Command -Session $session -ScriptBlock{ 
        $deploymentToolsPath = "c:\DeploymentTools"
        
        Import-Module "$deploymentToolsPath\Utility.ps1"

        Get-PowerShellVersion
    }
}