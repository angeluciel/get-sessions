function Get-VeeamSessions {
    <#
    .SYNOPSIS
    Reads backup, backup-copy and restore executions through the existing API module.
    The configured API version, HTTP retries and TLS behavior stay in VeeamApi.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Headers,
        [Parameter(Mandatory)][DateTimeOffset]$StartUtc,
        [Parameter(Mandatory)][DateTimeOffset]$EndUtc
    )

    # Filter after fetching, so older API revisions are never sent newer enum values.
    # These are execution/session types, not /jobs job-definition types.
    $sessionTypes = @(
        'BackupJob', 'ConfigurationBackup', 'FileServerSave', 'AgentPolicy',
        'AgentBackup', 'EndpointBackup', 'SqlLogBackup', 'OracleLogBackup',
        'PostgreSqlLogBackup', 'IrisBackup', 'PlatformBackupJob', 'PlatformSnapshotJob',
        'AgentOperationBackupNow', 'AgentOperationActiveFull',
        'BackupCopyJob', 'BackupCopyJobParent', 'UnstructuredDataBackupCopy',
        'CopyBackup', 'PerVmCopyBackup', 'PlatformSnapshotCopyJob',
        'RestoreVm', 'InstantRecovery', 'FirstClassDiskInstantRestore',
        'FileLevelRestore', 'LinuxFileLevelRestore', 'CloudDirectorVmRestore',
        'CloudDirectorVAppRestore', 'EntraIdRestore', 'EntraIdRestoreFromCopy',
        'NasRestore', 'AzureInstantRecovery', 'AzureInstantRecoveryMigration',
        'AzureInstantRecoverySwitchover', 'AzureInstantRecoveryStart',
        'AzureInstantRecoveryStop', 'AzureInstantRecoveryMigrationUndo',
        'AzureInstantRecoveryMount', 'FileInstantRecovery', 'FileInstantRecoveryMigration',
        'ApplicationLevelRestore', 'AdForestRestore', 'RestoreRecoveryApplianceVolumes',
        'RestoreAgentVolumes', 'EndpointRestore', 'InstantDiskRecovery', 'DiskRestore',
        'QuickMigration', 'FirstClassDiskQuickMigration'
    )

    $limit = 200
    $skip = 0
    $expectedTotal = $null
    $sessionsById = @{}
    # Widen the lower API filter, then apply the exact boundary locally. This
    # includes a session exactly at midnight whether the API uses > or >=.
    $after = [uri]::EscapeDataString($StartUtc.AddSeconds(-1).ToString('o'))
    $before = [uri]::EscapeDataString($EndUtc.ToString('o'))

    while ($true) {
        $endpoint = '/api/v1/sessions?orderColumn=CreationTime&orderAsc=true' +
            "&skip=$skip&limit=$limit&createdAfterFilter=$after&createdBeforeFilter=$before"

        $response = Invoke-VeeamApi `
            -Endpoint $endpoint `
            -Method Get `
            -Headers $Headers `
            -Context SESSIONS

        if ($null -eq $response -or $null -eq $response.data) {
            throw 'The sessions endpoint returned no data array.'
        }
        $page = @($response.data)
        $total = $response.pagination.total
        if ($null -ne $total) {
            if ($null -eq $expectedTotal) { $expectedTotal = [long]$total }
            elseif ($expectedTotal -ne [long]$total) {
                throw 'Session history changed while paging. Rerun the report; no partial export was written.'
            }
        }
        if ($page.Count -eq 0) {
            if ($null -ne $expectedTotal -and $skip -lt $expectedTotal) {
                throw 'The API returned an empty page before its advertised total was reached.'
            }
            break
        }

        $newIds = 0
        foreach ($session in $page) {
            if ([string]::IsNullOrWhiteSpace([string]$session.id)) { throw 'A session has no id.' }
            if (-not $sessionsById.ContainsKey([string]$session.id)) { $newIds++ }
            $sessionsById[[string]$session.id] = $session
        }
        if ($newIds -eq 0) { throw 'The sessions endpoint repeated a page.' }
        $skip += $page.Count
        Write-Log "Read $skip sessions." -Level DEBUG -Context SESSIONS
        if ($null -ne $expectedTotal -and $skip -ge $expectedTotal) { break }
    }

    if ($null -ne $expectedTotal -and $sessionsById.Count -ne $expectedTotal) {
        throw 'Overlapping or missing sessions were detected while paging. Rerun the report.'
    }

    $selected = @(
        foreach ($session in $sessionsById.Values) {
            if ([string]::IsNullOrWhiteSpace([string]$session.creationTime)) {
                throw "Session '$($session.id)' has no creationTime."
            }
            $created = [DateTimeOffset]$session.creationTime
            if ($created -ge $StartUtc -and $created -lt $EndUtc -and $session.sessionType -in $sessionTypes) {
                $session
            }
        }
    )
    Write-Log "Selected $($selected.Count) backup/copy/restore executions." -Level SUCCESS -Context SESSIONS
    return $selected | Sort-Object -Property @{
        Expression = { [DateTimeOffset]$_.creationTime }
    }, @{ Expression = { [string]$_.id } }
}
