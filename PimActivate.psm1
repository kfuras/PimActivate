$script:ArmUrl = 'https://management.azure.com'

function Test-PimConnection {
    if (-not (Get-AzContext)) { return $false }
    try {
        # Throws when the cached sign-in has expired (e.g. Conditional Access sign-in frequency)
        $null = Get-AzAccessToken -ResourceUrl $script:ArmUrl -AsSecureString -ErrorAction Stop -WarningAction SilentlyContinue
        $true
    }
    catch {
        $false
    }
}

function Get-PimPrincipalId {
    $context = Get-AzContext
    if (-not $context) { throw 'Not signed in to Azure. Run Connect-PimAuthContext (pim-login).' }

    # HomeAccountId is "<objectId>.<tenantId>" for the signed-in user
    $homeAccountId = $context.Account.ExtendedProperties['HomeAccountId']
    if ($homeAccountId) { return ($homeAccountId -split '\.')[0] }

    $response = Invoke-AzRestMethod -Uri 'https://graph.microsoft.com/v1.0/me?$select=id' -ResourceId 'https://graph.microsoft.com/' -Method GET
    if ($response.StatusCode -ne 200) { throw "Could not look up the signed-in user ($($response.StatusCode)): $($response.Content)" }
    ($response.Content | ConvertFrom-Json).id
}

function Get-PimEligibility {
    param(
        [Parameter(Mandatory)] [string] $Name
    )

    $uri = $script:ArmUrl + '/providers/Microsoft.Authorization/roleEligibilityScheduleInstances?api-version=2020-10-01&$filter=asTarget()'
    $eligibilities = while ($uri) {
        $response = Invoke-AzRestMethod -Uri $uri -Method GET
        if ($response.StatusCode -ne 200) { throw "Listing eligible roles failed ($($response.StatusCode)): $($response.Content)" }
        $page = $response.Content | ConvertFrom-Json
        $page.value
        $uri = $page.nextLink
    }

    $eligibilities |
        Where-Object { $_.properties.expandedProperties.scope.displayName -like "*$Name*" } |
        Sort-Object { $_.properties.expandedProperties.scope.displayName }, { $_.properties.scope }
}

function ConvertFrom-PimSelection {
    param(
        [Parameter(Mandatory)] [string] $Selection,
        [Parameter(Mandatory)] [int] $Count
    )

    if ($Selection -eq 'a') { return 1..$Count }

    $indexes = foreach ($part in ($Selection -split '[,\s]+' | Where-Object { $_ })) {
        if ($part -match '^(\d+)-(\d+)$') { [int]$Matches[1]..[int]$Matches[2] }
        elseif ($part -match '^\d+$') { [int]$part }
        else { Write-Warning "Ignoring '$part'" }
    }
    # Drop out-of-range numbers; index -1 would silently pick the last item
    $indexes | Select-Object -Unique | Where-Object { $_ -ge 1 -and $_ -le $Count }
}

function Invoke-PimActivation {
    param(
        [Parameter(Mandatory)] $Eligibility,
        [Parameter(Mandatory)] [string] $PrincipalId,
        [Parameter(Mandatory)] [int] $Hours,
        [Parameter(Mandatory)] [string] $Justification
    )

    $properties = $Eligibility.properties
    $status = $null
    $authContext = $null

    $body = @{
        properties = @{
            principalId                     = $PrincipalId
            roleDefinitionId                = $properties.roleDefinitionId
            requestType                     = 'SelfActivate'
            linkedRoleEligibilityScheduleId = $properties.roleEligibilityScheduleId
            justification                   = $Justification
            scheduleInfo                    = @{ expiration = @{ type = 'AfterDuration'; duration = "PT$($Hours)H" } }
        }
    } | ConvertTo-Json -Depth 5
    $uri = "$script:ArmUrl$($properties.scope)/providers/Microsoft.Authorization/roleAssignmentScheduleRequests/$((New-Guid).Guid)?api-version=2020-10-01"

    $response = Invoke-AzRestMethod -Uri $uri -Method PUT -Payload $body
    if ($response.StatusCode -in 200, 201) {
        $status = ($response.Content | ConvertFrom-Json).properties.status
    }
    else {
        $message = $response.Content
        if ($message -match 'RoleAssignmentExists') {
            $status = 'AlreadyActive'
        }
        # The error carries the required context as URL-encoded claims JSON, e.g. "value":"c1"
        elseif ($message -match 'AcrsValidationFailed' -and $message -match 'value(?:"|%22)\s*(?::|%3A)\s*(?:"|%22)(c\d+)') {
            $status = 'NeedsAuthContext'
            $authContext = $Matches[1]
        }
        else {
            $status = 'Failed'
            Write-Error "$($properties.expandedProperties.scope.displayName): $message"
        }
    }

    $Eligibility | Select-Object -Property @(
        @{ Name = 'Resource'; Expression = { $_.properties.expandedProperties.scope.displayName } }
        @{ Name = 'ResourceGroup'; Expression = { ($_.properties.scope -split '/')[4] } }
        @{ Name = 'Role'; Expression = { $_.properties.expandedProperties.roleDefinition.displayName } }
        @{ Name = 'Status'; Expression = { $status } }
        @{ Name = 'AuthContext'; Expression = { $authContext } }
        @{ Name = 'Eligibility'; Expression = { $Eligibility } }
    )
}

function Enable-PimRole {
    <#
    .SYNOPSIS
    Activates eligible Azure PIM roles, picked from a numbered list by resource name.

    .DESCRIPTION
    Lists your eligible Azure resource role assignments whose resource name contains -Name,
    lets you pick which to activate, and activates them. If a role requires a Conditional
    Access authentication context (e.g. c1), it signs you in again with MFA and retries.
    Requires the Az.Accounts module. Signs in automatically if the Azure sign-in is missing or expired.

    .PARAMETER Name
    Text to match anywhere in the resource name. Wildcards are allowed. Default: all.

    .PARAMETER Hours
    Activation duration in hours. Values above the role's PIM policy maximum fail.

    .PARAMETER Justification
    Justification recorded on the activation.

    .PARAMETER Select
    Pick roles without the prompt, e.g. '1,3,5-7' or 'a' for all.

    .EXAMPLE
    pim prod
    Lists eligible roles with "prod" in the resource name and prompts for which to activate.

    .EXAMPLE
    pim prod -Hours 1 -Justification "Ticket 1234"

    .EXAMPLE
    pim rg-web -Select a -WhatIf
    Shows which roles would be activated without activating them.

    .NOTES
    Alias: pim
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [Alias('pim')]
    param(
        [Parameter(Position = 0)]
        [string] $Name = '*',

        [ValidateRange(1, 24)]
        [int] $Hours = 8,

        [ValidateNotNullOrEmpty()]
        [string] $Justification = 'Ops work',

        [ValidatePattern('^(a|[\d,\s-]+)$')]
        [string[]] $Select
    )

    if (-not (Test-PimConnection)) {
        Write-Host 'Azure sign-in missing or expired, opening sign-in...'
        Connect-PimAuthContext
    }
    $principalId = Get-PimPrincipalId

    $items = @(Get-PimEligibility -Name $Name)
    if ($items.Count -eq 0) {
        Write-Warning "No eligible assignments match '$Name'."
        return
    }

    Write-Host ('{0,3}  {1,-34} {2,-40} {3}' -f '#', 'Resource', 'Role', 'Resource group')
    for ($i = 0; $i -lt $items.Count; $i++) {
        $properties = $items[$i].properties
        Write-Host ('{0,3}  {1,-34} {2,-40} {3}' -f ($i + 1), $properties.expandedProperties.scope.displayName, $properties.expandedProperties.roleDefinition.displayName, ($properties.scope -split '/')[4])
    }

    # Separate variable: assigning to $Select would re-run its ValidatePattern and reject an empty answer
    $selection = $Select -join ','
    if (-not $selection) {
        $selection = Read-Host "`nSelect (e.g. 1,3,5-7 or 'a' for all, Enter to cancel)"
        if (-not $selection) { return }
    }
    $picked = ConvertFrom-PimSelection -Selection $selection -Count $items.Count | ForEach-Object { $items[$_ - 1] }

    $activation = @{ PrincipalId = $principalId; Hours = $Hours; Justification = $Justification }
    $operation = "Activate for $Hours hour(s)"
    $results = @(foreach ($eligibility in $picked) {
        $p = $eligibility.properties
        $target = '{0} ({1}, {2})' -f $p.expandedProperties.scope.displayName, $p.expandedProperties.roleDefinition.displayName, ($p.scope -split '/')[4]
        # Constrained Language Mode blocks $PSCmdlet.ShouldProcess(), so honor -WhatIf/-Confirm via their preference variables
        if ($WhatIfPreference) {
            Write-Host "What if: Performing the operation `"$operation`" on target `"$target`"."
            continue
        }
        if ($ConfirmPreference -eq 'Low' -and (Read-Host "$operation on $target? [y/N]") -notmatch '^y') {
            continue
        }
        Invoke-PimActivation -Eligibility $eligibility @activation
    })

    $needContext = @($results | Where-Object Status -EQ 'NeedsAuthContext')
    if ($needContext.Count) {
        $context = $needContext[0].AuthContext
        Write-Host "`n$($needContext.Count) role(s) need auth context '$context'. Signing in again, complete MFA..."
        Connect-PimAuthContext -Context $context
        $retried = foreach ($result in $needContext) { Invoke-PimActivation -Eligibility $result.Eligibility @activation }
        $results = @($results | Where-Object Status -NE 'NeedsAuthContext') + @($retried)
    }

    $results | Select-Object -Property Status, Resource, ResourceGroup, Role
}

function Connect-PimAuthContext {
    <#
    .SYNOPSIS
    Signs in to Azure (Connect-AzAccount), optionally satisfying a Conditional Access authentication context.

    .PARAMETER Context
    Authentication context ID required by the PIM policy, e.g. c1. Omit for a plain sign-in.

    .EXAMPLE
    pim-login -Context c1

    .NOTES
    Alias: pim-login
    #>
    [CmdletBinding()]
    [Alias('pim-login')]
    param(
        [ValidatePattern('^c\d+$')]
        [string] $Context
    )

    # Sign-in must happen even when the caller used -WhatIf/-Confirm
    $connect = @{ ErrorAction = 'Stop'; WhatIf = $false; Confirm = $false }

    if ($Context) {
        $claims = '{"access_token":{"acrs":{"essential":true,"value":"' + $Context + '"}}}'
        if ($ExecutionContext.SessionState.LanguageMode -eq 'FullLanguage') {
            $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($claims))
        }
        else {
            # Constrained Language Mode blocks [Convert]; certutil can still encode
            $inFile = New-TemporaryFile
            $outFile = "$($inFile.FullName).b64"
            try {
                Set-Content -Path $inFile.FullName -Value $claims -NoNewline -Encoding ascii
                certutil -f -encode $inFile.FullName $outFile | Out-Null
                $encoded = (Get-Content -Path $outFile | Where-Object { $_ -notmatch '^-----' }) -join ''
            }
            finally {
                Remove-Item -Path $inFile.FullName, $outFile -ErrorAction SilentlyContinue
            }
        }
        $connect.ClaimsChallenge = $encoded
    }

    $current = Get-AzContext
    if ($current) {
        $connect.Tenant = $current.Tenant.Id
        # Passing the current subscription skips the interactive subscription picker
        if ($current.Subscription) { $connect.Subscription = $current.Subscription.Id }
    }

    # Browser sign-in instead of the Windows account picker (WAM), and no subscription prompt; this session only
    $null = Update-AzConfig -EnableLoginByWam $false -LoginExperienceV2 Off -Scope Process -WhatIf:$false -WarningAction SilentlyContinue
    $null = Connect-AzAccount @connect -WarningAction SilentlyContinue -InformationAction SilentlyContinue
}

Export-ModuleMember -Function Enable-PimRole, Connect-PimAuthContext -Alias pim, pim-login
