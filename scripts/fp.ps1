# Run the dependency-free development controller from any current directory.
[CmdletBinding()]
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$CommandArgs)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$Entry = Join-Path $Root 'tools/fairpane.mjs'
$Node = Get-Command node -CommandType Application -ErrorAction SilentlyContinue
if ($null -ne $Node) {
    $Version = & $Node.Source --version
    $VersionMatch = [regex]::Match(($Version -join ''), '^v(\d+)\.')
    if ($LASTEXITCODE -eq 0 -and $VersionMatch.Success -and [int]$VersionMatch.Groups[1].Value -ge 22) {
        & $Node.Source $Entry @CommandArgs
        exit $LASTEXITCODE
    }
}
$Bun = Get-Command bun -CommandType Application -ErrorAction SilentlyContinue
if ($null -ne $Bun) {
    & $Bun.Source $Entry @CommandArgs
    exit $LASTEXITCODE
}
throw 'The controller needs Node 22 or newer, or Bun. Install a development runtime through an approved method.'
