function ConvertTo-SessionReport {
    <#
    .SYNOPSIS
    Preserves executions and produces one presentation row per explicitly linked retry chain.
    Sessions without originalSessionId remain separate and are marked Unlinked.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Sessions
    )

    $allExecutions = @($Sessions | Sort-Object -Property @{
        Expression = { [DateTimeOffset]$_.creationTime }
    }, @{ Expression = { [string]$_.id } })
    $chains = [ordered]@{}

    foreach ($session in $allExecutions) {
        $originalProperty = $session.PSObject.Properties['originalSessionId']
        $originalId = if ($null -ne $originalProperty) { [string]$originalProperty.Value } else { '' }
        $hasLink = -not [string]::IsNullOrWhiteSpace($originalId) -and $originalId -ne [guid]::Empty.ToString()
        $chainId = if ($hasLink) { $originalId } else { [string]$session.id }

        if (-not $chains.Contains($chainId)) {
            $chains[$chainId] = @{
                Linked = $false
                Sessions = [System.Collections.Generic.List[object]]::new()
            }
        }
        $chains[$chainId].Linked = $chains[$chainId].Linked -or $hasLink
        $chains[$chainId].Sessions.Add($session)
    }

    $beautified = @(
        foreach ($chainId in $chains.Keys) {
            $chain = $chains[$chainId]
            $attempts = $chain.Sessions.ToArray()
            $first = $attempts[0]
            $last = $attempts[-1]
            $ids = @($attempts | ForEach-Object { [string]$_.id })
            $hasOriginal = $ids -contains $chainId
            $jobIds = @($attempts | Select-Object -ExpandProperty jobId -Unique)
            if ($jobIds.Count -gt 1) { throw "Chain '$chainId' contains conflicting job IDs." }

            $latestTime = [DateTimeOffset]$last.creationTime
            $tiedLatest = @($attempts | Where-Object { [DateTimeOffset]$_.creationTime -eq $latestTime }).Count -gt 1
            $result = if ($last.result.result) { $last.result.result } else { 'None' }
            $status = if ($last.state -ne 'Stopped') { $last.state }
                elseif ($last.result.isCanceled) { 'Canceled' }
                else { $result }
            if ($tiedLatest) { $status = 'AmbiguousAttemptOrder' }

            [PSCustomObject][ordered]@{
                chainId = $chainId
                sessionId = $last.id
                jobId = $last.jobId
                name = $first.name
                sessionType = $last.sessionType
                platform = $last.platformName
                firstAttemptStart = $first.creationTime
                lastAttemptStart = $last.creationTime
                endTime = if ($last.state -eq 'Stopped' -and $last.endTime -and ([DateTimeOffset]$last.endTime).Year -gt 1) { $last.endTime } else { $null }
                state = $last.state
                result = $result
                status = $status
                message = $last.result.message
                isCanceled = [bool]$last.result.isCanceled
                attemptCountInWindow = $attempts.Count
                retryCountInWindow = if ($chain.Linked) { $attempts.Count - [int]$hasOriginal } else { $null }
                originalSessionIncluded = if ($chain.Linked) { $hasOriginal } else { $null }
                normalizationStatus = if ($chain.Linked) { 'Linked' } else { 'Unlinked' }
                normalizationScope = 'ReportWindow'
                sourceSessionIds = [object[]]$ids
            }
        }
    )

    $unlinked = @($beautified | Where-Object normalizationStatus -eq 'Unlinked').Count
    if ($unlinked -gt 0) {
        Write-Log (
            "$unlinked executions have no originalSessionId and were kept separate. " +
            'Exact retry collapsing is unavailable for those rows; normalizationStatus=Unlinked.'
        ) -Level WARN -Context REPORT
    }

    [PSCustomObject][ordered]@{
        'all-executions' = [PSCustomObject]@{ data = [object[]]$allExecutions }
        'beautified' = [PSCustomObject]@{ data = [object[]]$beautified }
    }
}
