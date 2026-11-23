@{ Backends = @(
    @{ Name = 'opencode'; Adapter = 'Invoke-OpenCode.ps1'; ExeParam = 'OpenCodeExe'; ContentionKeys = @('agent'); TimeoutSec = 1200; CdCapable = $false }
    @{ Name = 'codex'; Adapter = 'Invoke-Codex.ps1'; ExeParam = 'CodexExe'; ContentionKeys = @(); TimeoutSec = 1200; CdCapable = $true }
    @{ Name = 'claude-code'; Adapter = 'Invoke-ClaudeCodeAsync.ps1'; ExeParam = 'ClaudeExe'; ContentionKeys = @('permissionmode', 'tools', 'sidecarpath', 'retentionmode', 'tempdir', 'circuitstateroot', 'claudeexe', 'message', 'messagepath'); TimeoutSec = 1200; CdCapable = $true }
    @{ Name = 'copilot'; Adapter = 'Invoke-Copilot.ps1'; ExeParam = 'CopilotExe'; ContentionKeys = @(); TimeoutSec = 1200; CdCapable = $true }
    @{ Name = 'gemini'; Adapter = 'Invoke-Gemini.ps1'; ExeParam = 'GeminiExe'; ContentionKeys = @('approvalmode'); TimeoutSec = 1200; CdCapable = $true }
    @{ Name = 'antigravity'; Adapter = 'Invoke-Antigravity.ps1'; ExeParam = 'AntigravityExe'; ContentionKeys = @('mode', 'agent', 'approvalmode', 'profile', 'cd', 'scratchpath', 'simulatecleanupfailure', 'receiptpath', 'antigravityexe', 'message', 'messagepath'); TimeoutSec = 1200; CdCapable = $false }
) }
