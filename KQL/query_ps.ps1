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
"@

$queryDelta = @"
resources
| where type == 'microsoft.azurearcdata/sqlserverinstances'
| extend Version = tostring(properties.version)
| extend Edition = tostring(properties.edition)
| extend containerId = tolower(tostring (properties.containerResourceId))
| where Version == "SQL Server 2022"
//| where Edition in ("Enterprise", "Standard")
| where isnotempty(containerId)
| extend SQL_instance = tostring(properties.instanceName)
//| project containerId, SQL_instance, Version, Edition
| join kind=inner (
    resources
    | where type == "microsoft.hybridcompute/machines"
    | extend machineId = tolower(tostring(id)), Machine_name = name
    //| project machineId, Machine_name
)on `$left.containerId == `$right.machineId
//| project containerId, SQL_instance, Version, Edition, machineId, Machine_name
//| order by machineId asc
| join kind=inner(
    resources
    | where type == tolower('Microsoft.HybridCompute/machines/extensions')
    | where name == 'WindowsAgent.SqlServer'
    | mv-expand with_itemindex = i properties.settings.AzureAD
    | extend instanceName = tostring(properties_settings_AzureAD.instanceName), aadkeyVaultCertificateName = properties_settings_AzureAD.aadkeyVaultCertificateName, appRegistrationName = properties_settings_AzureAD.appRegistrationName, azureCertSecretId = properties_settings_AzureAD.azureCertSecretId, adminLoginName = properties_settings_AzureAD.adminLoginName, adminLoginType = properties_settings_AzureAD.adminLoginType, ext_Machine_Name = tostring(split(id,"/",8)[0])
    //| project ext_Machine_Name, instanceName, aadkeyVaultCertificateName, appRegistrationName, azureCertSecretId, adminLoginName, adminLoginType
    | where instanceName <> ""
)on `$left.Machine_name == `$right.ext_Machine_Name and `$left.SQL_instance == `$right.instanceName
//| distinct SQL_instance, Version, Edition, Machine_name, location, resourceGroup, subscriptionId, instanceName
"@

$r = Search-AzGraph -Query $queryDelta


############################################################################################

$queryDelta = @"
resources
| where type == tolower('microsoft.azurearcdata/sqlserverinstances')
| extend Version = tostring(properties.version)
| extend Edition = tostring(properties.edition)
| extend containerId = tolower(tostring (properties.containerResourceId))
| where Version == "SQL Server 2022"
//| where Edition in ("Enterprise", "Standard")
| where isnotempty(containerId)
| extend SQL_instance = tostring(properties.instanceName)
//| project containerId, SQL_instance, Version, Edition
| join kind=inner (
    resources
    | where type == tolower()"microsoft.hybridcompute/machines")
    | extend machineId = tolower(tostring(id)), Machine_name = name
    //| project machineId, Machine_name
)on `$left.containerId == `$right.machineId
//| project containerId, SQL_instance, Version, Edition, machineId, Machine_name
//| order by machineId asc
| join kind=inner(
    resources
    | where type == tolower('Microsoft.HybridCompute/machines/extensions')
    | where name == 'WindowsAgent.SqlServer'
    | mv-expand with_itemindex = i properties.settings.AzureAD
    | extend instanceName = tostring(properties_settings_AzureAD.instanceName), aadkeyVaultCertificateName = properties_settings_AzureAD.aadkeyVaultCertificateName, appRegistrationName = properties_settings_AzureAD.appRegistrationName, azureCertSecretId = properties_settings_AzureAD.azureCertSecretId, adminLoginName = properties_settings_AzureAD.adminLoginName, adminLoginType = properties_settings_AzureAD.adminLoginType, ext_Machine_Name = tostring(split(id,"/",8)[0])
    //| project ext_Machine_Name, instanceName, aadkeyVaultCertificateName, appRegistrationName, azureCertSecretId, adminLoginName, adminLoginType
    | where instanceName == ""
)on `$left.Machine_name == `$right.ext_Machine_Name and `$left.SQL_instance == `$right.instanceName
//| distinct SQL_instance, Version, Edition, Machine_name, location, resourceGroup, subscriptionId, instanceName
"@

$r = Search-AzGraph -Query $queryDelta

# need to check if sql is 2022 and if the instance name is empty
$tQuery = @"
resources
| where type == tolower('Microsoft.HybridCompute/machines/extensions')
| where name == 'WindowsAgent.SqlServer'
| mv-expand with_itemindex = i properties.settings.AzureAD
| extend instanceName = tostring(properties_settings_AzureAD.instanceName), aadkeyVaultCertificateName = properties_settings_AzureAD.aadkeyVaultCertificateName, appRegistrationName = properties_settings_AzureAD.appRegistrationName, azureCertSecretId = properties_settings_AzureAD.azureCertSecretId, adminLoginName = properties_settings_AzureAD.adminLoginName, adminLoginType = properties_settings_AzureAD.adminLoginType, ext_Machine_Name = tostring(split(id,"/",8)[0])
//| project ext_Machine_Name, instanceName, aadkeyVaultCertificateName, appRegistrationName, azureCertSecretId, adminLoginName, adminLoginType
| where instanceName == ""
"@

Search-AzGraph -Query $tQuery | ft instanceName, ext_Machine_Name




###########################################################################
$query = @"
resources
| where type == 'microsoft.azurearcdata/sqlserverinstances'
| extend Version = tostring(properties.version)
| extend Edition = tostring(properties.edition)
| extend containerId = tolower(tostring (properties.containerResourceId))
| where Version == "SQL Server 2022"
| where isnotempty(containerId)
| extend SQL_instance = tostring(properties.instanceName)
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

Search-AzGraph -Query $Query | ft instanceName, ext_Machine_Name