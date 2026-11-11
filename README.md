# PimActivate

Activate eligible Azure PIM (Privileged Identity Management) role assignments from the command line, picked by resource name.

```text
PS> pim prod
  #  Resource              Role                                 Resource group
  1  rg-prod-web           Contributor                          rg-prod-web
  2  rg-prod-sql           Reader                               rg-prod-sql

Select (e.g. 1,3,5-7 or 'a' for all, Enter to cancel): 1

Status      Resource     ResourceGroup Role
------      --------     ------------- ----
Provisioned rg-prod-web  rg-prod-web   Contributor
```

- Lists your eligible Azure resource roles across all subscriptions you can see, filtered by resource name.
- Signs in with the browser when your Azure sign-in is missing or expired.
- Handles Conditional Access authentication contexts (e.g. `c1`): signs you in again with MFA and retries.

## Requirements

- PowerShell 7 (Windows PowerShell 5.1 may work)
- [Az.Accounts](https://www.powershellgallery.com/packages/Az.Accounts)

## Install

```powershell
Install-Module Az.Accounts -Scope CurrentUser
git clone https://github.com/kfuras/PimActivate "$HOME\Documents\PowerShell\Modules\PimActivate"
```

The module loads automatically the first time you run `pim`.

## Usage

```powershell
pim prod                                  # pick from roles with "prod" in the resource name
pim prod -Hours 1 -Justification 'Ticket 1234'
pim rg-web -Select 1,3                    # no prompt
pim -Select a -WhatIf                     # show what would be activated
pim-login -Context c1                     # sign in for an authentication context up front
```

| Parameter | Default | Description |
|---|---|---|
| `Name` | `*` | Text to match anywhere in the resource name |
| `Hours` | `8` | Activation duration (1-24, limited by the role's PIM policy) |
| `Justification` | `Ops work` | Justification recorded on the activation |
| `Select` | | `1,3,5-7` or `a` for all; skips the prompt |

See `Get-Help pim -Full` for details.

## License

[MIT](LICENSE)
