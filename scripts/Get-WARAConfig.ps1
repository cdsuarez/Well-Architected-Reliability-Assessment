<#
.SYNOPSIS
    Loads and validates the WARA assessment configuration.

.DESCRIPTION
    This script loads the WARA configuration from a JSON file and validates
    the required settings. It also provides helper functions to access
    configuration values.

.PARAMETER ConfigPath
    Path to the WARA configuration JSON file.

.EXAMPLE
    $config = .\scripts\Get-WARAConfig.ps1 -ConfigPath .\wara-tenant-config.json
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [ValidateScript({
        if (-not (Test-Path -Path $_ -PathType Leaf)) {
            throw "Configuration file not found: $_"
        }
        return $true
    })]
    [string]$ConfigPath
)

# Load the configuration file
try {
    $config = Get-Content -Path $ConfigPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
}
catch {
    throw "Failed to load configuration file '$ConfigPath': $_"
}

# Validate required fields
$requiredFields = @(
    @{ Path = 'azure.tenantId'; Type = 'string' },
    @{ Path = 'assessment.customerName'; Type = 'string' },
    @{ Path = 'assessment.workloadName'; Type = 'string' }
)

# Validate subscription configuration
if (-not $config.azure.assessAllSubscriptions -and -not $config.azure.subscriptionId) {
    throw "Either 'subscriptionId' must be provided or 'assessAllSubscriptions' must be set to true"
}

# Set default values for subscription filter if not provided
if (-not $config.azure.subscriptionFilter) {
    $config.azure | Add-Member -MemberType NoteProperty -Name 'subscriptionFilter' -Value @{
        includedSubscriptions = @()
        excludedSubscriptions = @()
        includedTags = @{}
        excludedTags = @{}
    }
}

foreach ($field in $requiredFields) {
    $path = $field.Path
    $value = $config
    $pathParts = $path -split '\.'
    
    foreach ($part in $pathParts) {
        if ($null -eq $value -or -not (Get-Member -InputObject $value -Name $part -ErrorAction SilentlyContinue)) {
            throw "Missing required configuration field: $path"
        }
        $value = $value.$part
    }
    
    if ($field.Type -eq 'array' -and $value -isnot [array]) {
        $value = @($value)
        $config.($pathParts[0]).($pathParts[1]) = $value
    }
}

# Helper function to get a configuration value
function Get-WARAConfigValue {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,
        
        [Parameter(Mandatory = $false)]
        $DefaultValue = $null
    )
    
    $value = $config
    $pathParts = $Path -split '\.'
    
    foreach ($part in $pathParts) {
        if ($null -eq $value -or -not (Get-Member -InputObject $value -Name $part -ErrorAction SilentlyContinue)) {
            return $DefaultValue
        }
        $value = $value.$part
    }
    
    return $value
}

# Add helper methods to the config object
$config | Add-Member -MemberType ScriptMethod -Name 'GetValue' -Value {
    param($Path, $DefaultValue = $null)
    return Get-WARAConfigValue -Path $Path -DefaultValue $DefaultValue
}

# Add subscription IDs as an array
$subscriptionIds = @()

if ($config.azure.assessAllSubscriptions) {
    # Get all accessible subscriptions
    $allSubs = Get-AzSubscription -TenantId $config.azure.tenantId -WarningAction SilentlyContinue
    
    # Apply subscription filters
    $filteredSubs = $allSubs | Where-Object {
        $sub = $_
        $include = $true
        
        # Filter by included subscriptions
        if ($config.azure.subscriptionFilter.includedSubscriptions -and 
            $config.azure.subscriptionFilter.includedSubscriptions.Count -gt 0) {
            $include = $include -and ($sub.Id -in $config.azure.subscriptionFilter.includedSubscriptions -or 
                                     $sub.Name -in $config.azure.subscriptionFilter.includedSubscriptions)
        }
        
        # Filter by excluded subscriptions
        if ($config.azure.subscriptionFilter.excludedSubscriptions -and 
            $config.azure.subscriptionFilter.excludedSubscriptions.Count -gt 0) {
            $include = $include -and ($sub.Id -notin $config.azure.subscriptionFilter.excludedSubscriptions -and 
                                     $sub.Name -notin $config.azure.subscriptionFilter.excludedSubscriptions)
        }
        
        # Filter by included tags
        if ($config.azure.subscriptionFilter.includedTags -and 
            $config.azure.subscriptionFilter.includedTags.PSObject.Properties.Count -gt 0) {
            $include = $include -and (& {
                $hasAllTags = $true
                $tags = $sub.Tags
                if (-not $tags) { return $false }
                
                $config.azure.subscriptionFilter.includedTags.PSObject.Properties | ForEach-Object {
                    $tagName = $_.Name
                    $tagValue = $_.Value
                    if (-not ($tags.ContainsKey($tagName) -and ($null -eq $tagValue -or $tags[$tagName] -eq $tagValue))) {
                        $hasAllTags = $false
                    }
                }
                return $hasAllTags
            })
        }
        
        # Filter by excluded tags
        if ($config.azure.subscriptionFilter.excludedTags -and 
            $config.azure.subscriptionFilter.excludedTags.PSObject.Properties.Count -gt 0) {
            $include = $include -and -not (& {
                $hasAnyExcludedTag = $false
                $tags = $sub.Tags
                if (-not $tags) { return $false }
                
                $config.azure.subscriptionFilter.excludedTags.PSObject.Properties | ForEach-Object {
                    $tagName = $_.Name
                    $tagValue = $_.Value
                    if ($tags.ContainsKey($tagName) -and ($null -eq $tagValue -or $tags[$tagName] -eq $tagValue)) {
                        $hasAnyExcludedTag = $true
                    }
                }
                return $hasAnyExcludedTag
            })
        }
        
        return $include
    }
    
    $subscriptionIds = $filteredSubs | ForEach-Object { "/subscriptions/$($_.Id)" }
    Write-Host "Found $($subscriptionIds.Count) subscriptions to assess"
    
    # Set the first subscription as the default for operations that need one
    if ($subscriptionIds.Count -gt 0) {
        $config.azure.subscriptionId = $filteredSubs[0].Id
        $config.azure.subscriptionName = $filteredSubs[0].Name
    }
} else {
    $subscriptionIds = @("/subscriptions/$($config.azure.subscriptionId)")
}

$config.azure | Add-Member -MemberType NoteProperty -Name 'subscriptionIds' -Value $subscriptionIds -Force

# Add specialized workloads parameters
$specializedParams = @{}
if ($config.assessment.includeSpecializedWorkloads -and $config.assessment.specializedWorkloads.Count -gt 0) {
    foreach ($workload in $config.assessment.specializedWorkloads) {
        $paramName = $workload.ToUpper()
        $specializedParams[$paramName] = $true
    }
}

# Add specialized workloads to the config
$config.assessment | Add-Member -MemberType NoteProperty -Name 'specializedWorkloadParams' -Value $specializedParams

# Return the configuration object
return $config
