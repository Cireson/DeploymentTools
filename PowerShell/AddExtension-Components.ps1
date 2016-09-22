function Create-DestinationDirectories([string]$root, [string]$targetVersion){
    $commonApplicationData = [Environment]::GetFolderPath("CommonApplicationData")
    $platformHostCpexData = "$commonApplicationData\Cireson.Platform.Host\InstallableCpex"
    if((Test-Path $platformHostCpexData) -ne $true){
        New-Item $platformHostCpexData -ItemType Directory
    }
    
    $gclTarget = "$root\$targetVersion"

    if((Test-Path $root) -ne $true){
        New-Item $root -type directory
    }else{
        Write-Output "$root Exists"
    }

    if((Test-Path $gclTarget) -ne $true){
        New-Item $gclTarget -type directory
    }else{
        Write-Output "$gclTarget Exists"
    }
}

function Create-PlatformConnectionString([string]$sqlServer, [string]$sqlDatabase, [string]$sqlUserName, [string]$sqlPassword){
    return "Server=tcp:$sqlServer.database.windows.net,1433;Data Source=$sqlServer.database.windows.net;Initial Catalog=$sqlDatabase;Persist Security Info=False;User ID=$sqlUserName;Password=$sqlPassword;Encrypt=True;Connection Timeout=30;"
}

function Create-ContainedDatabaseUser([string]$connectionString, [string]$sqlServiceUserName, [string]$sqlServiceUserPassword){
	"connectionString: $connectionString"
	"sqlServiceUserName: $sqlServiceUserName"
	"sqlServiceUserPassword: $sqlServiceUserPassword"

    $connection = New-Object -TypeName System.Data.SqlClient.SqlConnection($connectionString)
    $query = "SELECT result = 1 FROM sys.database_principals WHERE authentication_type = 2 AND name = 'amservice'"
    $command = New-Object -TypeName System.Data.SqlClient.SqlCommand($query, $connection)
    $connection.Open()
    $result = $command.ExecuteScalar()

    if($result -eq 1){
        "********User Already Exists********"
    }else{
        "********Creating Sql User********"
        $query = "Create user $sqlServiceUserName with password = '$sqlServiceUserPassword'; ALTER AUTHORIZATION ON SCHEMA::[db_owner] TO [$sqlServiceUserName]; ALTER ROLE [db_owner] ADD MEMBER [$sqlServiceUserName];"
		"query: $query"
        $command = New-Object -TypeName System.Data.SqlClient.SqlCommand($query, $connection)
        $command.ExecuteNonQuery() #Other methods are available if you want to get the return value of your query.
    }

    $connection.Close()
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

function AddUserToGroup([string]$groupName,[string]$user)
{
    $Group = [ADSI]"WinNT://localhost/$groupName,group"   
    $Group.Add("WinNT://$user,user")
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
	$platform = "$platformBaseDirectory\$platformVersion"

	Write-Output "Create Directory to Store Platform Versions, $platformBaseDirectory"
	if((Test-Path $platformBaseDirectory) -ne $true){
		$result = New-Item $platformBaseDirectory -type directory    
		Write-Output "`tCreated"
	}else{
		Write-Output "`tAlready Exists"
	}
  
    Write-Output "Create Directory to Store Specific Platform Version, $platform"
    if((Test-Path $platform) -ne $true){
		$result = New-Item $platform -type directory
		Write-Output "`tCreated"
	}else{
		Write-Output "`tAlready Exists"
	}
  

	Write-Output "Download Specific Platform Version"
	$url = "https://www.nuget.org/api/v2/package/Cireson.Platform.Core.Host/$platformVersion"
	$file = "$platform\platform.zip"
	if((Test-Path $file) -ne $true){
		Write-Output "`tClean Directory $platform"
		$result = Remove-Item -Path "$platform\*" -Recurse -Force

		Write-Output "`tDownload From: $url"
		Write-Output "`tSave As: $file"

		$webclient = New-Object System.Net.WebClient
		$result = $webclient.DownloadFile($url,$file)

		Write-Output "`tDownload Completed"
	}else{
		Write-Output "`tAlready Downloaded"
	}

	Write-Output "Unzipping $file"
	Unzip-File $file "$platform\PackageContents"

	Write-Output "Removing $file"
	Remove-Item $file -recurse -force

	Write-Output "Copying Host Zip to $platform"
	Copy-Item -Path "$platform\PackageContents\content\PlatformRuntime\Cireson.Platform.Host.zip" -Destination "$platform\Cireson.Platform.Host.zip"

	Write-Output "Remove Package Contents"
	Remove-Item "$platform\PackageContents" -Recurse -Force

	Write-Output "Unzipping Platform Host"
	Unzip-File "$platform\Cireson.Platform.Host.zip" $platform

	Write-Output "Remove Platform Host Zip"
	Remove-Item "$platform\Cireson.Platform.Host.zip"

	Write-Output "Platform Host $platformVersion Downloaded"
	Write-Output "Find at: $platform"
      

	Write-Output "Copying Platform Version $platformVersion to $targetDirectory"
	Copy-Item -Path "$platform\*.*" -Destination $targetDirectory
	Write-Output "Contents of $targetDirectory"
	get-childitem "$targetDirectory"
}

function Update-PlatformConfig($targetDirectory, $connectionString){
    $configPath = "$targetDirectory\Cireson.Platform.Host.exe.config"
    [xml]$configFile = Get-Content $configPath
    $cstring = (($configFile.configuration.connectionStrings).add | where {$_.name -eq "CiresonDatabase"})
    $cstring.connectionString = $connectionString
    $configFile.Save($configPath) 
}