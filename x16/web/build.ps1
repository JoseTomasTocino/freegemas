param([string]$Out = "")

$ErrorActionPreference = "Stop"
$nodeArgs = @((Join-Path $PSScriptRoot "build.mjs"))
if ($Out) { $nodeArgs += @("--out", $Out) }

& node @nodeArgs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
