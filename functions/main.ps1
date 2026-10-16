param(
    [string]$ConfigPath = (
        Join-Path $PSScriptRoot '..\config.psd1'
    )
)

$repoRoot = Split-Path $PSScriptRoot -Parent
$ErrorActionPreference = 'Stop'

Import-Module "$repoRoot\modules\VeeamApi\VeeamApi.psm1" -Force
Import-Module "$repoRoot\modules\PSLogging\PSLogging.psm1" -Force

#region - Importing Functions

. "$PSScriptRoot\Private\Get-ReportPeriod.ps1"
. "$PSScriptRoot\Private\Veeam\Get-VeeamSessions.ps1"
. "$PSScriptRoot\Private\Adapter\ConvertTo-SessionReport.ps1"
. "$PSScriptRoot\Private\Adapter\ConvertTo-SessionCsv.ps1"

#endregion

function Main {
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        throw @"
        Configuration file not found:
        $ConfigPath

        Copy config.example.psd1 to config.psd1 and configure your environment.
"@
    }

    $config = [PSCustomObject](Import-PowerShellDataFile -Path $ConfigPath)
    $requiredSettings = @('VeeamBaseUrl', 'ApiVersion', 'PathToCredential')

    foreach ($setting in $requiredSettings) {
        if ([string]::IsNullOrWhiteSpace($config.$setting)) {
            throw "Required configuration value '$setting' is missing."
        }
    }

    try {
        $loggingParameters = @{
            Directory = $config.LogDirectory
            RetentionDays = $config.LogRetentionDays
        }
        if ($config.LogLevel) { $loggingParameters.LogLevel = $config.LogLevel }
        Initialize-Logging @loggingParameters
    }
    catch {
        Write-Host "Couldn't start logging: $($_.Exception.Message)"
    }

    try {
        $period = Get-ReportPeriod `
            -StartDate $config.ReportStartDate `
            -EndDate $config.ReportEndDate

        try {
            Initialize-VeeamApi `
                -BaseUrl $config.VeeamBaseUrl `
                -ApiVersion $config.ApiVersion `
                -MaxRetries 3 `
                -CredentialPath $config.PathToCredential
        
            Write-Log "Initialized Veeam API" -Level INFO -Context VEEAM
        } catch {
            Write-Log "Couldn't initialize Veeam API" -Level ERROR -Context VEEAM
        }

        try {
            Unlock-VeeamCredentialStore

            Write-Log "Unlocked CredentialStore" -Level INFO -Context VEEAM
        } catch {
            Write-Log "Couldn't initialize Veeam API" -Level ERROR -Context VEEAM
        }

        $token = Connect-VeeamApi

        Write-Log ("Token for logging purposes: $($token.Substring(0, 5))") -Level INFO -Context VEEAM

        $headers = @{
            'Authorization' = "Bearer $token"
            'accept' = 'application/json'
            'x-api-version' = $config.ApiVersion
        }

        Write-Log (
            "Report period: $($period.StartDate) through $($period.EndDate) " +
            "(inclusive; $([TimeZoneInfo]::Local.Id))."
        ) -Level INFO -Context REPORT

        $sessions = @(Get-VeeamSessions `
            -Headers $headers `
            -StartUtc $period.StartUtc `
            -EndUtc $period.EndUtc)

        $body = ConvertTo-SessionReport -Sessions $sessions

        $outputDirectory = $config.ReportOutputDirectory
        if ([string]::IsNullOrWhiteSpace($outputDirectory)) {
            $outputDirectory = Join-Path $repoRoot 'reports'
        }
        elseif (-not [IO.Path]::IsPathRooted($outputDirectory)) {
            $outputDirectory = Join-Path $repoRoot $outputDirectory
        }

        $null = New-Item -ItemType Directory -Path $outputDirectory -Force
        $fileName = 'veeam-executions-{0}-to-{1}.json' -f $period.StartDate, $period.EndDate
        $outputPath = Join-Path $outputDirectory $fileName
        $temporaryPath = $outputPath + '.' + [guid]::NewGuid().ToString('N') + '.tmp'

        try {
            $csv  = ConvertTo-SessionCsv -Report $body -Delimiter ';' |
                Set-Content -Path "$PSScriptRoot\..\reports\beautified.csv" -Encoding utf8
            $json = ConvertTo-Json -InputObject $body -Depth 100 -WarningAction Stop
            Set-Content -LiteralPath $temporaryPath -Value $json -Encoding utf8
            Move-Item -LiteralPath $temporaryPath -Destination $outputPath -Force
        }
        finally {
            if (Test-Path -LiteralPath $temporaryPath) {
                Remove-Item -LiteralPath $temporaryPath -Force
            }
        }

        Write-Log (
            "Exported $($body.'all-executions'.data.Count) executions and " +
            "$($body.beautified.data.Count) presentation rows to $outputPath."
        ) -Level SUCCESS -Context REPORT

        return $body
    }
    catch {
        Write-LogException -ErrorRecord $_ -Context REPORT
        exit 2
    }
}

Main
