$query = @"
resources
| where type == 'microsoft.compute/virtualmachines'
| order by name asc
"@

$results = $null
$queryResult = $null
$pageSize = 2
$skip = 0


do {
    if ($skip -eq 0){
        $queryResult = Search-AzGraph -Query $query -First $pageSize
    }
    else {
        $queryResult = Search-AzGraph -Query $query -First $pageSize -Skip $skip
    }
    #$results | Format-Table name # Process or output your results here
    $queryResult | ft name
    $results += $queryResult

    $skip += $pageSize
} while ($queryResult.Count -eq $pageSize)

$results | Format-Table name # Process or output your results here