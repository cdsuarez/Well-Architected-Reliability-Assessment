#Requires -Version 7.0
#Requires -Modules @{ ModuleName="Az.Accounts"; ModuleVersion="2.0.0" }
#Requires -Modules @{ ModuleName="Az.Resources"; ModuleVersion="6.0.0" }
#Requires -Modules @{ ModuleName="Az.Storage"; ModuleVersion="5.0.0" }

<#
.SYNOPSIS
    Authenticates with Azure and loads WARA configuration.

.DESCRIPTION
    This script handles Azure authentication using service principal credentials
    and loads the WARA configuration from a JSON file. It sets the appropriate
    Azure context for the WARA assessment and ensures all required modules are available.

.PARAMETER ConfigFile
    Path to the WARA configuration JSON file. Must be a valid JSON file with the required schema.

.PARAMETER OutputDirectory
    Directory where output files will be saved. Will be created if it doesn't exist.

.EXAMPLE
    .\azure-login.ps1 -ConfigFile ".\config\wara-tenant-config.json" -OutputDirectory ".\output"

.NOTES
    File Name      : azure-login.ps1
    Prerequisites  : PowerShell 7.0+, Az.Accounts, Az.Resources, Az.Storage
    Copyright      : (c) 2024 Your Organization. All rights reserved.
#>

[CmdletBinding(
    SupportsShouldProcess = $true,
    ConfirmImpact = 'Medium'
)]
param (
    [Parameter(Mandatory = $true,
        HelpMessage = 'Path to the WARA configuration JSON file')]
    [ValidateScript({
            if (-not (Test-Path -Path $_ -PathType Leaf)) {
                throw "Configuration file not found: $_"
            }
            if ($_ -notmatch '\.json$') {
                throw 'Configuration file must be a JSON file (.json)'
            }
            return $true
        })]
    [string]$ConfigFile,

    [Parameter(Mandatory = $true,
        HelpMessage = 'Directory where output files will be saved')]
    [ValidateScript({
            try {
                $path = Resolve-Path -Path $_ -ErrorAction Stop
                if (-not (Test-Path -Path $path -PathType Container)) {
                    New-Item -ItemType Directory -Path $path -Force | Out-Null
                }
                return $true
            }
            catch {
                throw "Invalid output directory: $_"
            }
        })]
    [string]$OutputDirectory
)

#region Initialization

# Set error action preference
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue' # Improves performance

# Import required modules
try {
    $requiredModules = @(
        @{ Name = 'Az.Accounts'; Version = '2.0.0' },
        @{ Name = 'Az.Resources'; Version = '6.0.0' },
        @{ Name = 'Az.Storage'; Version = '5.0.0' }
    )

    foreach ($module in $requiredModules) {
        $moduleName = $module.Name
        $moduleVersion = $module.Version
        
        if (-not (Get-Module -Name $moduleName -ListAvailable -ErrorAction SilentlyContinue | 
                Where-Object { $_.Version -ge [version]$moduleVersion })) {
            Write-Verbose "Installing required module: $moduleName $moduleVersion"
            Install-Module -Name $moduleName -RequiredVersion $moduleVersion -Force -AllowClobber -Scope CurrentUser
        }
        
        Import-Module -Name $moduleName -RequiredVersion $moduleVersion -ErrorAction Stop
        Write-Verbose "Imported module: $moduleName $moduleVersion"
    }
}
catch {
    Write-Error "Failed to import required modules: $_"
    exit 1
}

# Initialize logging
$logFile = Join-Path -Path $OutputDirectory -ChildPath 'wara-login.log'
Start-Transcript -Path $logFile -Append -Force

# Log script start
Write-Output "=== Starting Azure Login Script ==="
Write-Output "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Output "PowerShell Version: $($PSVersionTable.PSVersion)"
Write-Output "OS: $($PSVersionTable.OS)"
Write-Output "Config File: $ConfigFile"
Write-Output "Output Directory: $OutputDirectory"

#region Configuration Loading

try {
    Write-Output "Loading configuration from: $ConfigFile"
    
    # Validate and load configuration
    $configContent = Get-Content -Path $ConfigFile -Raw -ErrorAction Stop
    $config = $configContent | ConvertFrom-Json -ErrorAction Stop
    
    # Validate required configuration
    $requiredConfig = @('tenantId', 'subscriptionId')
    foreach ($key in $requiredConfig) {
        if (-not $config.azure.$key) {
            throw "Missing required configuration: azure.$key"
        }
    }
    
    # Set environment variables
    $env:tenantId = $config.azure.tenantId
    $env:subscriptionId = $config.azure.subscriptionId
    
    # Save the config to the output directory for reference
    $configBackupPath = Join-Path -Path $OutputDirectory -ChildPath 'wara-tenant-config.json'
    $config | ConvertTo-Json -Depth 10 | Out-File -FilePath $configBackupPath -Force
    Write-Output "Configuration saved to: $configBackupPath"
    
    # Log configuration summary (excluding sensitive data)
    $configSummary = $config | Select-Object -Property @{
        Name = 'azure.tenantId'; Expression = { $_.azure.tenantId }
    }, @{
        Name = 'azure.subscriptionId'; Expression = { $_.azure.subscriptionId }
    }, @{
        Name = 'azure.environment'; Expression = { $_.azure.environment } 
    }
    
    Write-Output "Configuration Summary:"
    $configSummary | Format-List | Out-String -Stream | ForEach-Object { Write-Output $_.Trim() }
    
    #region Azure Authentication
    
    try {
        # Check if we're already connected to Azure with the correct subscription
        $context = Get-AzContext -ErrorAction SilentlyContinue
        if ($null -ne $context -and $context.Subscription.Id -eq $config.azure.subscriptionId) {
            Write-Output "Already connected to Azure with the correct subscription: $($context.Subscription.Name) ($($context.Subscription.Id))"
            $alreadyConnected = $true
        }
        else {
            # Connect to Azure using available authentication method
            Write-Output "Initiating Azure authentication..."
            
            # Try different authentication methods in order of preference
            $authMethods = @(
                @{ Name = 'Managed Identity'; Script = { 
                    Write-Verbose 'Attempting Managed Identity authentication...'
                    Connect-AzAccount -Identity -ErrorAction Stop
                    return $true
                }},
                @{ Name = 'Service Principal'; Script = {
                    if ($env:servicePrincipalId -and $env:servicePrincipalKey) {
                        Write-Verbose 'Attempting Service Principal authentication...'
                        $securePassword = ConvertTo-SecureString $env:servicePrincipalKey -AsPlainText -Force -ErrorAction Stop
                        $psCredential = New-Object System.Management.Automation.PSCredential($env:servicePrincipalId, $securePassword) -ErrorAction Stop
                        $tenantId = $config.azure.tenantId
                        Connect-AzAccount -ServicePrincipal -Credential $psCredential -Tenant $tenantId -ErrorAction Stop
                        return $true
                    }
                    return $false
                }},
                @{ Name = 'Interactive'; Script = {
                    if ($IsCoreCLR -or $PSVersionTable.PSVersion.Major -ge 6) {
                        Write-Verbose 'Attempting interactive authentication...'
                        Connect-AzAccount -UseDeviceAuthentication -ErrorAction Stop
                        return $true
                    }
                    return $false
                }}
            )

            $authenticated = $false
            foreach ($method in $authMethods) {
                try {
                    Write-Verbose "Trying authentication method: $($method.Name)"
                    if (& $method.Script) {
                        Write-Output "Successfully authenticated using $($method.Name)"
                        $authenticated = $true
                        break
                    }
                }
                catch {
                    Write-Verbose "Authentication method $($method.Name) failed: $_"
                }
            }

            if (-not $authenticated) {
                throw 'Failed to authenticate with any available method. Please check your credentials and try again.'
            }

            # Set the subscription context
            Write-Output "Setting subscription context to: $($config.azure.subscriptionId)"
            $context = Set-AzContext -Subscription $config.azure.subscriptionId -ErrorAction Stop
            Write-Output "Connected to Azure subscription: $($context.Subscription.Name) ($($context.Subscription.Id))"
        }

        # Verify access
        try {
            $null = Get-AzResource -ErrorAction Stop
            Write-Output 'Successfully verified Azure resource access.'
        }
        catch {
            Write-Warning 'Warning: Could not verify Azure resource access. Some operations might fail.'
        }

        # Return the configuration and context
        [PSCustomObject]@{
            Config = $config
            Context = $context
            IsNewConnection = -not $alreadyConnected
            Timestamp = Get-Date -Format 'o'
        }
    }
    catch {
        $errorMsg = "Failed to authenticate with Azure: $_"
        Write-Error $errorMsg -ErrorAction Stop
        throw $errorMsg
    }
    finally {
        # Always ensure we're using the correct subscription
        if ($context -and $context.Subscription.Id -ne $config.azure.subscriptionId) {
            Write-Warning "Subscription context does not match the configured subscription. Attempting to correct..."
            try {
                $context = Set-AzContext -Subscription $config.azure.subscriptionId -ErrorAction Stop
                Write-Output "Corrected subscription context to: $($context.Subscription.Name) ($($context.Subscription.Id))"
            }
            catch {
                Write-Error "Failed to set subscription context: $_"
                throw
            }
        }
        
        # Verify the current context
        $context = Get-AzContext -ErrorAction Stop
        Write-Output "Current context: $($context.Account.Id) in subscription $($context.Subscription.Name) ($($context.Subscription.Id))"
        
        # Output the configuration for debugging
        Write-Verbose "WARA Configuration:"
        $config | ConvertTo-Json -Depth 3 | Out-String | Write-Verbose
        
        # Return the configuration and context
        [PSCustomObject]@{
            Config = $config
            Context = $context
            IsNewConnection = -not $alreadyConnected
            Timestamp = Get-Date -Format 'o'
        }
    }
    finally {
        # Complete logging
        Write-Output "Script completed at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        Write-Output "Log file: $logFile"
        Stop-Transcript | Out-Null
    }
}
catch {
    $errorMsg = "Failed to initialize WARA assessment: $_"
    Write-Error $errorMsg -ErrorAction Continue
    Write-Error $_.ScriptStackTrace
    throw $errorMsg
}
