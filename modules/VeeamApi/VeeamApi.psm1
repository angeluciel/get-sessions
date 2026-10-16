Set-StrictMode -Version Latest

# Private module state
$script:Config = $null

$script:Stats = @{
    ApiCalls   = 0
    ApiErrors  = 0
    ApiRetries = 0
}

function Initialize-VeeamApi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [uri]$BaseUrl,

        [Parameter(Mandatory)]
        [string]$ApiVersion,

        [ValidateRange(0, 10)]
        [int]$MaxRetries = 3,

        [ValidateRange(1, 300)]
        [int]$RetryDelaySec = 5,

        [string]$CredentialPath
    )

    $script:Config = @{
        VeeamBaseUrl       = $BaseUrl.AbsoluteUri.TrimEnd('/')
        ApiVersion         = $ApiVersion
        ApiMaxRetries      = $MaxRetries
        ApiRetryDelaySec   = $RetryDelaySec
        PathToCredential   = $CredentialPath
    }
}

function Assert-VeeamApiInitialized {
    if ($null -eq $script:Config) {
        throw 'Run Initialize-VeeamApi before using the module.'
    }
}

function Invoke-VeeamApi {
    <#
        Private API wrapper. It is available to other module functions,
        but is not exported to the user.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Endpoint,

        [ValidateSet('Get', 'Post', 'Put', 'Patch', 'Delete')]
        [string]$Method = 'Get',

        [hashtable]$Headers,

        [object]$Body,

        [string]$ContentType,

        [string]$Context = 'API'
    )

    Assert-VeeamApiInitialized

    $uri = '{0}/{1}' -f (
        $script:Config.VeeamBaseUrl.TrimEnd('/'),
        $Endpoint.TrimStart('/')
    )

    $attempt = 0

    while ($true) {
        $attempt++
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        try {
            Write-Log (
                '{0} {1} (attempt {2}/{3})' -f
                $Method,
                $Endpoint,
                $attempt,
                ($script:Config.ApiMaxRetries + 1)
            ) -Level DEBUG -Context $Context

            $parameters = @{
                Uri                  = $uri
                Method               = $Method
                Headers              = $Headers
                SkipCertificateCheck = $true
                ErrorAction          = 'Stop'
            }

            if ($PSBoundParameters.ContainsKey('Body') -and $null -ne $Body) {
                $parameters.Body = $Body
            }

            if ($ContentType) {
                $parameters.ContentType = $ContentType
            }

            $response = Invoke-RestMethod @parameters
            $stopwatch.Stop()

            $script:Stats.ApiCalls++

            Write-Log (
                "$Method $Endpoint -> success in " +
                "$($stopwatch.ElapsedMilliseconds)ms"
            ) -Level DEBUG -Context $Context

            return $response
        }
        catch {
            $stopwatch.Stop()
            $script:Stats.ApiErrors++

            $statusCode = $null

            if (
                $_.Exception.PSObject.Properties.Name -contains 'Response' -and
                $null -ne $_.Exception.Response
            ) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            $description = if ($statusCode) {
                "HTTP $statusCode"
            }
            else {
                'network error'
            }

            Write-Log (
                "$Method $Endpoint -> $description after " +
                "$($stopwatch.ElapsedMilliseconds)ms"
            ) -Level WARN -Context $Context

            if ($statusCode -in 400, 401, 403, 404) {
                Write-LogException -ErrorRecord $_ -Context $Context
                throw
            }

            if ($attempt -gt $script:Config.ApiMaxRetries) {
                Write-LogException -ErrorRecord $_ -Context $Context
                throw
            }

            $script:Stats.ApiRetries++

            Start-Sleep -Seconds $script:Config.ApiRetryDelaySec
        }
    }
}

function Unlock-VeeamCredentialStore {
    [CmdletBinding()]
    param(
        [string]$Path = $script:Config.PathToCredential
    )

    Assert-VeeamApiInitialized

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw 'No credential path was provided.'
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Credential file not found: $Path"
    }

    try {
        $password = Import-Clixml -LiteralPath $Path
        Unlock-SecretStore -Password $password -ErrorAction Stop
    }
    catch {
        Write-LogException -ErrorRecord $_ -Context AUTH
        throw 'Failed to unlock SecretStore.'
    }
}

function Connect-VeeamApi {
    [CmdletBinding()]
    param()

    Assert-VeeamApiInitialized

    try {
        $username = Get-Secret -Name VeeamApiUser -AsPlainText

        $response = Invoke-VeeamApi `
            -Endpoint '/api/oauth2/token' `
            -Method Post `
            -Context AUTH `
            -ContentType 'application/x-www-form-urlencoded' `
            -Headers @{
                accept          = 'application/json'
                'x-api-version' = $script:Config.ApiVersion
            } `
            -Body @{
                grant_type = 'Password'
                username   = $username
                password   = Get-Secret `
                    -Name VeeamApiPassword `
                    -AsPlainText
            }

        if (-not $response.access_token) {
            throw 'The API response did not contain an access token.'
        }

        return $response.access_token
    }
    catch {
        Write-LogException -ErrorRecord $_ -Context AUTH
        throw 'Veeam authentication failed.'
    }
}

function Get-VeeamApiStatistics {
    [CmdletBinding()]
    param()

    [pscustomobject]$script:Stats
}

# Only these commands become visible after Import-Module.
Export-ModuleMember -Function @(
    'Initialize-VeeamApi'
    'Unlock-VeeamCredentialStore'
    'Invoke-VeeamApi'
    'Connect-VeeamApi'
    'Get-VeeamApiStatistics'
)