function Write-LogException {
    param([Parameter(Mandatory)]$ErrorRecord, [string]$Context = '')

    Write-Log "Exceção: $($ErrorRecord.Exception.Message)" -Level ERROR -Context $Context
    Write-Log "Tipo: $($ErrorRecord.Exception.GetType().FullName)" -Level DEBUG -Context $Context
    Write-Log "Origem: $($ErrorRecord.InvocationInfo.ScriptLineNumber):$($ErrorRecord.InvocationInfo.OffsetInLine) -> $($ErrorRecord.InvocationInfo.Line.Trim())" -Level DEBUG -Context $Context

    if ($ErrorRecord.ScriptStackTrace) {
        foreach ($l in $ErrorRecord.ScriptStackTrace -split "`n") {
            Write-Log "  stack: $($l.Trim())" -Level DEBUG -Context $Context
        }
    }
}