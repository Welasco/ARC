$date = Get-Date -Format "yyyyMMdd-HHmmss"
#Start-Transcript -Path "transcript-$dateFile.log"
$transcriptPath = "Transcript-$date.log"

# Read the CSV file
$csvData = Import-Csv -Path "SQLInstanceList.csv"
foreach ($param in $csvData) {
    Write-OutPut "Processing Instance $($param.instanceName)"
    .\new-arc-sql.ps1 -applicationName $param.applicationName -keyVaultCertificateName $param.keyVaultCertificateName -keyVaultName $param.keyVaultName -machineName $param.machineName -resourceGroupName $param.resourceGroupName -adminAccountName $param.adminAccountName -instanceName $param.instanceName -adminAccountType $param.adminAccountType -tenantId $param.tenantId -subscriptionId $param.subscriptionId *> $transcriptPath
}