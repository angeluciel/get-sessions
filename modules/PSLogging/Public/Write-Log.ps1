function Write-Log {
    param(
        [Parameter(Mandatory, Position=0)][string]$Message,
        [ValidateSet('DEBUG','INFO','SUCCESS','WARN','ERROR')][string]$Level = 'INFO',
        [string]$Context = ''
    )

    $st   = $script:LogState
    $ts   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    $ctx  = if ($Context) { '[{0}] ' -f $Context.PadRight(8) } else { '' }
    $line = '{0} [{1}] [{2}] {3}{4}' -f $ts, $Level.PadRight(7), $st.RunId, $ctx, $Message

    if ($st.Levels[$Level] -ge $st.Levels[$st.LogLevel]) {
        Write-Host $line -ForegroundColor $st.Colors[$Level]
    }

    if ($st.LogFile) {
        try   { Add-Content -Path $st.LogFile -Value $line -Encoding UTF8 -ErrorAction Stop }
        catch { Write-Host "!! Falha ao gravar log: $($_.Exception.Message)" -ForegroundColor Red }
    }
}