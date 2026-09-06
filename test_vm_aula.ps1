<#
.SYNOPSIS
    Restores VM-AULA to its newest checkpoint and stages the setup-test files.

.DESCRIPTION
    The script restores the most recently created checkpoint before starting the
    VM. It then uses PowerShell Direct to copy the installer files to the
    specified guest directory. Run it from an elevated PowerShell account that
    has Hyper-V authorization for VM-AULA.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$VMName = 'VM-AULA',

    [string]$GuestUserName = 'analuisa',

    [string]$DestinationPath = 'C:\Users\Public\Documents\PythonSetupTest',

    [ValidateRange(30, 600)]
    [int]$StartupTimeoutSeconds = 180
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Stage {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host ''
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Get-RequiredSourceFiles {
    $requiredFiles = @(
        (Join-Path $PSScriptRoot 'setup_python_environment.ps1'),
        (Join-Path $PSScriptRoot 'run_setup_python_environment.bat'),
        (Join-Path $PSScriptRoot 'VSCodeUserSetup-x64-1.136.0.exe')
    )

    $missing = @($requiredFiles | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
    if ($missing.Count -gt 0) {
        throw "Required staging files are missing:`n$($missing -join "`n")"
    }

    # Python installers are optional: when present, stage every x64 installer
    # beside the setup script so setup_python_environment.ps1 can use the one
    # matching its requested Python version without downloading it with winget.
    $localPythonInstallers = @(Get-ChildItem `
        -LiteralPath $PSScriptRoot `
        -Filter 'python-*-amd64.exe' `
        -File `
        -ErrorAction SilentlyContinue |
        Sort-Object Name)

    if ($localPythonInstallers.Count -gt 0) {
        Write-Host ("Local Python installers to stage: {0}" -f ($localPythonInstallers.Name -join ', ')) -ForegroundColor Green
    }
    else {
        Write-Host 'No local Python installer found; the guest setup will fall back to winget.' -ForegroundColor Yellow
    }

    return @($requiredFiles + $localPythonInstallers.FullName)
}

function Connect-GuestSession {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][pscredential]$Credential,
        [Parameter(Mandatory)][int]$TimeoutSeconds
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        try {
            return New-PSSession -VMName $Name -Credential $Credential -ErrorAction Stop
        }
        catch {
            Start-Sleep -Seconds 5
        }
    } while ((Get-Date) -lt $deadline)

    throw "PowerShell Direct did not become available on '$Name' within $TimeoutSeconds seconds. Confirm that the guest supports PowerShell Direct and that '$GuestUserName' can sign in."
}

$sourceFiles = Get-RequiredSourceFiles
$vm = Get-VM -Name $VMName -ErrorAction Stop
$snapshot = Get-VMSnapshot -VMName $VMName -ErrorAction Stop |
    Sort-Object CreationTime -Descending |
    Select-Object -First 1

if ($null -eq $snapshot) {
    throw "VM '$VMName' has no checkpoint to restore."
}

if ($vm.State -ne 'Off') {
    throw "VM '$VMName' must be off before restoring a checkpoint. Its current state is '$($vm.State)'."
}

Write-Stage "Restoring latest checkpoint: $($snapshot.Name) ($($snapshot.CreationTime))"
if ($PSCmdlet.ShouldProcess($VMName, "Restore checkpoint '$($snapshot.Name)'")) {
    Restore-VMSnapshot -VMSnapshot $snapshot -Confirm:$false
}

Write-Stage "Starting $VMName"
if ($PSCmdlet.ShouldProcess($VMName, 'Start virtual machine')) {
    Start-VM -Name $VMName | Out-Null
}

Write-Stage "Requesting credentials for $GuestUserName"
$credential = Get-Credential -UserName $GuestUserName -Message "Enter the password for $GuestUserName in $VMName"
$session = $null

try {
    Write-Stage 'Waiting for PowerShell Direct'
    $session = Connect-GuestSession -Name $VMName -Credential $credential -TimeoutSeconds $StartupTimeoutSeconds

    Write-Stage "Creating guest destination: $DestinationPath"
    Invoke-Command -Session $session -ScriptBlock {
        param([string]$Path)
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    } -ArgumentList $DestinationPath

    # Use a fresh installer filename on every run. If a previous VS Code setup
    # window is still open, Windows keeps its EXE locked and would otherwise
    # prevent replacing the incomplete copy.
    $copySuffix = Get-Date -Format 'yyyyMMddHHmmss'
    $remoteFiles = @{}
    foreach ($sourceFile in $sourceFiles) {
        $sourceName = Split-Path -Leaf $sourceFile
        $remoteName = if ($sourceName -like 'VSCodeUserSetup*.exe') {
            '{0}-staged-{1}{2}' -f [System.IO.Path]::GetFileNameWithoutExtension($sourceName), $copySuffix, [System.IO.Path]::GetExtension($sourceName)
        }
        else {
            $sourceName
        }
        $remoteFiles[$remoteName] = $sourceFile
    }

    Write-Stage 'Copying setup files to the guest'
    foreach ($remoteName in $remoteFiles.Keys) {
        Copy-Item -LiteralPath $remoteFiles[$remoteName] -Destination (Join-Path $DestinationPath $remoteName) -ToSession $session -Force
    }

    Write-Stage 'Verifying copied file hashes'
    $sourceHashes = @{}
    foreach ($remoteName in $remoteFiles.Keys) {
        $sourceHashes[$remoteName] = (Get-FileHash -LiteralPath $remoteFiles[$remoteName] -Algorithm SHA256).Hash
    }

    $guestHashes = Invoke-Command -Session $session -ScriptBlock {
        param([string]$Path, [string[]]$FileNames)

        foreach ($fileName in $FileNames) {
            [pscustomobject]@{
                Name   = $fileName
                SHA256 = (Get-FileHash -LiteralPath (Join-Path $Path $fileName) -Algorithm SHA256).Hash
            }
        }
    } -ArgumentList $DestinationPath, @($sourceHashes.Keys)

    if (@($guestHashes).Count -ne $remoteFiles.Count) {
        throw "File integrity check did not return a hash for every copied file in '$VMName'. Run this staging script again before using the copied installer."
    }

    foreach ($guestHash in $guestHashes) {
        if ($sourceHashes[$guestHash.Name] -ne $guestHash.SHA256) {
            throw "File integrity check failed after copying '$($guestHash.Name)' to '$VMName'. Run this staging script again before using the copied installer."
        }
    }

    Write-Host ''
    Write-Host "Files staged in $VMName at: $DestinationPath" -ForegroundColor Green
}
finally {
    if ($null -ne $session) {
        Remove-PSSession -Session $session
    }
}
