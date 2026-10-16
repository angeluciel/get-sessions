#Requires -Version 7.0

$script:LogState = @{
    LogFile = $null
    RunId = [guid]::NewGuid().ToString('N').Substring(0,8)
    LogLevel = 'INFO'
    Levels = @{ DEBUG=0; INFO=1; SUCCESS=2; WARN=3; ERROR=4 } 
    Colors = @{ DEBUG='DarkGray'; INFO='Cyan'; SUCCESS='Green'; WARN='Yellow'; ERROR='Red' }
}

$publicas = Get-ChildItem  -Path "$PSScriptRoot\Public\*.ps1" -ErrorAction SilentlyContinue
foreach ($f in $publicas) { . $f.FullName }
Export-ModuleMember -Function $publicas.BaseName