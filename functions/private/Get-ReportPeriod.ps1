function Get-ReportPeriod {
    <#
    .SYNOPSIS
    Resolves inclusive calendar dates into a UTC [start, end) reporting window.
    Empty dates select the previous calendar month in the script host's timezone.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$StartDate,
        [AllowEmptyString()][string]$EndDate
    )

    $hasStart = -not [string]::IsNullOrWhiteSpace($StartDate)
    $hasEnd = -not [string]::IsNullOrWhiteSpace($EndDate)
    if ($hasStart -ne $hasEnd) {
        throw 'Set both ReportStartDate and ReportEndDate, or leave both empty for last month.'
    }

    if ($hasStart) {
        try {
            $start = [datetime]::ParseExact($StartDate, 'yyyy-MM-dd', [cultureinfo]::InvariantCulture)
            $endExclusive = [datetime]::ParseExact($EndDate, 'yyyy-MM-dd', [cultureinfo]::InvariantCulture).AddDays(1)
        }
        catch { throw 'ReportStartDate and ReportEndDate must be valid yyyy-MM-dd dates.' }
    }
    else {
        $now = Get-Date
        $endExclusive = [datetime]::new($now.Year, $now.Month, 1)
        $start = $endExclusive.AddMonths(-1)
    }

    if ($start -ge $endExclusive) { throw 'ReportEndDate must be on or after ReportStartDate.' }
    foreach ($boundary in @($start, $endExclusive)) {
        if ([TimeZoneInfo]::Local.IsInvalidTime($boundary) -or [TimeZoneInfo]::Local.IsAmbiguousTime($boundary)) {
            throw 'A report boundary falls in a local DST clock change; the calendar dates are ambiguous.'
        }
    }

    [pscustomobject]@{
        StartDate = $start.ToString('yyyy-MM-dd')
        EndDate = $endExclusive.AddDays(-1).ToString('yyyy-MM-dd')
        StartUtc = [DateTimeOffset]::new($start.ToUniversalTime())
        EndUtc = [DateTimeOffset]::new($endExclusive.ToUniversalTime())
    }
}
