# PimActivate

Activate eligible Azure PIM (Privileged Identity Management) role assignments
from the command line, picked by resource name.

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

- `pim <text>` lists **every** PIM role you are eligible for whose resource
  name contains `<text>` (not case-sensitive), across all subscriptions. The
  resource can be a subscription, resource group or single resource. Nothing
  is activated until you pick from the list.
- `pim` with no text lists all your eligible roles.
- Signs in with the browser when your Azure sign-in is missing or expired.
- Handles Conditional Access authentication contexts (e.g. `c1`): signs you in
  again with MFA and retries.

## Requirements

- PowerShell 7 (Windows PowerShell 5.1 may work)
- [Az.Accounts](https://www.powershellgallery.com/packages/Az.Accounts)

## Install

From the [PowerShell Gallery](https://www.powershellgallery.com/packages/PimActivate)
(installs Az.Accounts too):

```powershell
Install-Module PimActivate -Scope CurrentUser
```

Or from source:

```powershell
Install-Module Az.Accounts -Scope CurrentUser
$modules = "$HOME\Documents\PowerShell\Modules"
git clone https://github.com/kfuras/PimActivate "$modules\PimActivate"
```

The module loads automatically the first time you run `pim`.

## Usage

```powershell
# List every eligible role with "prod" in the resource name, then pick
pim prod

# Custom duration and justification
pim prod -Hours 1 -Justification 'Ticket 1234'

# Pick without the prompt
pim rg-web -Select 1,3

# Show what would be activated
pim -Select a -WhatIf

# Sign in for an authentication context up front
pim-login -Context c1
```

Without `-Hours` and `-Justification`, roles are activated for **8 hours**
with the justification **`Ops work`**.

| Parameter       | Default    | Description                                  |
| --------------- | ---------- | -------------------------------------------- |
| `Name`          | all        | Text to match in resource name; wildcards OK |
| `Hours`         | `8`        | 1-24, capped by the role's PIM policy        |
| `Justification` | `Ops work` | Recorded on the activation                   |
| `Select`        | none       | `1,3,5-7` or `a` (all); skips the prompt     |

See `Get-Help pim -Full` for details.

## License

[MIT](LICENSE)
