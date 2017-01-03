Param(
	[Parameter(Position=0)]
	$currentValues
)

function CreateOrUpdateWebsite($newWebsitePath){
    $ErrorActionPreference = "Stop"
	Write-Host "************************************************************************"
	Write-Host "CreateOrUpdateWebsite Version 1.0.1" -ForegroundColor Yellow

	[Void][Reflection.Assembly]::LoadWithPartialName("Microsoft.Web.Administration")

    $currentWebsitePath = ""
    $websiteName = "ConfigMgrPortal"

    $serverManager = New-Object Microsoft.Web.Administration.ServerManager

    # Find current version from IIS
    $site = $serverManager.Sites | Where-Object {$_.name -eq $websiteName}

    if($site -eq $null){
        # If no current version setup site for first time.
        New-WebAppPool -Name $websiteName
        Write-Host "Setup application pool."
        New-Website -Name $websiteName -PhysicalPath $newWebsitePath -ApplicationPool $websiteName -Port 80 -HostHeader "integration-configmgrportal.cireson.com"
        Set-WebConfiguration system.webServer/security/authentication/windowsAuthentication -PSPath IIS:\ -Location $websiteName -Value @{enabled="True"}
        Set-WebConfiguration system.webServer/security/authentication/anonymousAuthentication -PSPath IIS:\ -Location $websiteName -Value @{enabled="False"}
        Write-Host "Setup new web site."
    }else{
        $rootApp = $site.Applications | where-object { $_.Path -eq "/" }
        $rootApp.VirtualDirectories | where { $_.Path -eq "/" }
        $rootVdir = $rootApp.VirtualDirectories | where { $_.Path -eq "/" }
        $currentWebsitePath = $rootVdir.PhysicalPath;

        # Otherwise copy Configuration.xml and Web.Config from old over new.
        $configFileSource = $currentWebsitePath + "\configuration.xml"
        $configFileTarget = $newWebsitePath + "\configuration.xml"
        if((Test-Path $configFileSource) -eq $true -and $configFileSource -ne $configFileTarget){
            Copy-Item -path $configFileSource -Destination $configFileTarget -Force
            Write-Host "Copied existing Configuration.xml to new site."
        }

        $webConfigFileSource = $currentWebsitePath + "\web.config"
        $webConfigFileTarget = $newWebsitePath + "\web.config"
        if((Test-Path $webConfigFileSource) -eq $true -and $webConfigFileSource -ne $webConfigFileTarget){
            Copy-Item -path $webConfigFileSource -Destination $webConfigFileTarget -Force
            Write-Host "Copied existing Web.config to new site."
        }

        # Point website at new folder
        $rootVdir.PhysicalPath = $newWebsitePath
        $serverManager.CommitChanges()
        Write-Host "Updated existing site's physical path"
    }
}

function Update-ServiceConfiguration($serviceRoot, $websiteRoot){
	$ErrorActionPreference = "Stop"
	Write-Host "************************************************************************"
	Write-Host "Update-ServiceConfiguration Version 1.0.1" -ForegroundColor Yellow

    $configFile = $serviceRoot + "\ConfigMgr Portal Hosting Service.exe.config"
    [xml] $xml = Get-Content $configFile
    $xml.SelectSingleNode("/configuration/appSettings/add[@key='BaseFolder']").value = $websiteRoot
    $xml.Save($configFile)
}

function Get-WebsiteDeploymentInfo($version){
	$ErrorActionPreference = "Stop"
	Write-Host "************************************************************************"
	Write-Host "Get-WebsiteDeploymentInfo Version 1.0.2" -ForegroundColor Yellow

    $websiteDeployPath = "c:\websites"
	Write-Host "Path: '$websiteDeployPath'"

    if((Test-Path -Path $websiteDeployPath) -eq $false){
        New-Item -Path $websiteDeployPath -ItemType Directory
    }

    $websiteDeploymentPath = $websiteDeployPath + "\deployment"
	Write-Host "DeploymentPath: '$websiteDeploymentPath'"
    if((Test-Path -Path $websiteDeploymentPath) -eq $false){
        New-Item -Path $websiteDeploymentPath -ItemType Directory
    }
    
    $websiteDeployPath = $websiteDeployPath + "\cmpWebsite"
	Write-Host "Path: '$websiteDeployPath'"
    if((Test-Path -Path $websiteDeployPath) -eq $false){
        New-Item -Path $websiteDeployPath -ItemType Directory
    }

    $websiteDeployPath = $websiteDeployPath + "\" + $version
	Write-Host "Path: '$websiteDeployPath'"
    if((Test-Path -Path $websiteDeployPath) -eq $true){
        Remove-Item $websiteDeployPath -Recurse -Force
    }
    New-Item -Path $websiteDeployPath -ItemType Directory

    $websiteSourcePath = ""
    $files = ls $websiteDeploymentPath
    $file = $files | Where-Object{ $_.Extension -eq ".zip"} | Select-Object -first 1
    $file

    if($file -ne $null){
        $websiteSourcePath = $websiteDeploymentPath + "\extracted"
        if((Test-Path -Path $websiteSourcePath) -eq $true){
            Remove-Item $websiteSourcePath -Recurse -Force
        }

        New-Item -Path $websiteSourcePath -ItemType Directory

        Unzip-File -zipfile $file.FullName -outpath $websiteSourcePath
        $websiteSourcePath = $websiteSourcePath + "\website\*"
    }

    return @{
        SourcePath = $websiteSourcePath
        DeployPath = $websiteDeployPath
    }
}

Write-Host "************************************************************************"
Write-Host "WebsiteSetup Version 1.0.7" -ForegroundColor Yellow

Write-Host "Current Values: $currentValues"

$version = $currentValues.Version
Write-Host "Version: '$version'"
$websiteInfo = Get-WebsiteDeploymentInfo -version $version
Copy-Item -Path $websiteInfo.SourcePath -Destination $websiteInfo.DeployPath -Recurse
CreateOrUpdateWebsite -newWebsitePath $websiteInfo.DeployPath

$serviceDeployPath = "c:\services"

if((Test-Path -Path $serviceDeployPath) -eq $false){
    New-Item -Path $serviceDeployPath -ItemType Directory
}

$serviceSourcePath = $serviceDeployPath + "\deployment"
if((Test-Path -Path $serviceSourcePath) -eq $false){
    New-Item -Path $serviceSourcePath -ItemType Directory
}

$serviceDeployPath = $serviceDeployPath + "\cmpService"

if((Test-Path -Path $serviceDeployPath) -eq $false){
    New-Item -Path $serviceDeployPath -ItemType Directory
}

$serviceDeployPath = $serviceDeployPath + "\" + $version

if((Test-Path -Path $serviceDeployPath) -eq $true){
    Remove-Item $serviceDeployPath -Recurse -Force
}
New-Item -Path $serviceDeployPath -ItemType Directory

$serviceSourcePath = $serviceSourcePath + "\Cireson ConfigMgr Portal Service x64.msi"

Copy-Item -Path $serviceSourcePath -Destination $serviceDeployPath

$serviceMsi = $serviceDeployPath + "\Cireson ConfigMgr Portal Service x64.msi"

# run the msi
#msiexec.exe /i '$serviceMsi' /qn /l*v c:\Temp\logfile.log ALLUSERS=2    
$arguments = @(
    "/i"
    "`"$serviceMsi`""
    "/qn"
)
$process = Start-Process -FilePath msiexec.exe -ArgumentList $arguments -Wait -PassThru
if($process.ExitCode -eq 0){
    Write-Host "Installed Service"
}
    
$serviceDeployPath = "$Env:ProgramFiles\Cireson\Portal for Configuration Manager\Services"

# Update ConfigMgr Portal Hosting Service.exe.config, setting the BaseFolder to the new folder for website
Update-ServiceConfiguration -serviceRoot $serviceDeployPath -websiteRoot $websiteInfo.DeployPath

# Start Portal Service
Start-Service -Name "Cireson ConfigMgr Portal Hosting Service"