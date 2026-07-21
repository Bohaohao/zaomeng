param(
    [string]$DataPath = (Join-Path $PSScriptRoot '..\data\first-six-hours-v1.json')
)

$ErrorActionPreference = 'Stop'
$checks = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    $script:checks++
    if (-not $Condition) { throw $Message }
}

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    $script:checks++
    if ($Actual -cne $Expected) { throw "$Message. Expected: $Expected. Actual: $Actual" }
}

function Assert-SetEquals {
    param([string[]]$Actual, [string[]]$Expected, [string]$Message)
    $script:checks++
    $actualUnique = @($Actual | Sort-Object -Unique)
    $expectedUnique = @($Expected | Sort-Object -Unique)
    if ($actualUnique.Count -ne $Actual.Count -or $actualUnique.Count -ne $expectedUnique.Count -or
        (@(Compare-Object -CaseSensitive -ReferenceObject $expectedUnique -DifferenceObject $actualUnique).Count -ne 0)) {
        throw $Message
    }
}

$resolvedDataPath = (Resolve-Path -LiteralPath $DataPath -ErrorAction Stop).Path
try {
    $data = Get-Content -Raw -Encoding UTF8 -LiteralPath $resolvedDataPath | ConvertFrom-Json -ErrorAction Stop
}
catch {
    throw "first-six-hours data is not valid JSON: $($_.Exception.Message)"
}

$packageRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$configPath = Join-Path $packageRoot 'lua\growth_config.lua'
$runtimePath = Join-Path $packageRoot 'lua\growth_runtime.lua'
$testPath = Join-Path $PSScriptRoot 'test_growth_runtime.lua'

Assert-Equal $data.schema_version 1 'schema_version must be 1'
Assert-Equal $data.package_status 'offline_candidate_simulation_not_adopted' 'package must explicitly be an unadopted offline candidate'
Assert-Equal $data.execution_status 'offline_simulation_ready' 'package execution readiness must stay offline only'
Assert-Equal $data.production_gate 'closed' 'live production gate must remain closed'
Assert-True (-not [bool]$data.runtime_handoff) 'candidate package may not enable runtime handoff'
Assert-Equal $data.resource_table_status 'offline_candidate_not_adopted' 'resource table must remain a candidate'
Assert-Equal $data.resource_table_version 'f6h-v1' 'resource table version must be stable'
Assert-Equal $data.source_of_truth 'implementation/growth/lua/growth_config.lua' 'source of truth must be explicit'
Assert-True (Test-Path -LiteralPath $configPath -PathType Leaf) 'growth config is missing'
Assert-True (Test-Path -LiteralPath $runtimePath -PathType Leaf) 'growth runtime is missing'
Assert-True (Test-Path -LiteralPath $testPath -PathType Leaf) 'growth Lua regression test is missing'

$minutes = @($data.scope.active_minutes)
Assert-True ($minutes.Count -eq 2) 'active minute range must have two endpoints'
Assert-Equal $minutes[0] 0 'first-six-hours range must start at minute 0'
Assert-Equal $minutes[1] 360 'first-six-hours range must end at minute 360'
Assert-True ([bool]$data.scope.wall_clock_excluded) 'active time must exclude wall-clock idle time'
Assert-SetEquals @($data.scope.player_counts | ForEach-Object { [string]$_ }) @('1','2','3','4') 'player-count coverage must be 1–4'
Assert-SetEquals @($data.scope.level_range | ForEach-Object { [string]$_ }) @('1','20') 'offline scope must remain Lv1–20'
Assert-Equal $data.scope.chapter 'huaguoshan' 'offline scope must remain Huaguoshan'

Assert-Equal $data.experience_policy.party_policy_id 'F6H_PARTY_FULL_QUALIFIED_XP_V1' 'party XP policy must be unique'
Assert-Equal $data.experience_policy.level_20_target_active_minute 55 'Lv20 target minute drifted'
Assert-Equal $data.experience_policy.level_20_cumulative_xp 9485 'Lv20 cumulative XP drifted'
Assert-Equal $data.public_boss_policy.candidate_policy_id 'P1_PUBLIC_CHEST_BALANCED_CONTRIBUTION' 'simulation must identify its P1 candidate without declaring a final policy'
Assert-Equal $data.public_boss_policy.source_decision_id 'ECO-P1-001' 'P1 simulation candidate must retain its source decision'
Assert-Equal $data.public_boss_policy.source_decision_status 'conflict' 'P1 simulation candidate must retain its unresolved decision status'
$acceptanceCriteriaText = @($data.acceptance_criteria) -join "`n"
Assert-True ($acceptanceCriteriaText -notmatch '(?i)\bfinal P1 policy\b') 'candidate acceptance criteria may not claim a final P1 policy'
Assert-True ($acceptanceCriteriaText -match [regex]::Escape('one named P1 conflict candidate is used only by the offline qualification and settlement simulation; it is not a final policy')) 'candidate acceptance criteria must preserve the named offline-only P1 status'
Assert-True ($data.public_boss_policy.rare_drop -match 'separate') 'rare eligibility must remain separate from chest'
Assert-True ($data.public_boss_policy.pity -match 'settled') 'pity must require a settled roll miss'

$teamRaidPolicy = $data.team_raid_policy
Assert-Equal $teamRaidPolicy.policy_id 'F6H_TEAM_RAID_RARE_ELIGIBILITY_V1' 'team-raid rare policy must be stable'
Assert-Equal $teamRaidPolicy.snapshot_schema_version 1 'team-raid snapshot schema must be stable'
Assert-SetEquals @($teamRaidPolicy.member_count_range | ForEach-Object { [string]$_ }) @('1','4') 'team-raid snapshot must support exactly one to four members'
Assert-SetEquals @($teamRaidPolicy.required_snapshot_fields | ForEach-Object { [string]$_ }) @(
    'schema_version','policy_id','snapshot_id','raid_instance_id','completion_event_id',
    'profile_key','completed','rare_clear_attested','authority_proof_ref','members'
) 'team-raid snapshot required fields drifted'
Assert-SetEquals @($teamRaidPolicy.required_member_fields | ForEach-Object { [string]$_ }) @(
    'owner_id','joined_before_lock','present_at_completion','actor_alive_at_completion',
    'contribution_attested','rare_clear_attested'
) 'team-raid member required fields drifted'
Assert-True ($teamRaidPolicy.rare_drop -match 'authority-attested') 'team-raid rare eligibility must stay authority-attested'

$milestones = @($data.first_five_build_milestones)
Assert-True ($milestones.Count -eq 5) 'exactly five first-build milestones are required'
Assert-SetEquals @($milestones | ForEach-Object { [string]$_.key }) @(
    'SKILL_SECOND_ACTIVE','CORE_ROUTE','FIRST_EQUIPMENT','FIRST_ENHANCEMENT','FIRST_ARTIFACT'
) 'first-build milestone keys drifted'
Assert-True ((@($milestones | Where-Object { $_.target_active_minute -gt 360 }).Count) -eq 0) 'milestone may not exceed six-hour scope'

$expectedProfiles = @(
    'HG_DROP_MOUNTAIN_COMMON','HG_DROP_MOUNTAIN_ELITE','HG_DROP_MOUNTAIN_MAJOR',
    'HG_DROP_WATERFALL_COMMON','HG_DROP_WATERFALL_ELITE','HG_DROP_MACAQUE_PUBLIC',
    'HG_DROP_PEACH_COMMON','HG_DROP_PEACH_MAJOR','HG_DROP_CAVE_COMMON','HG_DROP_CAVE_MAJOR',
    'HG_DROP_SEVENSTAR_COMMON','HG_DROP_SEVENSTAR_ELITE','HG_DROP_SEVENSTAR_MAJOR',
    'HG_DROP_PENG_OPTIONAL','HG_DROP_EASTSEA_COMMON','HG_DROP_EASTSEA_ELITE',
    'HG_DROP_JIAO_PUBLIC','HG_DROP_SHARK_PUBLIC','HG_DROP_DRAGON_OLD',
    'HG_DROP_DRAGON_REVERSE','HG_DROP_OX_RAID'
)
Assert-SetEquals @($data.covered_reward_profiles | ForEach-Object { [string]$_ }) $expectedProfiles 'all Huaguoshan reward profiles must be covered exactly once'
Assert-SetEquals @($data.currency_boundary.active | ForEach-Object { [string]$_ }) @('CUR_GOLD','CUR_RAID_MARK') 'active six-hour currency boundary drifted'
Assert-SetEquals @($data.currency_boundary.reserved_for_later | ForEach-Object { [string]$_ }) @('CUR_TOWER_TOKEN') 'tower currency must remain reserved'
Assert-True (-not [bool]$data.currency_boundary.team_wallet) 'team wallet must remain disabled'
Assert-True (-not [bool]$data.currency_boundary.trade) 'trade must remain disabled'

$configText = Get-Content -Raw -Encoding UTF8 -LiteralPath $configPath
Assert-True ($configText -match "resource_table_version = 'f6h-v1'") 'Lua config must use the JSON resource version'
Assert-True ($configText -match "offline_candidate_simulation_not_adopted") 'Lua config must keep the simulation candidate-only'
Assert-True ($configText -match "candidate_policy_id = 'P1_PUBLIC_CHEST_BALANCED_CONTRIBUTION'") 'Lua config must identify the P1 candidate without declaring it final'
Assert-True ($configText -match "F6H_TEAM_RAID_RARE_ELIGIBILITY_V1") 'Lua config must use the team-raid rare policy'
Assert-True ($configText -match "bundle = 'ox_raid', scope = 'team_raid'") 'Ox raid must use the dedicated team-raid qualification path'
Assert-True ($configText -notmatch '\by3\.') 'offline growth config must not call Y3 APIs'
$runtimeText = Get-Content -Raw -Encoding UTF8 -LiteralPath $runtimePath
Assert-True ($runtimeText -notmatch '\by3\.') 'offline growth runtime must not call Y3 APIs'
Assert-True ($runtimeText -match 'reward_staging_state') 'reward settlement must stage its state changes'
Assert-True ($runtimeText -match 'team-qualification-snapshot-required') 'runtime must require an authority-attested team snapshot'

Write-Output "PASS: first-six-hours offline package validation ($checks checks)"
