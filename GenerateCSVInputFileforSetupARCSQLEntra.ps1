param (
    [Parameter(Mandatory = $true)] [string] $applicationName,
    [Parameter(Mandatory = $true)] [string] $keyVaultCertificateName,
    [Parameter(Mandatory = $true)] [string] $keyVaultName,
    [Parameter(Mandatory = $true)] [string] $resourceGroupName,
    [Parameter(Mandatory = $true)] [string] $adminAccountName,
    [int] $adminAccountType,
    [string] $tenantId,
    [string] $subscriptionId
)

$query = @"
resources
| where type == 'microsoft.azurearcdata/sqlserverinstances'
| extend Version = tostring(properties.version)
| extend Edition = tostring(properties.edition)
| extend containerId = tolower(tostring (properties.containerResourceId))
| where Version == "SQL Server 2022"
| where isnotempty(containerId)
| extend SQL_instance = tostring(properties.instanceName)
| extend SQL_Service_Type = tostring(properties.serviceType)
| where SQL_Service_Type == "Engine"
| join kind=inner (
    resources
    | where type == "microsoft.hybridcompute/machines"
    | extend machineId = tolower(tostring(id)), Machine_name = name
)on `$left.containerId == `$right.machineId
| join kind=inner(
    resources
    | where type == tolower('Microsoft.HybridCompute/machines/extensions')
    | where name == 'WindowsAgent.SqlServer'
    | mv-expand with_itemindex = i properties.settings.AzureAD
    | extend AAD_SQL_instanceName = tostring(properties_settings_AzureAD.instanceName), aadkeyVaultCertificateName = properties_settings_AzureAD.aadkeyVaultCertificateName, appRegistrationName = properties_settings_AzureAD.appRegistrationName, azureCertSecretId = properties_settings_AzureAD.azureCertSecretId, adminLoginName = properties_settings_AzureAD.adminLoginName, adminLoginType = properties_settings_AzureAD.adminLoginType, ext_Machine_Name = tostring(split(id,"/",8)[0])
    | where isempty(AAD_SQL_instanceName) or isnull(AAD_SQL_instanceName)
)on `$left.Machine_name == `$right.ext_Machine_Name
| order by Machine_name asc
"@

$TemplateObject = New-Object PSObject | Select-Object applicationName,keyVaultCertificateName,keyVaultName,machineName,resourceGroupName,adminAccountName,instanceName,adminAccountType,tenantId,subscriptionId
# Need to page through the results to get all instances
# skip entra time
#$machineInstances = Search-AzGraph -Query $query

$machineInstances = $null
$queryResult = $null
$pageSize = 100
$skip = 0

do {
    if ($skip -eq 0){
        $queryResult = Search-AzGraph -Query $query -First $pageSize
    }
    else {
        $queryResult = Search-AzGraph -Query $query -First $pageSize -Skip $skip
    }
    $machineInstances += $queryResult
    $skip += $pageSize
} while ($queryResult.Count -eq $pageSize)

$csvArray = @()

foreach ($machineInstance in $machineInstances) {
    $wmachineInstanceobj = $TemplateObject | Select-Object *
    $wmachineInstanceobj.applicationName = $applicationName
    $wmachineInstanceobj.keyVaultCertificateName = $keyVaultCertificateName
    $wmachineInstanceobj.keyVaultName = $keyVaultName
    $wmachineInstanceobj.machineName = $machineInstance.Machine_name
    $wmachineInstanceobj.resourceGroupName = $resourceGroupName
    $wmachineInstanceobj.adminAccountName = $adminAccountName
    $wmachineInstanceobj.instanceName = $machineInstance.SQL_instance
    $wmachineInstanceobj.adminAccountType = $adminAccountType
    $wmachineInstanceobj.tenantId = $tenantId
    $wmachineInstanceobj.subscriptionId = $subscriptionId

    $csvArray += $wmachineInstanceobj
}
$date = Get-Date -Format "yyyyMMdd-HHmmss"
$csvArray | Export-Csv -Path "SQLInstanceList-$date.csv" -NoTypeInformation -UseQuotes AsNeeded

#./buildCSVsqlInstances.ps1 -applicationName "xxxxx" -keyVaultCertificateName "xxxxx" -keyVaultName "XXXXX" -resourceGroupName "XXXXXX" -adminAccountName "XXXXX" -adminAccountType 1 -tenantId "xxxxxx" -subscriptionId "xxxxxx"