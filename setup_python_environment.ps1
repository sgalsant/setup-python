<#
.SYNOPSIS
    Prepares or checks a teaching Python environment for data analysis.

.DESCRIPTION
    - Uses the folder containing this script as the project folder by default.
    - Checks whether the requested Python version is already installed.
    - If it is missing, installs the official Python distribution with winget
      for the current user.
    - Installs/uses uv, but prevents uv from downloading its own Python build.
    - Creates .venv using the official/system Python interpreter.
    - Installs VS Code, the Python/Jupyter extensions, and project dependencies.

    Intended for Windows 11 classroom PCs without administrator privileges.
#>

[CmdletBinding(DefaultParameterSetName = 'Install', SupportsShouldProcess = $true)]
param(
    [Parameter(ParameterSetName = 'Check', Mandatory = $true)]
    [switch]$Check,

    [Parameter(ParameterSetName = 'Install')]
    [switch]$Reinstall,

    [Parameter(ParameterSetName = 'Install')]
    [switch]$IncludeExcelAndParquet,

    [Parameter(ParameterSetName = 'Install')]
    [switch]$PyData,

    [Parameter(ParameterSetName = 'Install')]
    [ValidatePattern('^3\.\d+(\.\d+)?$')]
    [string]$PythonVersion = '3.13',

    [Parameter(ParameterSetName = 'Install')]
    [Parameter(ParameterSetName = 'Check')]
    [string]$ProjectPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $Check -and -not $PyData -and -not [string]::IsNullOrWhiteSpace($ProjectPath)) {
    throw '-ProjectPath requires -PyData. The base mode does not create or modify a project.'
}

if (-not $Check -and -not $PyData -and $IncludeExcelAndParquet) {
    throw '-IncludeExcelAndParquet requires -PyData.'
}

function Get-DefaultPyDataProjectPath {
    $candidateNumber = 1
    do {
        $name = if ($candidateNumber -eq 1) { 'pydata' } else { "pydata$candidateNumber" }
        $candidate = Join-Path $PSScriptRoot $name
        $candidateNumber++
    } while (Test-Path -LiteralPath $candidate)

    return [System.IO.Path]::GetFullPath($candidate)
}

if ($PyData -and [string]::IsNullOrWhiteSpace($ProjectPath)) {
    $ProjectPath = Get-DefaultPyDataProjectPath
}
elseif (-not [string]::IsNullOrWhiteSpace($ProjectPath)) {
    $ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)
}

# Avoid the hardlink warning on classroom PCs / removable drives.
$env:UV_LINK_MODE = 'copy'

# Critical: never let uv silently download/manage another Python build.
$env:UV_PYTHON_DOWNLOADS = 'never'

$Script:UvInstallerUri = 'https://astral.sh/uv/install.ps1'
$Script:VsCodeInstallerUri = 'https://code.visualstudio.com/sha/download?build=stable&os=win32-x64-user'
$Script:RequiredExtensions = @('ms-python.python', 'ms-toolsai.jupyter')
$Script:ExtensionsDirectory = Join-Path $PSScriptRoot 'extensions'
$Script:ExtensionInstallRetries = 3
$Script:ExtensionInstallFailures = [System.Collections.Generic.List[string]]::new()
$Script:BasePackages = @('numpy', 'pandas', 'matplotlib', 'seaborn')
$Script:DevelopmentPackages = @('ipykernel', 'ruff', 'pytest')

function Write-Stage {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host ''
    Write-Host ('==> {0}' -f $Message) -ForegroundColor Cyan
}

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter()][string[]]$Arguments = @()
    )

    Write-Verbose ('Running: {0} {1}' -f $FilePath, ($Arguments -join ' '))

    # Important: show native command output in the console, but do not let it
    # become PowerShell function output. Otherwise functions that should return
    # a single path (for example PythonPath) can accidentally return an array
    # containing command output + the path, causing "cannot convert to string".
    & $FilePath @Arguments | Out-Host
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        throw ('Command failed with exit code {0}: {1} {2}' -f $exitCode, $FilePath, ($Arguments -join ' '))
    }
}

function Add-CurrentSessionPath {
    param([Parameter(Mandatory)][string]$Directory)
    if ((Test-Path -LiteralPath $Directory) -and ($env:Path -notlike "*$Directory*")) {
        $env:Path = "$Directory;$env:Path"
    }
}

function Test-PythonCandidate {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$RequestedVersion
    )

    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    try {
        $actual = & $Path -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>$null
        return (($LASTEXITCODE -eq 0) -and ($actual.Trim() -eq (($RequestedVersion -split '\.')[0..1] -join '.')))
    }
    catch {
        return $false
    }
}

function Get-SystemPythonPath {
    param([Parameter(Mandatory)][string]$RequestedVersion)

    $majorMinor = (($RequestedVersion -split '\.')[0..1] -join '.')
    $compact = $majorMinor.Replace('.', '')

    # 1) Python Launcher, if available.
    $py = Get-Command py.exe -ErrorAction SilentlyContinue
    if ($null -ne $py) {
        try {
            $candidate = (& $py.Source "-$majorMinor" -c "import sys; print(sys.executable)" 2>$null).Trim()
            if ($candidate -and (Test-PythonCandidate -Path $candidate -RequestedVersion $majorMinor)) {
                return $candidate
            }
        }
        catch {}
    }

    # 2) Common per-user and machine-wide locations.
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Programs\Python\Python$compact\python.exe"),
        (Join-Path $env:ProgramFiles "Python$compact\python.exe")
    )
    if (${env:ProgramFiles(x86)}) {
        $candidates += (Join-Path ${env:ProgramFiles(x86)} "Python$compact\python.exe")
    }

    # 3) Registry locations used by official Python installers.
    $registryRoots = @(
        'HKCU:\Software\Python\PythonCore',
        'HKLM:\Software\Python\PythonCore',
        'HKLM:\Software\WOW6432Node\Python\PythonCore'
    )
    foreach ($root in $registryRoots) {
        $installPathKey = Join-Path $root "$majorMinor\InstallPath"
        try {
            $installDir = (Get-ItemProperty -LiteralPath $installPathKey -ErrorAction Stop).'(default)'
            if ($installDir) {
                $candidates += (Join-Path $installDir 'python.exe')
            }
        }
        catch {}
    }

    # 4) PATH, but ignore the Microsoft Store execution alias.
    $pythonCommand = Get-Command python.exe -ErrorAction SilentlyContinue
    if (($null -ne $pythonCommand) -and ($pythonCommand.Source -notmatch '\\WindowsApps\\')) {
        $candidates += $pythonCommand.Source
    }

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if ($candidate -and (Test-PythonCandidate -Path $candidate -RequestedVersion $majorMinor)) {
            return $candidate
        }
    }

    return $null
}

function Install-OfficialPython {
    param([Parameter(Mandatory)][string]$RequestedVersion)

    $majorMinor = (($RequestedVersion -split '\.')[0..1] -join '.')
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($null -eq $winget) {
        throw 'Python is not installed and winget is not available. Install App Installer/winget or install Python manually from python.org.'
    }

    $packageId = "Python.Python.$majorMinor"
    Write-Stage "Installing official Python $majorMinor for the current user"

    if ($PSCmdlet.ShouldProcess($packageId, 'Install with winget for the current user')) {
        Invoke-NativeCommand -FilePath $winget.Source -Arguments @(
            'install',
            '--id', $packageId,
            '--exact',
            # Do not query the Microsoft Store source. In some classroom
            # networks its certificate validation fails even when the winget
            # community repository is reachable.
            '--source', 'winget',
            '--scope', 'user',
            '--accept-package-agreements',
            '--accept-source-agreements',
            '--disable-interactivity'
        )
    }

    # winget does not always refresh PATH in the current process, so locate it directly.
    Start-Sleep -Seconds 2
    $pythonPath = Get-SystemPythonPath -RequestedVersion $majorMinor
    if ($null -eq $pythonPath) {
        throw "Python $majorMinor appears to have been installed, but python.exe could not be located. Close this window and run the BAT again."
    }

    return $pythonPath
}

function Ensure-SystemPython {
    param([Parameter(Mandatory)][string]$RequestedVersion)

    Write-Stage "Checking for Python $RequestedVersion"
    $pythonPath = Get-SystemPythonPath -RequestedVersion $RequestedVersion

    if ($null -ne $pythonPath) {
        Write-Host ('Using installed Python: {0}' -f $pythonPath) -ForegroundColor Green
        return $pythonPath
    }

    Write-Host ("Python {0} is not installed. It will be installed from the official winget package." -f $RequestedVersion) -ForegroundColor Yellow
    return Install-OfficialPython -RequestedVersion $RequestedVersion
}

function Get-UvPath {
    $command = Get-Command uv.exe -ErrorAction SilentlyContinue
    if ($null -ne $command) { return $command.Source }

    $candidate = Join-Path $env:USERPROFILE '.local\bin\uv.exe'
    if (Test-Path -LiteralPath $candidate) {
        Add-CurrentSessionPath -Directory (Split-Path -Parent $candidate)
        return $candidate
    }
    return $null
}

function Install-Uv {
    $uvPath = Get-UvPath
    if (($null -ne $uvPath) -and (-not $Reinstall)) {
        Write-Host ('Using uv: {0}' -f $uvPath) -ForegroundColor Green
        return $uvPath
    }

    Write-Stage 'Installing uv'
    if ($PSCmdlet.ShouldProcess('uv', 'Install using the official Astral installer')) {
        $installer = Invoke-RestMethod -Uri $Script:UvInstallerUri
        Invoke-Expression $installer | Out-Host
    }

    $uvPath = Get-UvPath
    if ($null -eq $uvPath) {
        throw 'uv could not be found after installation. Close this window and run the BAT again.'
    }
    return $uvPath
}

function Get-VsCodeCliPath {
    $command = Get-Command code.cmd -ErrorAction SilentlyContinue
    if ($null -ne $command) { return $command.Source }

    $candidate = Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\bin\code.cmd'
    if (Test-Path -LiteralPath $candidate) {
        Add-CurrentSessionPath -Directory (Split-Path -Parent $candidate)
        return $candidate
    }
    return $null
}

function Find-LocalVsCodeInstaller {
    # Look for common VS Code Windows installer names in the same directory
    # as this PowerShell script. Version numbers are allowed in the filename.
    $patterns = @(
        'VSCodeUserSetup-*.exe',
        'VSCodeSetup-*.exe',
        'VSCodeUserSetup*.exe',
        'VSCodeSetup*.exe'
    )

    $candidates = @()

    foreach ($pattern in $patterns) {
        $candidates += Get-ChildItem `
            -LiteralPath $PSScriptRoot `
            -Filter $pattern `
            -File `
            -ErrorAction SilentlyContinue
    }

    # Remove duplicates because patterns can overlap.
    $candidates = @($candidates | Sort-Object FullName -Unique)

    if ($candidates.Count -eq 0) {
        return $null
    }

    # If several installers are present, use the most recently modified one.
    $selected = $candidates |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    return [string]$selected.FullName
}

function Test-TrustedVsCodeInstaller {
    param([Parameter(Mandatory)][string]$Path)

    try {
        $signature = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop
        if ($signature.Status -eq 'Valid') {
            return $true
        }

        Write-Warning ("Ignoring local VS Code installer because its signature is {0}: {1}" -f $signature.Status, $Path)
    }
    catch {
        Write-Warning ("Ignoring local VS Code installer because its signature could not be checked: {0}" -f $Path)
    }

    return $false
}

function Install-VsCodeUser {
    $codeCli = Get-VsCodeCliPath
    if ($null -ne $codeCli) {
        Write-Host ('Using VS Code: {0}' -f $codeCli) -ForegroundColor Green
        return [string]$codeCli
    }

    # Prefer a local installer next to the script. This is useful in classrooms
    # and avoids downloading VS Code when the installer has already been copied.
    $localInstaller = Find-LocalVsCodeInstaller

    if (($null -ne $localInstaller) -and (-not (Test-TrustedVsCodeInstaller -Path $localInstaller))) {
        # A damaged copy commonly produces the installer message "The setup
        # files are corrupted". Fall back to the official download instead.
        $localInstaller = $null
    }

    if ($null -ne $localInstaller) {
        Write-Stage 'Installing VS Code from local installer'
        Write-Host ('Local VS Code installer found: {0}' -f $localInstaller) -ForegroundColor Green

        if ($PSCmdlet.ShouldProcess($localInstaller, 'Install VS Code for the current user')) {
            $arguments = @(
                '/VERYSILENT',
                '/NORESTART',
                '/MERGETASKS=!runcode'
            )

            $process = Start-Process `
                -FilePath $localInstaller `
                -ArgumentList $arguments `
                -Wait `
                -PassThru

            if ($process.ExitCode -ne 0) {
                throw ('Local VS Code installer finished with exit code {0}: {1}' -f $process.ExitCode, $localInstaller)
            }
        }
    }
    else {
        Write-Stage 'Installing VS Code for the current user'
        Write-Host 'No local VS Code installer was found next to the script.' -ForegroundColor Yellow
        Write-Host 'Downloading the official VS Code User Setup installer...' -ForegroundColor Yellow

        $installerPath = Join-Path $env:TEMP 'VSCodeUserSetup.exe'
        $downloadUri = 'https://update.code.visualstudio.com/latest/win32-x64-user/stable'

        if ($PSCmdlet.ShouldProcess('VS Code User Setup', 'Download and install')) {
            Invoke-WebRequest `
                -Uri $downloadUri `
                -OutFile $installerPath `
                -UseBasicParsing

            $process = Start-Process `
                -FilePath $installerPath `
                -ArgumentList @('/VERYSILENT', '/NORESTART', '/MERGETASKS=!runcode') `
                -Wait `
                -PassThru

            if ($process.ExitCode -ne 0) {
                throw ('VS Code installer finished with exit code {0}.' -f $process.ExitCode)
            }
        }
    }

    # Refresh PATH for the current PowerShell process.
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')

    # Give the installer a moment to finish writing files and verify code.cmd.
    for ($attempt = 1; $attempt -le 10; $attempt++) {
        $codeCli = Get-VsCodeCliPath
        if ($null -ne $codeCli) {
            break
        }
        Start-Sleep -Seconds 2
    }

    if ($null -eq $codeCli) {
        throw 'VS Code was installed, but code.cmd could not be found. Run the BAT again.'
    }

    Write-Host ('Using VS Code: {0}' -f $codeCli) -ForegroundColor Green
    return [string]$codeCli
}

function Get-InstalledVsCodeExtensions {
    param([Parameter(Mandatory)][string]$CodeCli)

    try {
        $items = & $CodeCli --list-extensions 2>$null
        if ($LASTEXITCODE -eq 0) {
            return @($items | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ })
        }
    }
    catch {}
    return @()
}

function Test-HttpEndpoint {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Uri
    )

    try {
        $response = Invoke-WebRequest -Uri $Uri -Method Get -TimeoutSec 12 -UseBasicParsing -MaximumRedirection 5
        return [pscustomobject]@{
            Name       = $Name
            Reachable  = $true
            StatusCode = [int]$response.StatusCode
            Error      = ''
        }
    }
    catch {
        $statusCode = $null
        try {
            if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }
        }
        catch {}

        return [pscustomobject]@{
            Name       = $Name
            Reachable  = $false
            StatusCode = $statusCode
            Error      = $_.Exception.Message
        }
    }
}

function Get-VsCodeMarketplaceDiagnosis {
    Write-Host 'Diagnosing VS Code Marketplace connectivity...' -ForegroundColor Yellow

    $tests = @(
        (Test-HttpEndpoint -Name 'General Internet (Microsoft)' -Uri 'https://www.microsoft.com/'),
        (Test-HttpEndpoint -Name 'Visual Studio Marketplace' -Uri 'https://marketplace.visualstudio.com/'),
        (Test-HttpEndpoint -Name 'VS Code Marketplace API' -Uri 'https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery')
    )

    foreach ($test in $tests) {
        if ($test.Reachable) {
            Write-Host ("  [OK] {0} - HTTP {1}" -f $test.Name, $test.StatusCode) -ForegroundColor Green
        }
        else {
            $codeText = if ($null -ne $test.StatusCode) { "HTTP $($test.StatusCode)" } else { 'no HTTP response' }
            Write-Host ("  [FAIL] {0} - {1}" -f $test.Name, $codeText) -ForegroundColor Red
            Write-Verbose $test.Error
        }
    }

    $internet = $tests[0]
    $marketplace = $tests[1]
    $api = $tests[2]

    if (-not $internet.Reachable) {
        return 'ACCESS: No general Internet access was detected. Check DNS, proxy, firewall, captive portal, or network connectivity.'
    }

    if (-not $marketplace.Reachable -and -not $api.Reachable) {
        return 'ACCESS: Internet works, but Visual Studio Marketplace endpoints are not reachable. A proxy, firewall, filtering policy, or Marketplace outage may be blocking access.'
    }

    if (($marketplace.StatusCode -eq 503) -or ($api.StatusCode -eq 503)) {
        return 'SERVICE: Marketplace returned HTTP 503. This normally indicates a temporary service-side availability problem.'
    }

    if ($marketplace.Reachable -or $api.Reachable) {
        return 'SERVICE/CLI: Marketplace is reachable from this PC. If code --install-extension still fails with 5xx, the problem is likely temporary in the Marketplace/CLI path rather than basic network access.'
    }

    return 'UNKNOWN: Connectivity tests were inconclusive.'
}

function Find-LocalVsix {
    param([Parameter(Mandatory)][string]$ExtensionId)

    if (-not (Test-Path -LiteralPath $Script:ExtensionsDirectory)) {
        return $null
    }

    $exact = Join-Path $Script:ExtensionsDirectory "$ExtensionId.vsix"
    if (Test-Path -LiteralPath $exact) {
        return $exact
    }

    $candidate = Get-ChildItem -LiteralPath $Script:ExtensionsDirectory -Filter "$ExtensionId*.vsix" -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($null -ne $candidate) {
        return $candidate.FullName
    }

    return $null
}

function Install-VsCodeExtensionFromMarketplace {
    param(
        [Parameter(Mandatory)][string]$CodeCli,
        [Parameter(Mandatory)][string]$ExtensionId
    )

    for ($attempt = 1; $attempt -le $Script:ExtensionInstallRetries; $attempt++) {
        Write-Host ("Installing {0} from Marketplace (attempt {1}/{2})..." -f $ExtensionId, $attempt, $Script:ExtensionInstallRetries)
        & $CodeCli --install-extension $ExtensionId --force
        if ($LASTEXITCODE -eq 0) {
            return $true
        }

        if ($attempt -lt $Script:ExtensionInstallRetries) {
            Start-Sleep -Seconds (3 * $attempt)
        }
    }
    return $false
}

function Install-VsCodeExtensionFromVsix {
    param(
        [Parameter(Mandatory)][string]$CodeCli,
        [Parameter(Mandatory)][string]$ExtensionId
    )

    $vsix = Find-LocalVsix -ExtensionId $ExtensionId
    if ($null -eq $vsix) {
        Write-Host ("No local VSIX found for {0} in: {1}" -f $ExtensionId, $Script:ExtensionsDirectory) -ForegroundColor DarkYellow
        return $false
    }

    Write-Host ("Trying local VSIX: {0}" -f $vsix) -ForegroundColor Yellow
    & $CodeCli --install-extension $vsix --force
    if ($LASTEXITCODE -eq 0) {
        Write-Host ("Installed {0} from local VSIX." -f $ExtensionId) -ForegroundColor Green
        return $true
    }

    Write-Warning ("Local VSIX installation also failed for {0}." -f $ExtensionId)
    return $false
}

function Install-VsCodeExtensions {
    param([Parameter(Mandatory)][string]$CodeCli)

    Write-Stage 'Installing VS Code extensions'

    if (-not (Test-Path -LiteralPath $Script:ExtensionsDirectory)) {
        New-Item -ItemType Directory -Path $Script:ExtensionsDirectory -Force | Out-Null
    }

    foreach ($extension in $Script:RequiredExtensions) {
        $installed = Get-InstalledVsCodeExtensions -CodeCli $CodeCli
        if ($installed -contains $extension.ToLowerInvariant()) {
            Write-Host ("Extension already installed: {0}" -f $extension) -ForegroundColor Green
            continue
        }

        $marketplaceSuccess = Install-VsCodeExtensionFromMarketplace -CodeCli $CodeCli -ExtensionId $extension
        if ($marketplaceSuccess) {
            continue
        }

        Write-Warning ("Marketplace installation failed for {0}." -f $extension)
        $diagnosis = Get-VsCodeMarketplaceDiagnosis
        Write-Host ("Diagnosis: {0}" -f $diagnosis) -ForegroundColor Yellow

        $vsixSuccess = Install-VsCodeExtensionFromVsix -CodeCli $CodeCli -ExtensionId $extension
        if (-not $vsixSuccess) {
            [void]$Script:ExtensionInstallFailures.Add($extension)
            Write-Warning ("Continuing setup without extension {0}. Python environment creation is not blocked by this failure." -f $extension)
        }
    }
}

function Write-MinimalPyProject {
    $pyproject = Join-Path $ProjectPath 'pyproject.toml'

    if (Test-Path -LiteralPath $pyproject) {
        # Repair the specific uv-init problem from older versions of this script:
        # [project.scripts] python = "python:main" uses the reserved executable name 'python'.
        $lines = Get-Content -LiteralPath $pyproject
        $output = [System.Collections.Generic.List[string]]::new()
        $insideScripts = $false
        $changed = $false

        foreach ($line in $lines) {
            if ($line -match '^\s*\[project\.scripts\]\s*$') {
                $insideScripts = $true
                $changed = $true
                continue
            }
            if ($insideScripts -and $line -match '^\s*\[') {
                $insideScripts = $false
            }
            if (-not $insideScripts) {
                [void]$output.Add($line)
            }
        }

        if ($changed) {
            Set-Content -LiteralPath $pyproject -Value $output -Encoding UTF8
            Write-Host 'Removed obsolete [project.scripts] section that used the reserved name python.' -ForegroundColor Yellow
        }
        return
    }

    $majorMinor = (($PythonVersion -split '\.')[0..1] -join '.')
    $nextMinor = [int](($majorMinor -split '\.')[1]) + 1
    $upper = "3.$nextMinor"

    $content = @"
[project]
name = "data-analysis-python"
version = "0.1.0"
requires-python = ">=$majorMinor,<$upper"
dependencies = []
"@
    Set-Content -LiteralPath $pyproject -Value $content -Encoding UTF8
}

function Initialize-Project {
    param(
        [Parameter(Mandatory)][string]$UvPath,
        [Parameter(Mandatory)][string]$PythonPath
    )

    if (-not (Test-Path -LiteralPath $ProjectPath)) {
        New-Item -ItemType Directory -Path $ProjectPath -Force | Out-Null
    }

    Push-Location $ProjectPath
    try {
        New-Item -ItemType Directory -Path (Join-Path $ProjectPath 'notebooks') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $ProjectPath 'data') -Force | Out-Null

        Write-MinimalPyProject

        $venvPath = Join-Path $ProjectPath '.venv'
        $venvPython = Join-Path $venvPath 'Scripts\python.exe'

        if ($Reinstall -and (Test-Path -LiteralPath $venvPath)) {
            Write-Stage 'Removing existing virtual environment'
            Remove-Item -LiteralPath $venvPath -Recurse -Force
        }
        elseif (Test-Path -LiteralPath $venvPython) {
            # A previous run may have created .venv from uv-managed Python,
            # which can be blocked by Windows Application Control. Test it first.
            $existingVenvWorks = $false
            try {
                & $venvPython --version *> $null
                $existingVenvWorks = ($LASTEXITCODE -eq 0)
            }
            catch {
                $existingVenvWorks = $false
            }

            if (-not $existingVenvWorks) {
                Write-Stage 'Replacing the existing blocked/broken .venv'
                Remove-Item -LiteralPath $venvPath -Recurse -Force
            }
        }

        if (-not (Test-Path -LiteralPath $venvPython)) {
            Write-Stage 'Creating .venv from the installed official Python'
            Invoke-NativeCommand -FilePath $UvPath -Arguments @('venv', '--python', $PythonPath, '--no-python-downloads', '.venv')
        }

        Write-Stage 'Validating the virtual environment interpreter'
        try {
            $venvVersion = & $venvPython --version
            if ($LASTEXITCODE -ne 0) { throw 'The .venv Python interpreter could not be executed.' }
            Write-Host $venvVersion -ForegroundColor Green
        }
        catch {
            throw "Windows blocked .venv\Scripts\python.exe. The environment was created from '$PythonPath', but an Application Control policy still prevents execution."
        }

        Write-Stage 'Installing project dependencies'
        Invoke-NativeCommand -FilePath $UvPath -Arguments (@('add', '--python', $PythonPath, '--no-python-downloads') + $Script:BasePackages)
        Invoke-NativeCommand -FilePath $UvPath -Arguments (@('add', '--dev', '--python', $PythonPath, '--no-python-downloads') + $Script:DevelopmentPackages)

        if ($IncludeExcelAndParquet) {
            Invoke-NativeCommand -FilePath $UvPath -Arguments @('add', '--python', $PythonPath, '--no-python-downloads', 'openpyxl', 'pyarrow')
        }

        Write-Stage 'Synchronizing the virtual environment'
        $syncArgs = @('sync', '--locked', '--python', $PythonPath, '--no-python-downloads')
        if ($Reinstall) { $syncArgs += '--reinstall' }
        Invoke-NativeCommand -FilePath $UvPath -Arguments $syncArgs
    }
    finally {
        Pop-Location
    }
}

function Invoke-EnvironmentCheck {
    param(
        [string]$ExpectedPythonPath = '',
        [switch]$CheckProject
    )

    $failed = $false
    function Report-Check {
        param([string]$Name, [bool]$Passed, [string]$Detail = '')
        if ($Passed) { Write-Host ('[OK]   {0} {1}' -f $Name, $Detail) -ForegroundColor Green }
        else { Write-Host ('[FAIL] {0} {1}' -f $Name, $Detail) -ForegroundColor Red; $script:CheckFailed = $true }
    }

    $script:CheckFailed = $false
    Write-Stage 'Checking the environment'

    $pythonPath = Get-SystemPythonPath -RequestedVersion $PythonVersion
    Report-Check 'Official/system Python' ($null -ne $pythonPath) $pythonPath

    $uvPath = Get-UvPath
    Report-Check 'uv' ($null -ne $uvPath) $uvPath

    $codeCli = Get-VsCodeCliPath
    Report-Check 'VS Code' ($null -ne $codeCli) $codeCli

    if ($null -ne $codeCli) {
        $installedExtensions = Get-InstalledVsCodeExtensions -CodeCli $codeCli
        foreach ($extension in $Script:RequiredExtensions) {
            $present = $installedExtensions -contains $extension.ToLowerInvariant()
            if ($present) {
                Write-Host ('[OK]   VS Code extension {0}' -f $extension) -ForegroundColor Green
            }
            else {
                Write-Host ('[WARN] VS Code extension {0} is not installed' -f $extension) -ForegroundColor Yellow
            }
        }
    }

    if ($CheckProject) {
        $venvPython = Join-Path $ProjectPath '.venv\Scripts\python.exe'
        Report-Check '.venv interpreter exists' (Test-Path -LiteralPath $venvPython) $venvPython

        if (Test-Path -LiteralPath $venvPython) {
            try {
            # Do not merge stderr into the PowerShell error stream here.
            # Some valid Python libraries (notably Matplotlib on first run)
            # write informational messages such as "building the font cache"
            # to stderr even though Python exits successfully.
            $versionText = & $venvPython --version 2>$null
            $versionExitCode = $LASTEXITCODE
            Report-Check '.venv interpreter runs' ($versionExitCode -eq 0) ($versionText -join ' ')

            # Check that packages are installed WITHOUT importing them.
            # Importing matplotlib/seaborn during validation can build the
            # Matplotlib font cache and emit a harmless stderr message.
            $packageProbe = @"
import importlib.util
packages = ['numpy', 'pandas', 'matplotlib', 'seaborn', 'ipykernel', 'pytest']
missing = [name for name in packages if importlib.util.find_spec(name) is None]
if missing:
    print('missing: ' + ', '.join(missing))
    raise SystemExit(1)
print('packages OK')
"@
            $packageCheck = & $venvPython -c $packageProbe 2>$null
            $packageExitCode = $LASTEXITCODE
            Report-Check 'Project packages' ($packageExitCode -eq 0) ($packageCheck -join ' ')
            }
            catch {
                Report-Check '.venv validation' $false $_.Exception.Message
            }
        }
    }

    if ($script:CheckFailed) {
        Write-Host ''
        Write-Host 'Check completed with errors.' -ForegroundColor Red
        return $false
    }

    Write-Host ''
    Write-Host 'Check completed successfully.' -ForegroundColor Green
    return $true
}

if ($Check) {
    $checkProject = -not [string]::IsNullOrWhiteSpace($ProjectPath)
    if (-not (Invoke-EnvironmentCheck -CheckProject:$checkProject)) { exit 1 }
    exit 0
}

try {
    Write-Host 'Python workstation setup' -ForegroundColor White
    if ($PyData) {
        Write-Host ('Data analysis project: {0}' -f $ProjectPath)
    }

    # Check/install official Python first, before uv creates any environment.
    $pythonPath = Ensure-SystemPython -RequestedVersion $PythonVersion

    $codeCli = Install-VsCodeUser
    Install-VsCodeExtensions -CodeCli $codeCli

    $uvPath = Install-Uv
    if ($PyData) {
        Initialize-Project -UvPath $uvPath -PythonPath $pythonPath
    }

    if (-not (Invoke-EnvironmentCheck -ExpectedPythonPath $pythonPath -CheckProject:$PyData)) { exit 1 }

    if ($Script:ExtensionInstallFailures.Count -gt 0) {
        Write-Host ''
        Write-Host 'WARNING: The Python environment is ready, but these VS Code extensions could not be installed:' -ForegroundColor Yellow
        foreach ($extension in $Script:ExtensionInstallFailures) {
            Write-Host ('  - {0}' -f $extension) -ForegroundColor Yellow
        }
        Write-Host ('Place downloaded VSIX files in: {0}' -f $Script:ExtensionsDirectory) -ForegroundColor Yellow
        Write-Host 'Then run the installer again. It will try Marketplace first and local VSIX as fallback.' -ForegroundColor Yellow
    }

    Write-Host ''
    $completionMessage = if ($PyData) { 'Data analysis environment ready.' } else { 'Base tools ready.' }
    Write-Host $completionMessage -ForegroundColor Green
    Write-Host ('Python used: {0}' -f $pythonPath) -ForegroundColor Green
    if ($PyData) {
        Write-Host 'In VS Code, select: .venv\Scripts\python.exe' -ForegroundColor Green
    }
}
catch {
    Write-Host ''
    Write-Host ('ERROR: {0}' -f $_.Exception.Message) -ForegroundColor Red
    exit 1
}
