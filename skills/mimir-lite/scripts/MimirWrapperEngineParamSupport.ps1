#requires -Version 7.4
<#
.SYNOPSIS
  Support (dot-source) for two local-wrapper inventory checks
  (Test-MimirWrapperInventory.ps1): (1) forwards_unknown_engine_param — forwarding an
  undeclared parameter to a shared advanced engine (wrapper->engine direction); (2) surface
  diff of local wrapper vs. template — surface_mismatch (blocking) and INVENTORY_SURFACE_ADVISORY
  (warning), see its own block at the end of the file (wrapper->template direction).

.DESCRIPTION
  This file hosts TWO inventory checks. This .DESCRIPTION section and the KNOWN
  LIMITS below cover check (1) forwards_unknown_engine_param (wrapper->engine direction);
  check (2), the wrapper->template surface diff (`surface_mismatch`/`INVENTORY_SURFACE_ADVISORY`,
  helpers Get-MimirScriptParamSurface/Get-MimirWrapperSurfaceFinding), has its own
  documentation in the comment block at the end of the file.

  Check (1): verifies, via AST + Get-Command (without executing the engine, without a KB), that every
  parameter a local wrapper FORWARDS to a shared ADVANCED engine actually EXISTS on the engine (canonical
  name or alias). On an advanced engine, forwarding an undeclared parameter is a runtime
  binding error, invisible to parse/STRUCTURE_OK/GATE_OK.

  It is NOT a self-test; it emits no sentinel. It is dot-sourced by Test-MimirWrapperInventory.ps1.

  Scope discriminator (by VALUE, not by the root variable's name):
    - site = `& $V ...` where $V is assigned (depth 1, same scope) from a
      `Join-Path <root> 'scripts\<Leaf>.ps1'` expression (literal/nested/multi-arg forms);
    - the discriminator operates on the Join-Path expression's literal 'scripts' (AST), not on the
      resolved path: `Join-Path $PSScriptRoot 'Rebuild.ps1'` resolves to .../scripts/Rebuild.ps1
      but does NOT have the literal 'scripts' -> local sibling, out of scope;
    - leaf existing in the auditor's engines folder (EnginesRoot) -> shared engine;
    - leaf not existing under an expression with the literal 'scripts' -> shared_engine_unresolved
      (wrapper-drift signal; consistent with 8.a.ii of the setup workflow);
    - target not resolvable to a literal Join-Path expression (dynamic root, reassignment,
      multi-hop) -> skip the site (conservative; see LIMITS).

  Advanced detection (without executing): advanced iff the CommonParameters were INJECTED by the
  runtime, i.e. present in Get-Command.Parameters but ABSENT from the engine's declared param()
  block in the AST. A SIMPLE script that literally declares $Verbose is not mistaken for advanced.

  Name comparison: OrdinalIgnoreCase throughout the pipeline (binding is case-insensitive).

  KNOWN LIMITS (skip the site; known follow-up), not audited:
    - reassignment of the root/intermediate variable via a non-trackable expression, multi-hop,
      variable-composed basename, fully dynamic root;
    - direct invocation without a variable, Invoke-Expression, dot-source, pipeline, positional
      forwarding;
    - name collision via `Join-Path $repoRoot 'scripts\<X>.ps1'` pointing to a LOCAL file
      whose leaf matches a canonical engine (outside the templates' pattern).
#>

Set-StrictMode -Version Latest

# CommonParameters that only coexist in ADVANCED functions/scripts (injected by the runtime).
# Subset stable across PowerShell 7.x versions, used as the discriminator.
$script:MimirEngineParamCommonMarkers = @('Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'OutBuffer')

function Get-MimirAstJoinPathLeaf {
    <#
      Takes an expression Ast (right-hand side of an assignment, or the & target).
      If it is (or contains) a Join-Path call with a literal 'scripts' segment and a
      literal '<something>.ps1' leaf, returns [pscustomobject]@{ HasScriptsSegment; Leaf }.
      If it is not a Join-Path resolvable to literals, returns $null (unresolvable target).
    #>
    param([System.Management.Automation.Language.Ast]$Ast)

    if ($null -eq $Ast) { return $null }

    # Unwrap Pipeline/CommandExpression down to the Join-Path's CommandAst, or ParenExpression.
    $node = $Ast
    while ($true) {
        if ($node -is [System.Management.Automation.Language.PipelineAst]) {
            if (@($node.PipelineElements).Count -ne 1) { return $null }
            $node = $node.PipelineElements[0]; continue
        }
        if ($node -is [System.Management.Automation.Language.CommandExpressionAst]) { $node = $node.Expression; continue }
        if ($node -is [System.Management.Automation.Language.ParenExpressionAst]) { $node = $node.Pipeline; continue }
        break
    }

    if (-not ($node -is [System.Management.Automation.Language.CommandAst])) { return $null }

    $elements = @($node.CommandElements)
    if ($elements.Count -lt 1) { return $null }
    $cmdName = $elements[0]
    if (-not ($cmdName -is [System.Management.Automation.Language.StringConstantExpressionAst])) { return $null }
    if ($cmdName.Value -ine 'Join-Path') { return $null }

    # Collect string literals from this call + from Join-Path calls nested in the arguments.
    $literals = [System.Collections.Generic.List[string]]::new()
    for ($ei = 1; $ei -lt $elements.Count; $ei++) {
        $el = $elements[$ei]
        if ($el -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
            $literals.Add([string]$el.Value)
        } elseif ($el -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) {
            # interpolated string (e.g. "scripts\$leaf") -> not resolvable to a safe literal
            return $null
        } elseif ($el -is [System.Management.Automation.Language.ParenExpressionAst] -or
                  $el -is [System.Management.Automation.Language.CommandExpressionAst] -or
                  $el -is [System.Management.Automation.Language.PipelineAst]) {
            $nested = Get-MimirAstJoinPathLeaf -Ast $el
            if ($null -ne $nested) {
                if ($nested.HasScriptsSegment) { return $nested }
                # nested resolved but without 'scripts' -> aggregate its segments via leaf
                if ($nested.Leaf) { $literals.Add([string]$nested.Leaf) }
            }
        }
        # VariableExpressionAst (the root) is deliberately ignored: the discriminator is by shape+leaf.
    }

    if ($literals.Count -eq 0) { return $null }

    # Split each literal into segments by \ or /.
    $segments = [System.Collections.Generic.List[string]]::new()
    foreach ($lit in $literals) {
        foreach ($seg in @($lit -split '[\\/]+')) {
            if (-not [string]::IsNullOrWhiteSpace($seg)) { $segments.Add($seg) }
        }
    }

    $hasScripts = $false
    foreach ($seg in $segments) { if ($seg -ieq 'scripts') { $hasScripts = $true; break } }

    $leaf = $null
    for ($i = $segments.Count - 1; $i -ge 0; $i--) {
        if ($segments[$i] -imatch '\.ps1$') { $leaf = $segments[$i]; break }
    }

    if ($null -eq $leaf) { return $null }
    return [pscustomobject]@{ HasScriptsSegment = $hasScripts; Leaf = $leaf }
}

function Resolve-MimirEngineTarget {
    <#
      Resolves a `& <target> ...` target to an engine leaf (depth 1, same root
      ScriptBlock). Returns [pscustomobject]@{ Kind; Leaf } where Kind is:
        'shared'      -> Join-Path with literal 'scripts' + leaf (audit; check existence)
        'local'       -> Join-Path without literal 'scripts' (local sibling; out of scope)
        'unresolved'  -> not resolvable to a literal (skip)
    #>
    param(
        [System.Management.Automation.Language.Ast]$TargetAst,
        [System.Management.Automation.Language.Ast]$RootAst
    )

    # Case 1: the target is the Join-Path expression itself (e.g. & (Join-Path ...) -P) — defensive.
    $direct = Get-MimirAstJoinPathLeaf -Ast $TargetAst
    if ($null -ne $direct) {
        if ($direct.HasScriptsSegment) { return [pscustomobject]@{ Kind = 'shared'; Leaf = $direct.Leaf } }
        return [pscustomobject]@{ Kind = 'local'; Leaf = $direct.Leaf }
    }

    # Case 2: the target is a variable -> resolve the SINGLE literal assignment in scope.
    if (-not ($TargetAst -is [System.Management.Automation.Language.VariableExpressionAst])) {
        return [pscustomobject]@{ Kind = 'unresolved'; Leaf = $null }
    }
    $varName = $TargetAst.VariablePath.UserPath

    $assignments = @($RootAst.FindAll({
                param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $n.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
                $n.Left.VariablePath.UserPath -ieq $varName
            }, $true))

    if ($assignments.Count -ne 1) {
        # none, or multiple (reassignment) -> not trackable
        return [pscustomobject]@{ Kind = 'unresolved'; Leaf = $null }
    }

    $resolved = Get-MimirAstJoinPathLeaf -Ast $assignments[0].Right
    if ($null -eq $resolved) { return [pscustomobject]@{ Kind = 'unresolved'; Leaf = $null } }
    if ($resolved.HasScriptsSegment) { return [pscustomobject]@{ Kind = 'shared'; Leaf = $resolved.Leaf } }
    return [pscustomobject]@{ Kind = 'local'; Leaf = $resolved.Leaf }
}

function Get-MimirForwardedParamName {
    <#
      Extracts the parameter NAMES forwarded at a site `& <target> <elements...>`.
      Explicit ones via CommandParameterAst; splat via resolving the splatted variable's
      literal keys. Redirections are not a CommandElement -> ignored.
    #>
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [System.Management.Automation.Language.Ast]$RootAst
    )

    $names = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $elements = @($CommandAst.CommandElements)
    # element 0 is the target (& $V); the rest are parameters/arguments.
    for ($i = 1; $i -lt $elements.Count; $i++) {
        $el = $elements[$i]
        if ($el -is [System.Management.Automation.Language.CommandParameterAst]) {
            [void]$names.Add([string]$el.ParameterName)
        } elseif ($el -is [System.Management.Automation.Language.VariableExpressionAst] -and $el.Splatted) {
            foreach ($k in (Get-MimirSplatLiteralKey -SplatVarName $el.VariablePath.UserPath -RootAst $RootAst)) {
                [void]$names.Add($k)
            }
        }
    }
    return @($names)
}

function Get-MimirSplatLiteralKey {
    <#
      Collects the literal keys of a splat hashtable (@var):
        - literal HashtableAst assigned to $var;
        - member  $var.Key = ...
        - index   $var['Key'] = ...
        - method  $var.Add('Key', ...)
      A non-literal (dynamic) key is ignored. If $var undergoes mutation via .Remove/.Clear
      or reassignment via a non-trackable expression, the caller will already have skipped
      the site; here we just collect what is literal.
    #>
    param([string]$SplatVarName, [System.Management.Automation.Language.Ast]$RootAst)

    $keys = [System.Collections.Generic.List[string]]::new()

    # (a) literal HashtableAst assigned directly to $var.
    $assigns = @($RootAst.FindAll({
                param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $n.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
                $n.Left.VariablePath.UserPath -ieq $SplatVarName
            }, $true))
    foreach ($a in $assigns) {
        $right = $a.Right
        if ($right -is [System.Management.Automation.Language.CommandExpressionAst]) { $right = $right.Expression }
        if ($right -is [System.Management.Automation.Language.HashtableAst]) {
            foreach ($pair in $right.KeyValuePairs) {
                $keyAst = $pair.Item1
                if ($keyAst -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                    $keys.Add([string]$keyAst.Value)
                }
            }
        }
    }

    # (b) member/index: $var.Key = ... or $var['Key'] = ...
    $memberAssigns = @($RootAst.FindAll({
                param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst]
            }, $true))
    foreach ($a in $memberAssigns) {
        $left = $a.Left
        if ($left -is [System.Management.Automation.Language.MemberExpressionAst] -and
            $left.Expression -is [System.Management.Automation.Language.VariableExpressionAst] -and
            $left.Expression.VariablePath.UserPath -ieq $SplatVarName -and
            $left.Member -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
            $keys.Add([string]$left.Member.Value)
        } elseif ($left -is [System.Management.Automation.Language.IndexExpressionAst] -and
            $left.Target -is [System.Management.Automation.Language.VariableExpressionAst] -and
            $left.Target.VariablePath.UserPath -ieq $SplatVarName -and
            $left.Index -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
            $keys.Add([string]$left.Index.Value)
        }
    }

    # (c) method .Add('Key', ...)
    $invokes = @($RootAst.FindAll({
                param($n) $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
                $n.Expression -is [System.Management.Automation.Language.VariableExpressionAst] -and
                $n.Expression.VariablePath.UserPath -ieq $SplatVarName -and
                $n.Member -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
                $n.Member.Value -ieq 'Add'
            }, $true))
    foreach ($inv in $invokes) {
        $argList = @($inv.Arguments)
        if ($argList.Count -ge 1 -and $argList[0] -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
            $keys.Add([string]$argList[0].Value)
        }
    }

    return @($keys)
}

function Test-MimirSplatVarMutated {
    <# True if the splat variable undergoes .Remove/.Clear or was reassigned more than once (not trackable). #>
    param([string]$SplatVarName, [System.Management.Automation.Language.Ast]$RootAst)

    $mutators = @($RootAst.FindAll({
                param($n) $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
                $n.Expression -is [System.Management.Automation.Language.VariableExpressionAst] -and
                $n.Expression.VariablePath.UserPath -ieq $SplatVarName -and
                $n.Member -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
                ($n.Member.Value -ieq 'Remove' -or $n.Member.Value -ieq 'Clear')
            }, $true))
    return $mutators.Count -gt 0
}

function Get-MimirEngineAcceptedParam {
    <#
      Resolves the set of parameters accepted by an ADVANCED engine, or a diagnostic.
      Returns [pscustomobject]@{ Status; Accepted } where Status is:
        'advanced'   -> Accepted = HashSet (OrdinalIgnoreCase) of accepted names + aliases
        'simple'     -> non-advanced engine (permissive binder); not auditable
        'unparseable'-> parse error/Get-Command failed/Parameters null
        'dynamic'    -> engine declares DynamicParam (not statically visible)
    #>
    param([string]$EngineFullPath)

    # Primary parse (source of unparseable).
    $perrs = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($EngineFullPath, [ref]$null, [ref]$perrs)
    if ($null -ne $perrs -and @($perrs).Count -gt 0) {
        return [pscustomobject]@{ Status = 'unparseable'; Accepted = $null }
    }

    $cmd = $null
    try { $cmd = Get-Command -Name $EngineFullPath -ErrorAction Stop } catch {
        return [pscustomobject]@{ Status = 'unparseable'; Accepted = $null }
    }
    if ($null -eq $cmd -or $null -eq $cmd.Parameters) {
        return [pscustomobject]@{ Status = 'unparseable'; Accepted = $null }
    }

    # DynamicParam guard (does not appear statically in Get-Command).
    $body = [System.IO.File]::ReadAllText($EngineFullPath)
    if ($body -imatch '(?m)^\s*dynamicparam\b') {
        return [pscustomobject]@{ Status = 'dynamic'; Accepted = $null }
    }

    $surface = @($cmd.Parameters.Keys)

    # Names declared in the AST's param() block (TrimStart '$').
    $declared = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $engineAst = [System.Management.Automation.Language.Parser]::ParseFile($EngineFullPath, [ref]$null, [ref]$null)
    $paramBlocks = @($engineAst.FindAll({
                param($n) $n -is [System.Management.Automation.Language.ParamBlockAst]
            }, $true))
    foreach ($pb in $paramBlocks) {
        foreach ($p in $pb.Parameters) {
            [void]$declared.Add(([string]$p.Name.VariablePath.UserPath))
        }
    }

    # injected = surface - declared.
    $injected = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($s in $surface) { if (-not $declared.Contains([string]$s)) { [void]$injected.Add([string]$s) } }

    $isAdvanced = $true
    foreach ($marker in $script:MimirEngineParamCommonMarkers) {
        if (-not $injected.Contains($marker)) { $isAdvanced = $false; break }
    }
    if (-not $isAdvanced) { return [pscustomobject]@{ Status = 'simple'; Accepted = $null } }

    $accepted = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($s in $surface) { [void]$accepted.Add([string]$s) }
    foreach ($pname in $cmd.Parameters.Keys) {
        foreach ($alias in @($cmd.Parameters[$pname].Aliases)) { [void]$accepted.Add([string]$alias) }
    }
    return [pscustomobject]@{ Status = 'advanced'; Accepted = $accepted }
}

function Get-MimirWrapperEngineParamFinding {
    <#
      Entry point. For a local wrapper, returns:
        [pscustomobject]@{
          Signals          = @( @{ Reason; Detail } )   # wrapper-drift signals (-> INVENTORY_CUSTOMIZED)
          EngineDiagnostics = @( @{ Reason; Detail } )   # soft infra diagnostic (-> INVENTORY_ENGINE_DIAGNOSTIC)
          AuditedSiteCount = <int>                        # number of audited advanced-engine sites
        }
      EnginesRoot = folder of the auditor's canonical engines (typically the inventory's $PSScriptRoot).
    #>
    param(
        [Parameter(Mandatory)][string]$WrapperPath,
        [Parameter(Mandatory)][string]$EnginesRoot
    )

    $signals = [System.Collections.Generic.List[object]]::new()
    $diagnostics = [System.Collections.Generic.List[object]]::new()
    $audited = 0

    $perrs = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($WrapperPath, [ref]$null, [ref]$perrs)
    if ($null -eq $ast) {
        return [pscustomobject]@{ Signals = @(); EngineDiagnostics = @(); AuditedSiteCount = 0 }
    }

    $callSites = @($ast.FindAll({
                param($n) $n -is [System.Management.Automation.Language.CommandAst] -and
                $n.InvocationOperator -eq [System.Management.Automation.Language.TokenKind]::Ampersand
            }, $true))

    foreach ($site in $callSites) {
        $elements = @($site.CommandElements)
        if ($elements.Count -lt 1) { continue }
        $target = Resolve-MimirEngineTarget -TargetAst $elements[0] -RootAst $ast
        if ($target.Kind -eq 'local' -or $target.Kind -eq 'unresolved') { continue }
        # target.Kind = 'shared'
        $leaf = $target.Leaf
        $enginePath = Join-Path $EnginesRoot $leaf
        if (-not (Test-Path -LiteralPath $enginePath -PathType Leaf)) {
            $signals.Add(@{ Reason = 'shared_engine_unresolved'; Detail = $leaf })
            continue
        }

        # If the splat variable undergoes non-trackable mutation, skip the site (conservative).
        $splatVar = $null
        for ($i = 1; $i -lt $elements.Count; $i++) {
            if ($elements[$i] -is [System.Management.Automation.Language.VariableExpressionAst] -and $elements[$i].Splatted) {
                $splatVar = $elements[$i].VariablePath.UserPath; break
            }
        }
        if ($splatVar -and (Test-MimirSplatVarMutated -SplatVarName $splatVar -RootAst $ast)) { continue }

        $engine = Get-MimirEngineAcceptedParam -EngineFullPath $enginePath
        # NOTE: 'continue' inside a switch continues the switch, not the foreach; that's why the
        # switch is the loop body's last statement and each case only does its own work.
        switch ($engine.Status) {
            'unparseable' { $diagnostics.Add(@{ Reason = 'engine_unresolved_or_unparseable'; Detail = $leaf }) }
            'dynamic'     { }
            'simple'      { }
            'advanced' {
                $audited++
                $forwarded = Get-MimirForwardedParamName -CommandAst $site -RootAst $ast
                foreach ($name in $forwarded) {
                    if (-not $engine.Accepted.Contains([string]$name)) {
                        $signals.Add(@{ Reason = 'forwards_unknown_engine_param'; Detail = ('-{0} -> {1}' -f $name, $leaf) })
                    }
                }
            }
        }
    }

    return [pscustomobject]@{
        Signals           = @($signals)
        EngineDiagnostics = @($diagnostics)
        AuditedSiteCount  = $audited
    }
}

# ============================================================================
# Wrapper surface diff (surface_mismatch / INVENTORY_SURFACE_ADVISORY check)
#
# Compares the LOCAL wrapper's surface {parameter names; Mandatory; each [ValidateSet]'s
# value set} against the canonical TEMPLATE (.example.ps1). DEFAULT VALUE is
# NOT part of the surface (the template uses placeholders such as SharedSkillsRoot). Direction-
# aware severity: the false positive lives on the "more / ahead" side (the repo deliberately
# removes [ValidateSet] to delegate to the engine; there is a runtime index-gate), so that side
# is NOT punished. BLOCKS only on LOSS of mandatory contract; WARNS on optional/ValidateSet
# reductions; QUIET on legitimate surplus/delegation. Complements (does not duplicate) the reverse-
# direction check forwards_unknown_engine_param above: there the wrapper forwards too much; here the
# wrapper falls behind the template.
# ============================================================================

function Test-MimirAttributeAstIsType {
    <# True if $Attr is an AttributeAst whose TypeName matches (accelerator OR FQN) one of $Names. #>
    param([System.Management.Automation.Language.Ast]$Attr, [string[]]$Names)
    if (-not ($Attr -is [System.Management.Automation.Language.AttributeAst])) { return $false }
    $fn = [string]$Attr.TypeName.FullName
    foreach ($n in $Names) { if ($fn -ieq $n) { return $true } }
    return $false
}

function Test-MimirParamAstMandatory {
    <#
      A parameter is mandatory IFF ANY [Parameter] marks it Mandatory=$true (union across
      parameter sets). Missing [Parameter] attribute OR without Mandatory=optional; Mandatory with no value
      (ExpressionOmitted)=mandatory; =$true=mandatory; =$false=optional per that attr; ANY
      non-literal-bool expression (=$var, =[bool]"x")=conservatively MANDATORY (do not evaluate). Matches
      [Parameter] by accelerator AND FQN.
    #>
    param([System.Management.Automation.Language.ParameterAst]$ParameterAst)
    foreach ($attr in $ParameterAst.Attributes) {
        if (-not (Test-MimirAttributeAstIsType -Attr $attr -Names @('Parameter', 'ParameterAttribute', 'System.Management.Automation.ParameterAttribute'))) { continue }
        foreach ($na in $attr.NamedArguments) {
            if ($na.ArgumentName -ine 'Mandatory') { continue }
            if ($na.ExpressionOmitted) { return $true }
            $arg = $na.Argument
            if ($arg -is [System.Management.Automation.Language.VariableExpressionAst]) {
                $vp = $arg.VariablePath.UserPath
                if ($vp -ieq 'true') { return $true }
                elseif ($vp -ieq 'false') { continue }
                else { return $true }
            } else {
                return $true
            }
        }
    }
    return $false
}

function Get-MimirParamAstValidateSet {
    <#
      Returns [pscustomobject]@{ Comparable; Values }. Comparable (Values=HashSet OrdinalIgnoreCase)
      IFF EXACTLY 1 [ValidateSet] exists and ALL positionals are STRING literals. Not comparable
      (Values=$null) when: zero or >1 [ValidateSet] (multiple = AND/INTERSECTION, not union); empty;
      any non-literal positional (mixed/generator/variable) or non-string literal (e.g. 1,2,3).
      NAMED arguments (IgnoreCase=/ErrorMessage=) are ignored. Covers direct positional and
      ArrayLiteralAst. Matches [ValidateSet] by accelerator AND FQN.
    #>
    param([System.Management.Automation.Language.ParameterAst]$ParameterAst)
    $vsAttrs = @($ParameterAst.Attributes | Where-Object {
            Test-MimirAttributeAstIsType -Attr $_ -Names @('ValidateSet', 'ValidateSetAttribute', 'System.Management.Automation.ValidateSetAttribute')
        })
    if ($vsAttrs.Count -ne 1) { return [pscustomobject]@{ Comparable = $false; Values = $null } }

    $attr = $vsAttrs[0]
    $positionals = [System.Collections.Generic.List[object]]::new()
    foreach ($pa in $attr.PositionalArguments) {
        if ($pa -is [System.Management.Automation.Language.ArrayLiteralAst]) {
            foreach ($el in $pa.Elements) { $positionals.Add($el) }
        } else {
            $positionals.Add($pa)
        }
    }
    if ($positionals.Count -eq 0) { return [pscustomobject]@{ Comparable = $false; Values = $null } }

    $values = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($pa in $positionals) {
        if (-not ($pa -is [System.Management.Automation.Language.StringConstantExpressionAst])) {
            return [pscustomobject]@{ Comparable = $false; Values = $null }
        }
        [void]$values.Add(([string]$pa.Value).Trim())
    }
    return [pscustomobject]@{ Comparable = $true; Values = $values }
}

function Get-MimirScriptParamSurface {
    <#
      Extracts the parameter surface from the root ScriptBlock's TOP-LEVEL ParamBlock
      ($ast.ParamBlock), NEVER a recursive FindAll(ParamBlockAst) — recursive would also pick up the
      param() of internal functions/filters (e.g. Update-KbFromXpz.example.ps1 has a top-level param()
      AND ~5 internal functions with Mandatory param()). A script with no top-level param() (function/filter
      only) has a NULL ParamBlock -> HasParamBlock=$false, with no fallback to an internal param(). CAUTION:
      [CmdletBinding()] with no param() produces a null ParamBlock (parse error); [CmdletBinding()] WITH
      an empty param() produces a non-null ParamBlock with Count 0 (zero-surface template).

      Returns [pscustomobject]@{ Parseable; HasParamBlock; Params(Dictionary OrdinalIgnoreCase);
      ParamCount; MandatoryCount }. Extracts from the AST, not from Get-Command (which injects
      CommonParameters on advanced ones).
    #>
    param([Parameter(Mandatory)][string]$ScriptPath)

    $perrs = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$null, [ref]$perrs)
    $parseable = ($null -ne $ast) -and ($null -eq $perrs -or @($perrs).Count -eq 0)

    $paramBlock = if ($null -ne $ast) { $ast.ParamBlock } else { $null }
    $hasParamBlock = ($null -ne $paramBlock)

    $params = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $mandatoryCount = 0
    if ($hasParamBlock) {
        foreach ($p in $paramBlock.Parameters) {
            $name = [string]$p.Name.VariablePath.UserPath
            if ($params.ContainsKey($name)) { continue }
            $mandatory = Test-MimirParamAstMandatory -ParameterAst $p
            $vs = Get-MimirParamAstValidateSet -ParameterAst $p
            $params[$name] = [pscustomobject]@{
                Name                  = $name
                Mandatory             = $mandatory
                ValidateSetComparable = $vs.Comparable
                ValidateSetValues     = $vs.Values
            }
            if ($mandatory) { $mandatoryCount++ }
        }
    }

    return [pscustomobject]@{
        Parseable      = $parseable
        HasParamBlock  = $hasParamBlock
        Params         = $params
        ParamCount     = $params.Count
        MandatoryCount = $mandatoryCount
    }
}

function Get-MimirWrapperSurfaceFinding {
    <#
      Compares the LOCAL wrapper's surface against the canonical TEMPLATE. Returns
      [pscustomobject]@{ Blocking; Advisory } where each item is @{ Reason; Detail }.
        Blocking (-> INVENTORY_CUSTOMIZED reason=surface_mismatch): mandatory_param_missing,
          mandatory_downgraded, no_param_block (when the template has a mandatory one).
        Advisory (-> INVENTORY_SURFACE_ADVISORY, outside the aggregator's pendency regex):
          optional_param_missing, validateset_reduced (SET DIFFERENCE template-local),
          optional_promoted_to_mandatory, extra_mandatory_added, no_param_block (template has >=1 param,
          all optional).
      QUIET: extra optional param; local ValidateSet is a superset/removed/not comparable; template
      is zero-surface with nothing mandatory; either side not parseable (conservative — a broken wrapper
      is caught by another gate).
    #>
    param(
        [Parameter(Mandatory)][string]$TemplatePath,
        [Parameter(Mandatory)][string]$LocalPath
    )
    $blocking = [System.Collections.Generic.List[object]]::new()
    $advisory = [System.Collections.Generic.List[object]]::new()

    $template = Get-MimirScriptParamSurface -ScriptPath $TemplatePath
    $local = Get-MimirScriptParamSurface -ScriptPath $LocalPath

    if (-not $template.Parseable -or -not $local.Parseable) {
        return [pscustomobject]@{ Blocking = @(); Advisory = @() }
    }

    # LOCAL with no top-level param() -> no_param_block; severity per the TEMPLATE's surface.
    if (-not $local.HasParamBlock) {
        if ($template.MandatoryCount -gt 0) {
            $blocking.Add(@{ Reason = 'no_param_block'; Detail = '' })
        } elseif ($template.ParamCount -gt 0) {
            $advisory.Add(@{ Reason = 'no_param_block'; Detail = '' })
        }
        return [pscustomobject]@{ Blocking = @($blocking); Advisory = @($advisory) }
    }

    foreach ($mName in @($template.Params.Keys)) {
        $mp = $template.Params[$mName]
        if (-not $local.Params.ContainsKey($mName)) {
            if ($mp.Mandatory) {
                $blocking.Add(@{ Reason = 'mandatory_param_missing'; Detail = ('-{0}' -f $mp.Name) })
            } else {
                $advisory.Add(@{ Reason = 'optional_param_missing'; Detail = ('-{0}' -f $mp.Name) })
            }
            continue
        }
        $lp = $local.Params[$mName]
        if ($mp.Mandatory -and -not $lp.Mandatory) {
            $blocking.Add(@{ Reason = 'mandatory_downgraded'; Detail = ('-{0}' -f $mp.Name) })
        } elseif (-not $mp.Mandatory -and $lp.Mandatory) {
            $advisory.Add(@{ Reason = 'optional_promoted_to_mandatory'; Detail = ('-{0}' -f $mp.Name) })
        }
        if ($mp.ValidateSetComparable -and $lp.ValidateSetComparable) {
            $missing = [System.Collections.Generic.List[string]]::new()
            foreach ($v in $mp.ValidateSetValues) {
                if (-not $lp.ValidateSetValues.Contains($v)) { $missing.Add($v) }
            }
            if ($missing.Count -gt 0) {
                $sorted = @($missing | Sort-Object)
                $advisory.Add(@{ Reason = 'validateset_reduced'; Detail = ('-{0} [{1}]' -f $mp.Name, ($sorted -join ', ')) })
            }
        }
    }

    foreach ($lName in @($local.Params.Keys)) {
        if ($template.Params.ContainsKey($lName)) { continue }
        $lp = $local.Params[$lName]
        if ($lp.Mandatory) {
            $advisory.Add(@{ Reason = 'extra_mandatory_added'; Detail = ('-{0}' -f $lp.Name) })
        }
    }

    return [pscustomobject]@{ Blocking = @($blocking); Advisory = @($advisory) }
}
