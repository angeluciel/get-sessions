function Initialize-Logging {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Directory,
        [int]$RetentionDays = 30,
        [string]$Prefix = 'app',
        [ValidateSet('DEBUG','INFO','SUCCESS','WARN','ERROR')][string]$LogLevel = 'INFO',
        [string]$RunId
    )

    if ($RunId) { $script:LogState.RunId = $RunId }
    $script:LogState.LogLevel = $LogLevel

    if (-not (Test-Path $Directory)) {
        New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    }

    $script:LogState.LogFile = Join-Path $Directory (
        '{0}_{1}.log' -f $Prefix, (Get-Date -Format 'yyyy-MM-dd')
    )

    Write-Log "===== Início da execução (RunId $($script:LogState.RunId)) =====" -Context 'INIT'
    Write-Log "Host: $env:COMPUTERNAME | Usuário: $env:USERNAME | PS $($PSVersionTable.PSVersion)" -Level DEBUG -Context 'INIT'

    try {
        $antigos = Get-ChildItem -Path $Directory -Filter "$Prefix`_*.log" -ErrorAction SilentlyContinue |
                   Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$RetentionDays) }
        if ($antigos) {
            $antigos | Remove-Item -Force -ErrorAction SilentlyContinue
            Write-Log "Removidos $($antigos.Count) log(s) com mais de $RetentionDays dias" -Level DEBUG -Context 'INIT'
        }
    }
    catch { Write-Log "Falha ao expurgar logs antigos: $($_.Exception.Message)" -Level WARN -Context 'INIT' }
}