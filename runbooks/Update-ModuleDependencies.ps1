<#
.SYNOPSIS
    Updates PowerShell module dependencies to their latest versions.
    
.DESCRIPTION
    This script checks for and updates all PowerShell modules used by the WARA tool
    to their latest available versions from the PowerShell Gallery.
    
.PARAMETER Scope
    Specifies the installation scope of the modules. Valid values are 'CurrentUser' and 'AllUsers'.
    Default is 'CurrentUser'.
    
.PARAMETER Force
    Forces the update of modules even if they are already up to date.
    
.PARAMETER WhatIf
    Shows what would happen if the cmdlet runs. The cmdlet is not run.
    
.EXAMPLE
    .\Update-ModuleDependencies.ps1 -Scope CurrentUser -Verbose
    
    Updates all modules for the current user with verbose output.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param (
    [ValidateSet('CurrentUser', 'AllUsers')]
    [string]$Scope = 'CurrentUser',
    [switch]$Force
)

# Required modules and their minimum versions
$requiredModules = @{
    'Az.Accounts' = '2.0.0'
    'Az.Resources' = '6.0.0'
    'Pester' = '5.0.0'
    'PSScriptAnalyzer' = '1.0.0'
    'ImportExcel' = '7.8.4'
    'PowerShellGet' = '2.2.5'
}

# Check if running as administrator when installing for AllUsers
if ($Scope -eq 'AllUsers' -and -not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Administrator rights are required to install modules for AllUsers. Please run PowerShell as Administrator or use -Scope CurrentUser."
    exit 1
}

# Ensure NuGet provider is installed
$nugetProvider = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
if (-not $nugetProvider) {
    Write-Host "Installing NuGet package provider..." -ForegroundColor Cyan
    Install-PackageProvider -Name NuGet -Force -Scope $Scope | Out-Null
}

# Set up the repository
if (-not (Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue)) {
    Write-Host "Registering PSGallery repository..." -ForegroundColor Cyan
    Register-PSRepository -Default -InstallationPolicy Trusted -ErrorAction Stop
}

# Update each module
$results = @()
foreach ($module in $requiredModules.GetEnumerator()) {
    $moduleName = $module.Key
    $minVersion = $module.Value
    
    Write-Host "`nChecking $moduleName (Minimum version: $minVersion)..." -ForegroundColor Cyan
    
    try {
        # Check if module is installed
        $installedModule = Get-Module -Name $moduleName -ListAvailable | 
            Sort-Object -Property Version -Descending | 
            Select-Object -First 1
        
        # Get the latest version from the gallery
        $galleryModule = Find-Module -Name $moduleName -Repository PSGallery -ErrorAction Stop
        
        $status = @{
            Module = $moduleName
            InstalledVersion = $installedModule.Version.ToString()
            AvailableVersion = $galleryModule.Version.ToString()
            Action = 'Skipped'
        }
        
        # Check if update is needed
        if (-not $installedModule -or ($galleryModule.Version -gt $installedModule.Version) -or $Force) {
            $action = if (-not $installedModule) { 'Install' } else { 'Update' }
            
            if ($PSCmdlet.ShouldProcess("$moduleName ($($galleryModule.Version))", "$action module")) {
                Write-Host "$action`ing $moduleName to version $($galleryModule.Version)..." -ForegroundColor Yellow
                
                # Install or update the module
                if ($action -eq 'Install') {
                    Install-Module -Name $moduleName -RequiredVersion $galleryModule.Version -Force -AllowClobber -Scope $Scope -SkipPublisherCheck
                } else {
                    Update-Module -Name $moduleName -RequiredVersion $galleryModule.Version -Force -AllowClobber -ErrorAction Stop
                }
                
                $status.Action = $action
                $status.InstalledVersion = $galleryModule.Version.ToString()
                Write-Host "Successfully $($action.ToLower())ed $moduleName $($galleryModule.Version)" -ForegroundColor Green
            }
        } else {
            Write-Host "$moduleName is up to date (v$($installedModule.Version))" -ForegroundColor Green
            $status.Action = 'UpToDate'
        }
    }
    catch {
        Write-Error "Error processing $moduleName : $_"
        $status.Action = "Error: $_"
    }
    
    $results += [PSCustomObject]$status
}

# Display summary
Write-Host "`nUpdate Summary:`" -ForegroundColor Cyan
$results | Format-Table -AutoSize

# Import updated modules
Write-Host "`nImporting updated modules..." -ForegroundColor Cyan
foreach ($module in $requiredModules.Keys) {
    try {
        Import-Module -Name $module -Force -ErrorAction Stop
        Write-Host "Imported $module" -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to import $module : $_"
    }
}

Write-Host "`nModule update process completed." -ForegroundColor Cyan
