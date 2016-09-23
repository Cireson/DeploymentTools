Add-Type -AssemblyName System.IO.Compression.FileSystem

function Download-File([System.Uri]$uri, $destinationDirectory){
    $fileName = $uri.Segments[$uri.Segments.Count-1]
    $destinationFile = Join-Path $destinationDirectory $fileName

    "Downloading $uri to $destinationFile"

    $webclient = New-Object System.Net.WebClient
    $webclient.DownloadFile($uri,$destinationFile)
}

function Unzip-File([string]$zipfile, [string]$outpath)
{
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipfile, $outpath)
}

function Get-PowerShellVersion(){
    "Running PowerShell Version"
    "************************************************************************"
    $PSVersionTable.PSVersion
    "************************************************************************"
}

function Create-RemoteSession($machineHostName, $machineUserName, $machinePassword){
    $password = ConvertTo-SecureString –String $machinePassword –AsPlainText -Force
    $credential = New-Object –TypeName "System.Management.Automation.PSCredential" –ArgumentList $machineUserName, $password
    $SessionOptions = New-PSSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck
    $targetMachine = "https://${machineHostName}:5986"
    return New-PSSession -ConnectionUri $targetMachine -Credential $credential –SessionOption $SessionOptions
}