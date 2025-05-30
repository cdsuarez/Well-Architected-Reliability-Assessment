<#
.SYNOPSIS
    Script to authenticate with Azure using a service principal and load WARA configuration.

.DESCRIPTION
    This script authenticates with Azure using the service principal credentials
    provided by Azure DevOps and loads the WARA configuration from a JSON file.
    It sets the appropriate context for the WARA assessment.

.PARAMETER ConfigFile
    Path to the WARA configuration JSON file.

.PARAMETER OutputDirectory
    Directory where output files will be saved.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$ConfigFile,
    
    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory
)

# Import required modules
Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.Resources -ErrorAction Stop
Import-Module Az.Storage -ErrorAction Stop

# Load configuration
Write-Host "Loading configuration from $ConfigFile"
if (-not (Test-Path $ConfigFile -PathType Leaf)) {
    throw "Configuration file not found: $ConfigFile"
}

try {
    $config = Get-Content -Path $ConfigFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    
    # Set environment variables from config
    $env:tenantId = $config.azure.tenantId
    $env:subscriptionId = $config.azure.subscriptionId
    
    # Ensure output directory exists
    if (-not (Test-Path $OutputDirectory)) {
        New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    }
    
    # Save the config to the output directory for reference
    $config | ConvertTo-Json -Depth 10 | Out-File -FilePath "$OutputDirectory/wara-config.json" -Force
    
    # Check if we're already connected to Azure
    $context = Get-AzContext -ErrorAction SilentlyContinue
    if ($null -ne $context -and $context.Account -ne $null) {
        Write-Host "Already connected to Azure as $($context.Account.Id)"
        
        # Check if we need to switch subscriptions
        if ($context.Subscription.Id -ne $config.azure.subscriptionId) {
            Write-Host "Switching to subscription $($config.azure.subscriptionName) ($($config.azure.subscriptionId))"
            $context = Set-AzContext -Subscription $config.azure.subscriptionId -ErrorAction Stop
        }
        
        return $config
    }
    
    # Connect to Azure using the service principal from Azure DevOps
    Write-Host "Connecting to Azure with service principal..."
    $connectionResult = Connect-AzAccount -ServicePrincipal -Tenant $config.azure.tenantId -ErrorAction Stop
    
    # Get the current context
    $context = Get-AzContext -ErrorAction Stop
    
    if ($null -eq $context -or $null -eq $context.Account) {
        throw "Failed to authenticate with Azure. No context or account information available."
    }
    
    Write-Host "Successfully connected to Azure as $($context.Account.Id)"
    
    # List available subscriptions for debugging
    $subscriptions = Get-AzSubscription -ErrorAction Stop
    Write-Host "Available subscriptions:"
    $subscriptions | Format-Table Name, Id, TenantId -AutoSize
    
    # Set the subscription
    Write-Host "Setting context to subscription: $($config.azure.subscriptionName) ($($config.azure.subscriptionId))"
    $context = Set-AzContext -Subscription $config.azure.subscriptionId -ErrorAction Stop
    
    # Verify the current context
    $context = Get-AzContext -ErrorAction Stop
    Write-Host "Current context: $($context.Account.Id) in subscription $($context.Subscription.Name) ($($context.Subscription.Id))"
    
    # Output the configuration for debugging
    Write-Host "WARA Configuration:"
    $config | ConvertTo-Json -Depth 3 | Write-Host
    
    return $config
}
catch {
    Write-Error "Failed to initialize WARA assessment: $_"
    Write-Error $_.ScriptStackTrace
    throw $_
}
