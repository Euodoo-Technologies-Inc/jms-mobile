$ErrorActionPreference = 'Stop'
$payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
$sessionId = $payload.session_id
if (-not $sessionId) { exit 0 }
$sentinel = Join-Path $env:TEMP "claude-history-done-$sessionId"
if (Test-Path $sentinel) { exit 0 }
New-Item -ItemType File -Path $sentinel -Force | Out-Null
$out = @{
  decision = 'block'
  reason   = 'Before stopping: append a new entry to the top of the Sessions list in d:\work\jms-mobile\fe-fms\history.md summarizing this session, following the existing template (Goal / Changes / Decisions / Open items). Newest-first.'
} | ConvertTo-Json -Compress
Write-Output $out
