function CreateOrUpdateWebsite($newWebsitePath, $versionsPath, $appPoolSettings, $version){
    $ErrorActionPreference = "Stop"
	Write-Host "************************************************************************"
	Write-Host "CreateOrUpdateWebsite Version 1.0.8" -ForegroundColor Yellow

	[Void][Reflection.Assembly]::LoadWithPartialName("Microsoft.Web.Administration")
	Import-Module WebAdministration

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
        $rootVdir = $rootApp.VirtualDirectories | where { $_.Path -eq "/" }
        $currentWebsitePath = $rootVdir.PhysicalPath;

        Write-Host "Copy configuration.xml from old site to new site."
        $configFileSource = $currentWebsitePath + "\configuration.xml"
        $configFileTarget = $newWebsitePath + "\configuration.xml"
		Write-Host "Old configuration file path: $configFileSource"
		Write-Host "New configuration file path: $configFileTarget"
        if((Test-Path $configFileSource) -eq $true -and $configFileSource -ne $configFileTarget){
            Copy-Item -path $configFileSource -Destination $configFileTarget -Force
            Write-Host "Copied existing Configuration.xml to new site."
        }else{
			Write-Host "No existing Configuration.xml to copy."
		}

        $webConfigFileSource = $currentWebsitePath + "\web.config"
        $webConfigFileTarget = $newWebsitePath + "\web.config"
		Write-Host "Old web.config file path: $webConfigFileSource"
		Write-Host "New web.config file path: $webConfigFileTarget"
        if((Test-Path $webConfigFileSource) -eq $true -and $webConfigFileSource -ne $webConfigFileTarget){
            Copy-Item -path $webConfigFileSource -Destination $webConfigFileTarget -Force
            Write-Host "Copied existing Web.config to new site."
        }else{
			Write-Host "No existing web.config to copy."
		}

        # Point website at new folder
        $rootVdir.PhysicalPath = $newWebsitePath
        $serverManager.CommitChanges()
        Write-Host "Updated existing site's physical path"
    }

	$username = $appPoolSettings.userName;
	Set-ItemProperty IIS:\AppPools\$websiteName -Name processModel -Value @{userName=$username;password=$appPoolSettings.password;identitytype=3}

	$currentAcl = Get-Acl -Path $versionsPath

	$appPoolIdentity = $currentAcl.Access | Where-Object { $_.IdentityReference -eq $username}

	if($appPoolIdentity -ne $null){
		Write-Host "$username has full control of $versionsPath"
	}else{
		$accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($username, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
		$currentAcl.SetAccessRule($accessRule)
		Set-Acl $versionsPath $currentAcl
		Write-Host "Granted $appPoolSettings.userName full control of $versionsPath"
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
	Write-Host "Get-WebsiteDeploymentInfo Version 1.0.6" -ForegroundColor Yellow

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
	$websiteVersionsRoot = $websiteDeployPath;
	Write-Host "Path: '$websiteDeployPath'"
    if((Test-Path -Path $websiteDeployPath) -eq $false){
        New-Item -Path $websiteDeployPath -ItemType Directory
    }

    $versionedPath = $websiteDeployPath + "\" + $version
	$num = 0
	While((Test-Path -Path $versionedPath) -eq $true){
		$num = $num + 1
		$redeployVersion = $version + "-Redeploy" + $num
		$versionedPath = $websiteDeployPath + "\" + $redeployVersion
	}
	$websiteDeployPath = $versionedPath
	$version = $redeployVersion
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
		WebsiteVersionsPath = $websiteVersionsRoot
        SourcePath = $websiteSourcePath
        DeployPath = $websiteDeployPath
		Version = $version
    }
}

function Setup-Website($currentValues){
	Write-Host "************************************************************************"
	Write-Host "WebsiteSetup Version 1.0.20" -ForegroundColor Yellow

	Write-Host "Current Values: $currentValues"

	$version = $currentValues.targetVersion
	$appPoolSettings = @{
		userName = $currentValues.appPoolUserName
		password = $currentValues.appPoolPassword
	}
	Write-Host "Version: '$version'"
	$websiteInfo = Get-WebsiteDeploymentInfo -version $version
	$version = $websiteInfo.Version
	Copy-Item -Path $websiteInfo.SourcePath -Destination $websiteInfo.DeployPath -Recurse
	CreateOrUpdateWebsite -newWebsitePath $websiteInfo.DeployPath -versionsPath $websiteInfo.WebsiteVersionsPath -appPoolSettings $appPoolSettings -version $version

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
	
	#Added by Seth
	#Uninstall the application/service if found first
	$app = Get-WmiObject -Class Win32_Product -Filter "Name = 'Cireson ConfigMgr Portal Service'"
	if($app -ne $null) {
		$app.Uninstall()
	}

	# run the msi
	#msiexec.exe /i '$serviceMsi' /qn /l*v c:\Temp\logfile.log ALLUSERS=2    

	$arguments = @(
		"/i"
		"`"$serviceMsi`""
		"/qn"
		"/l*v C:\Windows\Temp\portalinstallogfile.log"
		"ALLUSERS=2"
	)
	
	#this isn't needed anymore as the service is removed first
	try{
		$service = Get-Service "Cireson ConfigMgr Portal Hosting Service" -ErrorAction Stop

		Write-Host "Stopping Found Service"
		Stop-Service $service -Force
	}catch{
		Write-Host "Service Not Found"
	}
	
	$process = Start-Process -FilePath msiexec.exe -ArgumentList $arguments -Wait -PassThru
	if($process.ExitCode -eq 0){
		Write-Host "Installed Service"
	}else{
		Write-Host "Process Failed to Install Service"
		$process
		Write-Host "Arguments Were"
		$arguments
		throw "Failure running MSIEXEC"
	}

	$arguments = @(
		"/fa"
		"`"$serviceMsi`""
		"/qn"
		"/l*v C:\Windows\Temp\portalinstallogfile.log"
		"ALLUSERS=2"
	)

	$process = Start-Process -FilePath msiexec.exe -ArgumentList $arguments -Wait -PassThru
	if($process.ExitCode -eq 0){
		Write-Host "Repaired Service"
	}else{
		Write-Host "Process Failed to Repair Service"
		$process
		Write-Host "Arguments Were"
		$arguments
		throw "Failure running MSIEXEC"
	}

	$serviceDeployPath = "$Env:ProgramFiles\Cireson\Portal for Configuration Manager\Services"

	# Update ConfigMgr Portal Hosting Service.exe.config, setting the BaseFolder to the new folder for website
	Update-ServiceConfiguration -serviceRoot $serviceDeployPath -websiteRoot $websiteInfo.DeployPath

	# Start Portal Service
	Start-Service -Name "Cireson ConfigMgr Portal Hosting Service"
}
