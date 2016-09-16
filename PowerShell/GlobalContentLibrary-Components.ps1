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

function Create-ContainedDatabseUser(
    [string]$sqlServer,
    [string]$sqlDatabase,
    [string]$sqlUserName,
    [string]$sqlPassword,
    [string]$sqlServiceUserName,
    [string]$sqlServiceUserPassword
){
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