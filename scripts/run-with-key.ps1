<#
.SYNOPSIS
  Run FinMatrix with the Anthropic (Claude) key injected at build time.

.DESCRIPTION
  Reads the key from the ANTHROPIC_API_KEY environment variable so the secret
  is never stored in source control. Any extra arguments are forwarded verbatim
  to `flutter run` (e.g. -d chrome, -d windows).

  Note: no param() block is used on purpose — it lets flags like `-d` pass
  straight through to flutter instead of being captured by PowerShell binding.

.EXAMPLE
  $env:ANTHROPIC_API_KEY = 'sk-ant-...'
  ./scripts/run-with-key.ps1 -d windows
#>

$ErrorActionPreference = 'Stop'

$key = $env:ANTHROPIC_API_KEY
if ([string]::IsNullOrWhiteSpace($key)) {
  Write-Error "ANTHROPIC_API_KEY is not set. Run:  `$env:ANTHROPIC_API_KEY = 'sk-ant-...'  then re-run this script."
  exit 1
}

# Run from the project root (parent of this script's folder).
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot
try {
  $tail = if ($key.Length -ge 6) { $key.Substring($key.Length - 6) } else { $key }
  Write-Host "Launching FinMatrix with Anthropic key (…$tail)" -ForegroundColor Cyan
  # $args forwards all extra arguments (e.g. -d chrome) verbatim to flutter.
  flutter run --dart-define=ANTHROPIC_API_KEY=$key @args
}
finally {
  Pop-Location
}

