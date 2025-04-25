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
| extend Version = properties.version
| extend Edition = properties.edition
| extend containerId = tolower(tostring (properties.containerResourceId))
| where Version == "SQL Server 2022"
//| where Edition in ("Enterprise", "Standard")
| where isnotempty(containerId)
| project containerId, SQL_instance = properties.instanceName, Version, Edition
| join kind=inner (
    resources
    | where type == "microsoft.hybridcompute/machines"
    | extend machineId = tolower(tostring(id))
    | project machineId, Machine_name = name
)on `$left.containerId == `$right.machineId
order by machineId asc
"@

$TemplateObject = New-Object PSObject | Select-Object applicationName,keyVaultCertificateName,keyVaultName,machineName,resourceGroupName,adminAccountName,instanceName,adminAccountType,tenantId,subscriptionId
# Need to page through the results to get all instances
# skip entra time
$machineInstances = Search-AzGraph -Query $query

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