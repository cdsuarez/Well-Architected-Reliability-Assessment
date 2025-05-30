param(
    [Parameter(Mandatory=$true)]
    [string]$Path,
    [string]$ApiKey
)

# Verify module exists
if (-not (Test-Path $Path)) {
    Write-Error "Module not found at path: $Path"
    exit 1
}

# Get API key from parameter or environment
if (-not $ApiKey) {
    $ApiKey = $env:NUGET_API_KEY
}

if (-not $ApiKey) {
    Write-Error "NuGet API key not provided and NUGET_API_KEY environment variable not set"
    Write-Host "Please provide the API key using -ApiKey parameter or set NUGET_API_KEY environment variable"
    exit 1
}

# Import required module
$moduleName = (Get-ChildItem -Path $Path -Filter "*.psd1" | Select-Object -First 1).BaseName
if (-not $moduleName) {
    Write-Error "No module manifest (.psd1) found in $Path"
    exit 1
}

# Check if module is already published
$publishedVersion = (Find-Module -Name $moduleName -Repository PSGallery -ErrorAction SilentlyContinue).Version
$localVersion = (Import-PowerShellDataFile -Path "$Path\$moduleName.psd1").ModuleVersion

if ($publishedVersion -and ($publishedVersion -ge [version]$localVersion)) {
    Write-Warning "Module $moduleName version $localVersion is not newer than the published version $publishedVersion"
    Write-Host "To publish a new version, update the module version in the .psd1 file"
    exit 0
}

# Publish module
try {
    Write-Host "Publishing module $moduleName version $localVersion to PSGallery..."
    
    # Register the PSGallery repository if not already registered
    if (-not (Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue)) {
        Register-PSRepository -Default -InstallationPolicy Trusted
    }
    
    # Publish the module
    Publish-Module -Path $Path -NuGetApiKey $ApiKey -Verbose -ErrorAction Stop
    
    Write-Host "Module $moduleName version $localVersion published successfully to PSGallery!"
    Write-Host "You can install it using: Install-Module -Name $moduleName -Force -AllowClobber"
    
} catch {
    Write-Error "Failed to publish module: $_"
    exit 1
}
