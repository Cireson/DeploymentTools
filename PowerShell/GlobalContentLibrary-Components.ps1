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

function Create-ContainedDatabaseUser([string]$sqlServer, [string]$sqlDatabase, [string]$sqlUserName, [string]$sqlPassword, [string]$sqlServiceUserName, [string]$sqlServiceUserPassword){
    $connectionString = "Server=tcp:$sqlServer.database.windows.net,1433;Data Source=$sqlServer.database.windows.net;Initial Catalog=$sqlDatabase;Persist Security Info=False;User ID=$sqlUserName;Password=$sqlPassword;Encrypt=True;Connection Timeout=30;"
    $connection = New-Object -TypeName System.Data.SqlClient.SqlConnection($connectionString)
    $query = "SELECT result = 1 FROM sys.database_principals WHERE authentication_type = 2 AND name = 'gclservice'"
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