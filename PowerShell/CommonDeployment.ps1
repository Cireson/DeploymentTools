function Ensure-EmptyRemoteDirectoryExists($session, $directory){
	$ErrorActionPreference = "Stop"

	Invoke-Command -Session $session -ScriptBlock{ 
		$ErrorActionPreference = "Stop"
		$onDirectory = $Using:directory

		if((Test-Path $onDirectory) -ne $true){
			$result = New-Item $onDirectory -ItemType Directory
			Write-Host "Created $onDirectory" -ForegroundColor Green
		}else{
			Remove-Item -Path "$onDirectory\*" -Recurse -Force
			Write-Host "Cleaned $onDirectory" -ForegroundColor Yellow
		}
	}
}

function Remove-RunningService([string]$serviceName){
    $service = Get-WmiObject -Class Win32_Service -Filter "Name='$serviceName'"
    if($service -ne $null){
        "********Service $serviceName Found********"
        $service

        $complete = $false

        if($service.Status -eq "Degraded"){
            "********Service Degraded, Stopping Process********"
            Stop-Process -processname "Cireson.Platform.Host" -Force
        }
        elseif($service.State -ne "Stopped"){
            "********Stopping $serviceName  Service********"
            $failed = 0
        
            while($complete -ne $true -and $failed -lt 5){
               try{
                 $result = Stop-Service $serviceName
                 $complete = $true
               }catch{
                 $complete = $false
                 $failed += 1
               }
            }

            if($complete -eq $false){
                throw "Unable to stop $serviceName"
            }
        }

        "********Removing $serviceName Service********"
        "ReturnValue 0 - The request was accepted"
        "ReturnValue 16 - This service is being removed from the system."
        "More: https://msdn.microsoft.com/en-us/library/aa389960(v=vs.85).aspx"
        $result = $service.delete()
        $result
 
    }else{
        "********$serviceName not Found********"
    }
}

function Create-InboundFirewallRule($displayName, $port){
    $rule = Get-NetFirewallRule | Where-Object {$_.DisplayName -eq $displayName}
    if($rule -eq $null){
        New-NetFirewallRule -DisplayName $displayName -Direction Inbound -Action Allow -Protocol "TCP" -LocalPort $port
        "$displayName Rule Created"
    }else{
        Set-NetFirewallRule -DisplayName $displayName -Direction Inbound -Action Allow -Protocol "TCP" -LocalPort $port
        "$displayName Rule Already Exists, Updated"
    }
}

function AddUserToGroup([string]$groupName,[string]$user){
    $Group = [ADSI]"WinNT://localhost/$groupName,group"   
    $Group.Add("WinNT://$user,user")
}
 
function Create-PlatformConnectionString([string]$sqlServer, [string]$sqlDatabase, [string]$sqlUserName, [string]$sqlPassword){
    return "Server=tcp:$sqlServer.database.windows.net,1433;Data Source=$sqlServer.database.windows.net;Initial Catalog=$sqlDatabase;Persist Security Info=False;User ID=$sqlUserName;Password=$sqlPassword;Encrypt=True;Connection Timeout=30;"
}

function Create-ContainedDatabaseUser([string]$connectionString, [string]$sqlServiceUserName, [string]$sqlServiceUserPassword){
    $connection = New-Object -TypeName System.Data.SqlClient.SqlConnection($connectionString)
    $query = "SELECT result = 1 FROM sys.database_principals WHERE authentication_type = 2 AND name = '$sqlServiceUserName'"
    $command = New-Object -TypeName System.Data.SqlClient.SqlCommand($query, $connection)
    $connection.Open()
    $result = $command.ExecuteScalar()

    if($result -eq 1){
        "********User Already Exists********"
    }else{
        "********Creating Sql User********"
        $query = "Create user $sqlServiceUserName with password = '$sqlServiceUserPassword'; ALTER AUTHORIZATION ON SCHEMA::[db_owner] TO [$sqlServiceUserName]; ALTER ROLE [db_owner] ADD MEMBER [$sqlServiceUserName];"
        $command = New-Object -TypeName System.Data.SqlClient.SqlCommand($query, $connection)
        $command.ExecuteNonQuery() #Other methods are available if you want to get the return value of your query.
    }

    $connection.Close()
}

function Create-TargetDirectory($rootDirectory, $targetVersion){
    $targetDirectory = "$rootDirectory\$targetVersion"
    if((Test-Path $targetDirectory) -ne $true){
        $newItem = New-Item $targetDirectory -type directory
        Write-Host "Created $targetDirectory"    
    }else{
        Write-Host "$targetDirectory Already Exists"
    }

    return $targetDirectory
}

function Download-Platform($baseDirectory, $platformVersion, $targetDirectory){
    $platformBaseDirectory = "$baseDirectory\platform"
      if((Test-Path $platformBaseDirectory) -ne $true){
          New-Item $platformBaseDirectory -type directory    
      }
  
    $platform = "$platformBaseDirectory\$platformVersion"

    if((Test-Path $platform) -ne $true){

        New-Item $platform -type directory
  
        $url = "https://www.nuget.org/api/v2/package/Cireson.Platform.Core.Host/$platformVersion"
        Write-Output "Url: $url"
  
        $file = "$platform\platform.zip"
        Write-Output "File: $file"

         $webclient = New-Object System.Net.WebClient
         $webclient.DownloadFile($url,$file)

        "Unzipping $file"
        Unzip-File $file "$platform\PackageContents"

        "Removing $file"
        Remove-Item $file -recurse -force

        "Copying Host Zip to $platform"
        Copy-Item -Path "$platform\PackageContents\content\PlatformRuntime\Cireson.Platform.Host.zip" -Destination "$platform\Cireson.Platform.Host.zip"

        "Remove Package Contents"
        Remove-Item "$platform\PackageContents" -Recurse -Force

        "Unzipping Platform Host"
        Unzip-File "$platform\Cireson.Platform.Host.zip" $platform

        "Remove Platform Host Zip"
        Remove-Item "$platform\Cireson.Platform.Host.zip"

        "Platform Host $platformVersion Downloaded"
        "Find at: $platform"
      }else{
            "Platform Host $platformVersion Already Exists"
      }

      "Copying Platform Version $platformVersion to $targetDirectory"
      Copy-Item -Path "$platform\*.*" -Destination $targetDirectory
      "Contents of $targetDirectory"
      get-childitem "$targetDirectory"
}

function Update-PlatformConfig($targetDirectory, $connectionString){
    $configPath = "$targetDirectory\Cireson.Platform.Host.exe.config"
    [xml]$configFile = Get-Content $configPath
    $cstring = (($configFile.configuration.connectionStrings).add | where {$_.name -eq "CiresonDatabase"})
    $cstring.connectionString = $connectionString
    $configFile.Save($configPath) 
}

function Start-RemotePlatform($session, $deploymentVariables){
	Write-Host "Begin Start-RemotePlatform" -ForegroundColor Green

	Invoke-Command -Session $session -ScriptBlock{ 
        $ErrorActionPreference = "Stop"
        $onDeploymentVariables = $Using:deploymentVariables

        $productDirectory = $onDeploymentVariables.productRoot
		$deployedVersion = $onDeploymentVariables.targetVersion
		$serviceName = $onDeploymentVariables.serviceName
		$serviceUserName = $onDeploymentVariables.serviceUserName
		$serviceUserPassword = $onDeploymentVariables.serviceUserPassword

		$platform = "$productDirectory\$deployedVersion\Cireson.Platform.Host.exe"

		if((Test-Path $platform) -eq $false){
			throw "Platform not found at $platform"
		}else{
			Write-Host "Platform found at $platform" -ForegroundColor Green
		}

		Write-Host "Starting Platfrom at $platform" -ForegroundColor Green
		start-process $platform -ArgumentList "-install", "-sn", $serviceName, "-usr", ".\$serviceUserName", "-pwd", $serviceUserPassword, "-worker" -wait
    }

	Write-Host "End Start-RemotePlatform" -ForegroundColor Green
}

function Copy-NuGets($resourceGroupName, $storageAccountName, $productRoot, $tempContainerName, $session, $agentReleaseDirectory, $buildDefinitionName){
	Import-Module -Name Azure

	$storageAccount = Get-AzureRmStorageAccount -ResourceGroupName $resourceGroupName| Where-Object{ $_.StorageAccountName -eq $storageAccountName}
	"----Storage Account----"
	$storageAccount
	$storageAccountKey = Get-AzureRmStorageAccountKey -Name $storageAccount.StorageAccountName -ResourceGroupName $resourceGroupName
	$storageContext = New-AzureStorageContext -StorageAccountName $storageAccount.StorageAccountName -StorageAccountKey $storageAccountKey.Key1
	"----Storage Context----"
	$storageContext

	$version = $env:BUILD_BUILDNUMBER
	
	#$(System.DefaultWorkingDirectory)/Connectors.ConfigMgr (CI - integration)/drop/Cireson.AssetManagement.Connectors.ConfigMgr.Core.0.1.0-rc0051.nupkg
	$nuGets = Get-ChildItem "$agentReleaseDirectory/$buildDefinitionName/drop/" | Where-Object {$_.Name.EndsWith(".nupkg")}

	foreach($nuGet in $nuGets){
		"----Copying $nuGet.FullName to Temp Azure Storage----"
		Set-AzureStorageBlobContent -File $nuGet.FullName  -Container $tempContainerName -Blob $nuGet.Name -Context $storageContext -Force

		$blobUri = $storageContext.BlobEndPoint + "$tempContainerName/" + $nuGet.Name
	
		Invoke-Command -Session $Session -ScriptBlock{ 
			$onBlobUri = $Using:blobUri
			$onFileName = $Using:nuget.Name
			$onVersion = $Using:version

			"Blob URI: $onBlobUri"
			"File Name: $onFileName"
			"Version: $onVersion"

			$commonApplicationData = [Environment]::GetFolderPath("CommonApplicationData")
			$platformHostCpexData = "$commonApplicationData\Cireson.Platform.Host\InstallableCpex"
			Write-Output "Remove All Files From $platformHostCpexData"	
			Remove-Item -Path "$platformHostCpexData\*.*" -recurse -force 
			
			Write-Output "Download $onFileName from Azure Storage"
			$file = "$platformHostCpexData\$onFileName"
			$webclient = New-Object System.Net.WebClient
			$webclient.DownloadFile($onBlobUri, $file)
			Write-Output "`tSaved to $file"
		}

		"----Remove Blob from Temp Azure Storage----"
		Remove-AzureStorageBlob -Blob $nuGet.Name -Container $tempContainerName -Context $storageContext
	}
}

function Create-ServiceUser($serviceUserName, $servicePassword){
  $user = Get-WmiObject -Class Win32_UserAccount -Namespace "root\cimv2" -Filter "LocalAccount='$True'" | Where-Object { $_.Name -eq $serviceUserName}
  if($user -eq $null){
    "Creating User $serviceUserName($servicePassword)"
    NET USER $serviceUserName $servicePassword /ADD
  }else{
    "User $serviceUserName Already Exists"
  }

  Grant-UserRight $serviceUserName SeServiceLogonRight

  $group = get-wmiobject win32_group -filter "name='Administrators'"
  $user = $group.GetRelated("win32_useraccount") | Where-Object { $_.Name -eq $serviceUserName}
  if($user -eq $null){
    AddUserToGroup -groupName "Administrators" -user $serviceUserName
    "----Added $serviceUserName to Administrators Group----"
  }else{
    "----$serviceUserName Already a Member of Administrators Group----"
  }
}

function Create-DestinationDirectories([string]$root, [string]$targetVersion){
    $commonApplicationData = [Environment]::GetFolderPath("CommonApplicationData")
    $platformHostCpexData = "$commonApplicationData\Cireson.Platform.Host\InstallableCpex"
    if((Test-Path $platformHostCpexData) -ne $true){
        New-Item $platformHostCpexData -ItemType Directory
    }
    
    $targetDirectory = "$root\$targetVersion"

    if((Test-Path $root) -ne $true){
        New-Item $root -type directory
    }else{
        Write-Output "$root Exists"
    }

    if((Test-Path $targetDirectory) -ne $true){
        New-Item $targetDirectory -type directory
    }else{
        Write-Output "$targetDirectory Exists"
    }
}

function Push-RemoteDeploymentScripts($session, $uris, $remotePowerShellLocation){
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