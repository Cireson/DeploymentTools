Add-Type -AssemblyName System.IO.Compression.FileSystem

function Download-File([System.Uri]$uri, $destinationDirectory, $basicAuthValue, $fileName){
	Write-Host "************************************************************************"
	Write-Host "Download-File Version 1.0.0"

	if($fileName -ne $null){
        $destinationFile = Join-Path $destinationDirectory $fileName
    }else{
        $fileName = $uri.Segments[$uri.Segments.Count-1]
        $destinationFile = Join-Path $destinationDirectory $fileName
    }

    Write-Host "Downloading $uri to $destinationFile"

    $webclient = New-Object System.Net.WebClient

	if($basicAuthValue -ne $null){
        $webclient.Headers.Add("Authorization", $basicAuthValue)
    }

    $webclient.DownloadFile($uri,$destinationFile)
}

function Unzip-File([string]$zipfile, [string]$outpath)
{
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipfile, $outpath)
}

function Get-PowerShellVersion(){
    "************************************************************************"
	Write-Host "Get-PowerShellVersion Version 1.0.0"
	$powershellInfo = $PSVersionTable.PSVersion
	$major = $powershellInfo.Major
	$minor = $powershellInfo.Minor
	Write-Host "Running PowerShell Version $major.$minor"
}

function Create-RemoteSession($machineHostName, $machineUserName, $machinePassword){
    $password = ConvertTo-SecureString �String $machinePassword �AsPlainText -Force
    $credential = New-Object �TypeName "System.Management.Automation.PSCredential" �ArgumentList $machineUserName, $password
    $SessionOptions = New-PSSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck
    $targetMachine = "https://${machineHostName}:5986"
    return�New-PSSession -ConnectionUri $targetMachine -Credential $credential �SessionOption $SessionOptions
}