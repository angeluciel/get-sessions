function ConvertTo-SessionCsv {
    <#
    .SYNOPSIS
    Converts one section of the session report into CSV lines.

    .DESCRIPTION
    Defaults to beautified data. Nested objects and arrays are preserved as
    compact JSON inside CSV cells. Empty sections produce no output.

    .EXAMPLE
    ConvertTo-SessionCsv -Report $body |
        Set-Content -Path '.\reports\beautified.csv' -Encoding utf8

    .EXAMPLE
    ConvertTo-SessionCsv -Report $body -Section 'all-executions' -Delimiter ';' |
        Set-Content -Path '.\reports\all-executions.csv' -Encoding utf8
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Report,

        [ValidateSet('all-executions', 'beautified')]
        [string]$Section = 'beautified',

        [char]$Delimiter = ','
    )

    $sectionData = $Report.$Section

    if ($null -eq $sectionData) {
        throw "The report does not contain the '$Section' section."
    }

    $rows = [System.Collections.Generic.List[object]]::new()
    $columns = [System.Collections.Generic.List[string]]::new()
    $seenColumns = [System.Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )

    foreach ($execution in @($sectionData.data)) {
        if ($null -eq $execution) {
            continue
        }

        $row = [ordered]@{}

        foreach ($property in ([pscustomobject]$execution).PSObject.Properties) {
            $name = $property.Name
            $value = $property.Value

            if ($seenColumns.Add($name)) {
                $columns.Add($name)
            }

            if ($value -is [datetime] -or $value -is [DateTimeOffset]) {
                $value = $value.ToString('o', [cultureinfo]::InvariantCulture)
            }
            elseif (
                $null -ne $value -and (
                    $value -is [pscustomobject] -or
                    (
                        $value -is [System.Collections.IEnumerable] -and
                        $value -isnot [string]
                    )
                )
            ) {
                $value = ConvertTo-Json `
                    -InputObject $value `
                    -Depth 100 `
                    -Compress `
                    -WarningAction Stop
            }

            $row[$name] = $value
        }

        $rows.Add($row)
    }

    if ($rows.Count -eq 0) {
        return
    }

    # Include fields found in later executions, not just the first record.
    $csvRows = foreach ($row in $rows) {
        $record = [ordered]@{}

        foreach ($column in $columns) {
            $record[$column] = $row[$column]
        }

        [pscustomobject]$record
    }

    $csvRows | Microsoft.PowerShell.Utility\ConvertTo-Csv `
        -Delimiter $Delimiter `
        -NoTypeInformation
}