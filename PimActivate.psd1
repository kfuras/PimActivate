@{
    RootModule        = 'PimActivate.psm1'
    ModuleVersion     = '0.1.1'
    GUID              = '3aed46cb-d2e2-484a-bc17-4b4e5306643b'
    Author            = 'Kjetil Furås'
    Description       = 'Activate eligible Azure PIM roles by resource name.'
    PowerShellVersion = '5.1'
    RequiredModules   = @('Az.Accounts')
    # Listed explicitly so autoloading finds them without importing the module first
    FunctionsToExport = @('Enable-PimRole', 'Connect-PimAuthContext')
    AliasesToExport   = @('pim', 'pim-login')
    CmdletsToExport   = @()
    VariablesToExport = @()
    PrivateData       = @{
        PSData = @{
            Tags       = @('Azure', 'PIM', 'PrivilegedIdentityManagement', 'RBAC')
            ProjectUri = 'https://github.com/kfuras/PimActivate'
            LicenseUri = 'https://github.com/kfuras/PimActivate/blob/main/LICENSE'
        }
    }
}
