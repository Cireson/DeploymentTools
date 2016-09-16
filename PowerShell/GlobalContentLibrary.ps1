Param(
    [string]$targetMachineHostName,
    [string]$targetMachineUserName,
    [string]$targetMachinePassword
)

function CreateRemoteSession($machineHostName, $machineUserName, $machinePassword){
    $password = ConvertTo-SecureString –String $machinePassword –AsPlainText -Force
    $credential = New-Object –TypeName "System.Management.Automation.PSCredential" –ArgumentList $machineUserName, $password
    $SessionOptions = New-PSSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck
    $targetMachine = "https://${machineHostName}:5986"
    return New-PSSession -ConnectionUri $targetMachine -Credential $credential –SessionOption $SessionOptions
}

$session = CreateRemoteSession $targetMachineHostName $targetMachineUserName $targetMachinePassword

Invoke-Command -Session $session -ScriptBlock{ 
    $deploymentToolsPath = "c:\DeploymentTools"
    if((Test-Path $deploymentToolsPath) -ne $true){
    New-Item $deploymentToolsPath -ItemType Directory
    }
  
    function DownloadFile([System.Uri]$uri, $destinationDirectory){
        $fileName = $uri.Segments[$uri.Segments.Count-1]
        $destinationFile = Join-Path $destinationDirectory $fileName

        "Downloading $uri to $destinationFile"

        $webclient = New-Object System.Net.WebClient
        $webclient.DownloadFile($uri,$destinationFile)
    }

    $userRights = [System.Uri]"https://raw.githubusercontent.com/Cireson/DeploymentTools/master/PowerShell/UserRights.ps1"

    DownloadFile -uri $userRights -destinationDirectory $deploymentToolsPath
}