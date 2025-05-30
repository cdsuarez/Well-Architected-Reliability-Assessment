param(
    [Parameter(Mandatory=$true)]
    [string]$ModuleName,
    [string]$Version
)

# Create output directory
$outputDir = "./output"
if (Test-Path $outputDir) {
    Write-Host "Cleaning output directory..."
    Remove-Item -Path $outputDir -Recurse -Force
}
New-Item -ItemType Directory -Path $outputDir | Out-Null

# Copy module files
$moduleDir = "$outputDir/$ModuleName"
Write-Host "Copying module files to $moduleDir..."
Copy-Item -Path "./src/modules/$ModuleName" -Destination $moduleDir -Recurse -Force

# If version not provided, try to get it from git
if (-not $Version) {
    try {
        $Version = (git describe --tags --abbrev=0 2>$null) -replace '^v', ''
        if (-not $Version) {
            $Version = "0.1.0"
            Write-Warning "No git tags found, using default version: $Version"
        } else {
            Write-Host "Using version from git tag: $Version"
        }
    } catch {
        $Version = "0.1.0"
        Write-Warning "Error getting version from git, using default: $Version"
    }
}

# Define module manifest parameters
$manifestParams = @{
    Path = "$moduleDir/$ModuleName.psd1"
    RootModule = "$ModuleName.psm1"
    Description = 'Well-Architected Reliability Assessment Module'
    ModuleVersion = $Version
    Author = 'Microsoft'
    CompanyName = 'Microsoft'
    Copyright = '(c) Microsoft. All rights reserved.'
    PowerShellVersion = '7.4'
    RequiredModules = @(
        @{ModuleName = 'Az.Accounts'; ModuleVersion = '2.0.0'}
        @{ModuleName = 'Az.ResourceGraph'; ModuleVersion = '1.0.0'}
    )
    FunctionsToExport = '*'
    CmdletsToExport = @()
    VariablesToExport = '*'
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('Azure', 'Reliability', 'Well-Architected', 'Assessment')
            LicenseUri = 'https://github.com/Azure/Well-Architected-Reliability-Assessment/blob/main/LICENSE'
            ProjectUri = 'https://github.com/Azure/Well-Architected-Reliability-Assessment'
            ReleaseNotes = 'Initial release'
        }
    }
}

# Create or update module manifest
Write-Host "Creating/updating module manifest..."
if (Test-Path $manifestParams.Path) {
    Update-ModuleManifest @manifestParams
    Write-Host "Updated module manifest at $($manifestParams.Path)"
} else {
    New-ModuleManifest @manifestParams
    Write-Host "Created new module manifest at $($manifestParams.Path)"
}

# Validate the module
Write-Host "Validating module..."
$module = Import-Module $moduleDir -PassThru -Force
if (-not $module) {
    Write-Error "Failed to import module from $moduleDir"
    exit 1
}

# List exported commands
$exportedCommands = Get-Command -Module $module | Select-Object -ExpandProperty Name
Write-Host "Module $($module.Name) v$($module.Version) loaded successfully"
Write-Host "Exported commands: $($exportedCommands -join ', ')"

# Clean up
Remove-Module $module.Name -Force -ErrorAction SilentlyContinue

Write-Host "Build completed successfully! Output directory: $outputDir"
