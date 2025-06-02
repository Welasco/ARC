param (
    [Parameter(mandatory = $true)] $applicationName,
    [Parameter(mandatory = $true)] $certSubjectName,
    [Parameter(mandatory = $true)] $keyVaultName,
    [Parameter(mandatory = $true)] $machineName,
    [Parameter(mandatory = $true)] $resourceGroupName,
    [Parameter(mandatory = $true)] $adminAccountName,
    $instanceName,
    $tenantId,
    $subscriptionId
)

Import-Module Az.Accounts
Import-Module Az.ConnectedMachine
Import-Module Az.KeyVault
Import-Module Az.Resources

# Constants
#
$NUMRETRIES = 60

# Check parameters
#
if ([string]::IsNullOrEmpty($instanceName)) {
    Write-Host "Warning: SQL Instance name (-instanceName) not provided. Default of MSSQLSERVER will be used"
    $instanceName = "MSSQLSERVER"
}

$tenantIdArgument = ""

if ([string]::IsNullOrEmpty($tenantId)) {
    Write-Host "Warning: Tenant ID (-tenantId) not supplied to the script, so default tenant is being used"
}
else {
    $tenantIdArgument = "-TenantId '" + $tenantId + "'"
}

$subscriptionIdArgument = ""

if ([string]::IsNullOrEmpty($subscriptionId)) {
    Write-Host "Warning: Subscription ID (-subscriptionId) not supplied to the script, so default subscription is being used"
}
else {
    $subscriptionIdArgument = "-SubscriptionId '" + $subscriptionId + "'"
}

# Login
#
try {
    $loginRes = Invoke-Expression -Command ("Connect-AzAccount " + $tenantIdArgument + " " + $subscriptionIdArgument + " -ErrorAction stop -UseDeviceAuthentication")
}
catch {
    Write-Error $_
    Write-Error "Failed to login to Azure. Script can not continue"
    exit 1
}

# Get subscription ID
#
if ([string]::IsNullOrEmpty($subscriptionId)) {
    $context = Get-AzContext

    if ($context) {
        if ($context.Name -Match "[^(]+\(([^)]{36})\)") {
            if ($Matches[1]) {
                $subscriptionId = $Matches[1]
            }
        }
    }
}

if ([string]::IsNullOrEmpty($subscriptionId)) {
    Write-Error "Failed to find default subscription"
    exit 1
}

# Check AKV path exists
#
$keyVault = Get-AzKeyVault -VaultName $keyVaultName

if (!$keyVault) {
    Write-Error "Supplied key vault was not found in the subscription. Please specify an existing key vault"
    exit 1
}

# Check certificate doesn't exist
#
$cert = Get-AzKeyVaultCertificate -VaultName $keyVaultName -Name $certSubjectName

if ($cert) {
    Write-Error "Certificate $certSubjectName already exists"
    exit 1
}

# Check app registration doesn't exist
#
$application = Get-AzADApplication -DisplayName $applicationName

if ($application) {
    Write-Error "Application $applicationName already exists"
    exit 1
}

# Check Arc SQL instance is valid
#
$arcInstance = Get-AzConnectedMachineExtension -SubscriptionId $subscriptionId -MachineName $machineName -ResourceGroupName $resourceGroupName -Name "WindowsAgent.SqlServer"

if (!$arcInstance) {
    Write-Error "Could not find a SQL Server Arc instance in subscription '$subscriptionId' and resource group '$resourceGroupName' with name '$machineName'"
    exit 1
}

# Check if admin account exists
#
$adminAccount = Get-AzADUser -UserPrincipalName $adminAccountName
$adminAccountType = 0

if (!$adminAccount) {
    # Check for guest user
    #
    $adminAccount = Get-AzADUser -Mail $adminAccountName

    if (!$adminAccount) {
        $adminAccount = Get-AzADGroup -DisplayName $adminAccountName

        if (!$adminAccount) {
            $adminAccount = Get-AzADServicePrincipal -DisplayName $adminAccountName
        }
        else {
            $adminAccountType = 1
        }
    }
}

if ($adminAccount) {
    if ($adminAccount.Length -gt 1) {
        Write-Error "Multiple accounts with found with name $adminAccountName"
        exit 1
    }

    $adminAccountSid = $adminAccount.Id
}
else {
    Write-Error "Could not find an account with name $adminAccountName"
    exit 1
}

# Create certificate in AKV
#
$Policy = New-AzKeyVaultCertificatePolicy -SecretContentType "application/x-pkcs12" -SubjectName "CN=$certSubjectName" -IssuerName "Self" -ValidityInMonths 12 -ReuseKeyOnRenewal

try {
    $addCertRes = Add-AzKeyVaultCertificate -VaultName $keyVaultName -Name $certSubjectName -CertificatePolicy $Policy -ErrorAction stop
}
catch {
    Write-Error $_
    Write-Error "Certificate $certSubjectName could not be created"
    exit 1
}

for (($i = 0); $i -lt $NUMRETRIES -and (!$cert -or !$cert.enabled); $i++) {
    $cert = Get-AzKeyVaultCertificate -VaultName $keyVaultName -Name $certSubjectName

    if (!$cert -or !$cert.enabled) {
        Start-Sleep -Seconds 5
    }
}

if (!$cert) {
    Write-Error "Certificate $certSubjectName could not be created"
    exit 1
}

# Allow Arc to access AKV
#
$arcServicePrincipal = Get-AzADServicePrincipal -DisplayName $machineName

if ($arcServicePrincipal -and ![string]::IsNullOrEmpty($arcServicePrincipal.Id)) {
    try {
        Set-AzKeyVaultAccessPolicy -VaultName $keyVaultName -ObjectId $arcServicePrincipal.Id -PermissionsToSecrets Get, List -PermissionsToCertificates Get, List
    }
    catch {
        Write-Error $_
        Write-Host "Warning: Could not find the identity of the Azure extension for SQL Server and thus, could not add permissions for the Arc process to read from AKV. Ensure the Arc identity has the required permissions to read from AKV."
    }
}
else {
    Write-Host "Warning: Could not find the identity of the Azure extension for SQL Server and thus, could not add permissions for the Arc process to read from AKV. Ensure the Arc identity has the required permissions to read from AKV."
}

# Create an Azure AD application
#
$application = New-AzADApplication -DisplayName $applicationName

if (!$application) {
    Write-Error "Application could not be created"
    exit 1
}

# Set perms on app registration
#
Add-AzADAppPermission -ObjectId $application.Id -ApiId 00000003-0000-0000-c000-000000000000 -PermissionId c79f8feb-a9db-4090-85f9-90d820caa0eb # Delegated Application.Read.All
Add-AzADAppPermission -ObjectId $application.Id -ApiId 00000003-0000-0000-c000-000000000000 -PermissionId 0e263e50-5827-48a4-b97c-d940288653c7 # Delegated Directory.AccessAsUser.All
Add-AzADAppPermission -ObjectId $application.Id -ApiId 00000003-0000-0000-c000-000000000000 -PermissionId 7ab1d382-f21e-4acd-a863-ba3e13f7da61 -Type Role # Application Directory.Read.All
Add-AzADAppPermission -ObjectId $application.Id -ApiId 00000003-0000-0000-c000-000000000000 -PermissionId 5f8c59db-677d-491f-a6b8-5f174b11ec1d # Delegated Group.Read.All
Add-AzADAppPermission -ObjectId $application.Id -ApiId 00000003-0000-0000-c000-000000000000 -PermissionId a154be20-db9c-4678-8ab7-66f6cc099a59 # Delegated User.Read.All

# Upload cert to Azure AD
#
try {
    $base64Cert = [System.Convert]::ToBase64String($cert.Certificate.GetRawCertData())
    New-AzADAppCredential -ApplicationObject $application -CertValue $base64Cert -EndDate $cert.Certificate.NotAfter -StartDate $cert.Certificate.NotBefore -ErrorAction stop
}
catch {
    Write-Error $_
    Write-Error "Failed to add certificate to app registration"
    exit 1
}

# Remove the version from the secret ID if present
#
$secretId = $cert.SecretId

if ($secretId -Match "(https:\/\/[^\/]+\/secrets\/[^\/]+)(\/.*){0,1}$") {
    if ($Matches[1]) {
        $secretId = $Matches[1]
    }
}

# Create the settings object to write to the Azure extension for SQL Server
#
$instanceSettings = @{
    instanceName             = $instanceName
    adminLoginName           = $adminAccountName
    adminLoginSid            = $adminAccountSid
    azureCertSecretId        = $secretId.replace(":443", "")
    azureCertUri             = $cert.Id.replace(":443", "")
    azureKeyVaultResourceUID = $keyVault.ResourceId
    managedCertSetting       = "CUSTOMER MANAGED CERT"
    managedAppSetting        = "CUSTOMER MANAGED APP"
    appRegistrationName      = $application.DisplayName
    appRegistrationSid       = $application.AppId
    tenantId                 = $tenantId
    aadCertSubjectName       = $certSubjectName
    adminLoginType           = $adminAccountType
}

$arcInstance = Get-AzConnectedMachineExtension -SubscriptionId $subscriptionId -MachineName $machineName -ResourceGroupName $resourceGroupName -Name "WindowsAgent.SqlServer"

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
        $aadSettings[$instanceIndex] = $instanceSettings
    }
    else {
        $aadSettings += $instanceSettings
    }
}
else {
    $aadSettings = , $instanceSettings
}

Write-Host "Writing Microsoft Entra setting to SQL Server Arc Extension. This may take several minutes..."

# Push settings to Arc
#
try {

    #set the Entra ID / AzureAD setting in the hash table
    $SettingsToConfigure = @{
        AzureAD = $aadSettings
    }

    #add any non-AzureAD key value pairs back to the hashtable
    $keys = $arcInstance.Setting.Keys | where-object { $_ -notin ("AzureAD") }
    foreach ($key in $keys) {
        $SettingsToConfigure.$key = $arcInstance.Setting["$key"]
    }

    #Issue the update of the updated settings
    Update-AzConnectedMachineExtension -MachineName $machineName -Name "WindowsAgent.SqlServer" -ResourceGroupName $resourceGroupName -Setting $SettingsToConfigure
}
catch {
    Write-Error $_
    Write-Error "Failed to write settings to Arc host"
    exit 1
}

Write-Output "Success"