@{
    RootModule        = 'PimActivate.psm1'
    ModuleVersion     = '0.1.2'
    GUID              = '3aed46cb-d2e2-484a-bc17-4b4e5306643b'
    Author            = 'Kjetil Furås'
    Copyright         = '(c) 2026 Kjetil Furås. MIT License.'
    Description       = 'Activate your eligible Azure PIM (Privileged Identity Management) resource roles from the command line in seconds. Type "pim <text>" to list every eligible Azure RBAC role whose subscription, resource group or resource name contains the text, pick from a numbered menu (1,3,5-7 or all), and activate for a chosen duration with a justification. Handles Conditional Access authentication contexts (step-up MFA) automatically by signing you in again and retrying. Browser sign-in, -WhatIf support, works in Constrained Language Mode, and only depends on Az.Accounts.'
    PowerShellVersion = '5.1'
    RequiredModules   = @('Az.Accounts')
    # Listed explicitly so autoloading finds them without importing the module first
    FunctionsToExport = @('Enable-PimRole', 'Connect-PimAuthContext')
    AliasesToExport   = @('pim', 'pim-login')
    CmdletsToExport   = @()
    VariablesToExport = @()
    PrivateData       = @{
        PSData = @{
            Tags         = @(
                'Azure', 'PIM', 'PrivilegedIdentityManagement', 'RBAC', 'AzureRBAC',
                'JIT', 'JustInTime', 'RoleActivation', 'AuthenticationContext',
                'ConditionalAccess', 'MFA', 'Identity', 'Security'
            )
            ProjectUri   = 'https://github.com/kfuras/PimActivate'
            LicenseUri   = 'https://github.com/kfuras/PimActivate/blob/main/LICENSE'
        }
    }
}
