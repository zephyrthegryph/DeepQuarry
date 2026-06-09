# DQEdit — DME renamed vorestation.dme -> deepquarry.dme
Set-Variable -Name "basedir" -Value "$PSScriptRoot/../.."

(Get-Content "$basedir/deepquarry.dme").Replace('#include "maps\southern_cross\southern_cross.dm"', '#include "maps\virgo_minitest\virgo_minitest.dm"') | Set-Content "$basedir/deepquarry.dme"
& "$basedir/tools/build/build.bat"
(Get-Content "$basedir/deepquarry.dme").Replace('#include "maps\virgo_minitest\virgo_minitest.dm"', '#include "maps\southern_cross\southern_cross.dm"') | Set-Content "$basedir/deepquarry.dme"
Read-Host -Prompt "Press any key to continue"
