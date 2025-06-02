param (
    [Parameter(Mandatory = $true)] [string] $machineName,
    [Parameter(Mandatory = $true)] [string] $resourceGroupName,
    [Parameter(Mandatory = $true)] [string] $instanceName,
    [string] $tenantId,
    [string] $subscriptionId
)

$dateFile = Get-Date -Format "yyyyMMdd-HHmmss"
#Start-Transcript -Path "transcript-$dateFile.log"
$filePath = "Remove-$instanceName-$dateFile.log"

function AddLog ($message) {
    Add-Content -Path $filePath -Value "$(Get-Date): $message"
    Write-Output "$(Get-Date): $message"
}

# Import required Azure PowerShell modules
AddLog "Importing Azure PowerShell modules"
Import-Module Az.Accounts
Import-Module Az.ConnectedMachine
Import-Module Az.KeyVault
Import-Module Az.Resources

#Input parameters

# $subscriptionId="<subscriptionId>"
# $tenantId="<tenantId>"
# $machineName="<machineName>"  # hostname
# $instanceName="<instanceName>"  # SQL Server is define as `machine_name\instance_name $resourceGroupName="<resourceGroupName>"
# $keyVaultName="<keyVaultName>"
# $keyVaultCertificateName="<keyVaultCertificateName>" # Your existing certificate name
# $applicationName="<applicationName>" # Your existing application name
# $adminAccountName="<adminAccountName>"
# $adminAccountSid="<adminID>"  # Use object ID for the Microsoft Entra user and group, or client ID for the Microsoft Entra application
# $adminAccountType= 0  # 0 – for Microsoft Entra user and application, 1 for Microsoft Entra group

# Authenticate to Azure
AddLog "Authenticating to Azure"
try {
    $context = Get-AzContext
    if (-not $context) {
        AddLog "Azure Powershell context not found. Logging in using device code authentication."
        Connect-AzAccount -TenantId $tenantId -SubscriptionId $subscriptionId -ErrorAction Stop -UseDeviceAuthentication
    }
    else {
        if ((-not [string]::IsNullOrEmpty($tenantId)) -or (-not [string]::IsNullOrEmpty($subscriptionId))) {
            if ($context.Tenant.Id -ne $tenantId -or $context.Subscription.Id -ne $subscriptionId) {
                AddLog "Azure Powershell context found but does not match the provided tenantId and subscriptionId. Logging in using device code authentication."
                Connect-AzAccount -TenantId $tenantId -SubscriptionId $subscriptionId -ErrorAction Stop -UseDeviceAuthentication
            }
        }
        AddLog "Azure login:"
        $context | Format-List
    }
    #Connect-AzAccount -TenantId $tenantId -SubscriptionId $subscriptionId -ErrorAction Stop -UseDeviceAuthentication
}
catch {
    AddLog "Azure login failed. Exiting."
    AddLog "Error: $($_.Exception.Message)"
    exit 1
}

# Retrieve Subscription ID if not provided
if (-not $subscriptionId) {
    AddLog "Subscription ID not provided. Retrieving from Azure context."
    $context = Get-AzContext
    if ($context -and $context.Subscription) {
        AddLog "Subscription ID found: $($context.Subscription.Id)"
        $subscriptionId = $context.Subscription.Id
    }
    else {
        AddLog "Error: Subscription ID not found. Exiting."
        exit 1
    }
}

# Retrieve tenantId if not provided
if (-not $tenantId) {
    AddLog "TenantId not provided. Retrieving from Azure context."
    $context = Get-AzContext
    if ($context -and $context.Tenant) {
        AddLog "TenantId found: $($context.Tenant.Id)"
        $tenantId = $context.Tenant.Id
    }
    else {
        AddLog "Error: TenantId ID not found. Exiting."
        exit 1
    }
}

# Check parameter $instanceName
if ([string]::IsNullOrEmpty($instanceName)) {
    AddLog "Warning: SQL Instance name (-instanceName) not provided. Default of MSSQLSERVER will be used"
    $instanceName = "MSSQLSERVER"
}


# Retrieve the current settings from the Arc extension
AddLog "Retrieving current settings from the SQL Server Arc extension"
$arcInstance = Get-AzConnectedMachineExtension -SubscriptionId $subscriptionId -MachineName $machineName -ResourceGroupName $resourceGroupName -Name "WindowsAgent.SqlServer"

# Update the settings with the new Microsoft Entra settings
AddLog "Updating Microsoft Entra settings in the SQL Server Arc extension"
if ($arcInstance.Setting.AdditionalProperties.AzureAD) {
    $aadSettings = $arcInstance.Setting.AdditionalProperties.AzureAD
    $instanceFound = $false
    $instanceNameLower = $instanceName.ToLower()
    $instanceIndex = 0

    for (($i = 0); $i -lt $aadSettings.Length; $i++) {
        if ($aadSettings[$i].instanceName.ToLower() -eq $instanceNameLower) {
            $instanceIndex = $i
            $instanceFound = $true
            break
        }
    }

    if ($instanceFound) {
        if($aadSettings[$instanceIndex].instanceName -eq $instanceName) {
            AddLog "Found SQL instance to be removed: $instanceName"
        }
        else {
            AddLog "Adding non related SQL Instance"
            $aadSettings[$instanceIndex] = $instanceSettings

        }
        #$aadSettings[$instanceIndex] = $instanceSettings
    }
    else {
        $aadSettings += $instanceSettings
    }

}
else {
    $aadSettings = , $instanceSettings
}

AddLog "Writing Microsoft Entra setting to SQL Server Arc Extension. This may take several minutes..."
#$configaadSettings = $aadSettings | where{$_.instanceName -ne "MSSQLSERVER"}
# Push settings to Arc
#
try {
    #set the Entra ID / AzureAD setting in the hash table
    $SettingsToConfigure = @{
        AzureAD = {}
        #AzureAD = $configaadSettings
    }

    # $SettingsToConfigure = @{
    #     AzureAD = $aadSettings
    # }

    #add any non-AzureAD key value pairs back to the hashtable
    $keys = $arcInstance.Setting.Keys | where-object { $_ -notin ("AzureAD") }
    foreach ($key in $keys) {
        $SettingsToConfigure.$key = $arcInstance.Setting["$key"]
    }

    #Issue the update of the updated settings
    Update-AzConnectedMachineExtension -MachineName $machineName -Name "WindowsAgent.SqlServer" -ResourceGroupName $resourceGroupName -Setting $SettingsToConfigure

}
catch {
    AddLog "Failed to write settings to Arc host"
    AddLog "Error: $($_.Exception.Message)"
    exit 1
}

AddLog "Success"