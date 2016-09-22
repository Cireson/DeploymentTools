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
			$onWebUiVersion = $Using:webUiVersion
			$onExtensionCache = $Using:extensionCache

			"Blob URI: $onBlobUri"
			"File Name: $onFileName"
			"Version: $onVersion"
			"WebUiVersion: $onWebUiVersion"

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