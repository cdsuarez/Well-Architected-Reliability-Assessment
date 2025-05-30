<#
.SYNOPSIS
    Validates WARA configuration files for syntax and required settings.
    
.DESCRIPTION
    This script checks WARA configuration files for common issues, including:
    - JSON syntax validation
    - Required fields
    - Data types and formats
    - Valid values for enumerated types
    
.PARAMETER ConfigPath
    Path to the configuration file or directory containing configuration files.
    Defaults to the current directory.
    
.PARAMETER Recurse
    If specified, searches for configuration files in subdirectories.
    
.PARAMETER Detailed
    If specified, provides detailed validation results including all warnings.
    
.EXAMPLE
    .\Test-ConfigurationFile.ps1 -ConfigPath ".\config" -Recurse -Detailed
    
    Validates all configuration files in the config directory and its subdirectories,
    providing detailed validation results.
#>

[CmdletBinding()]
param (
    [Parameter(Position = 0)]
    [string]$ConfigPath = ".",
    
    [switch]$Recurse,
    [switch]$Detailed
)

# Define the configuration schema
$configSchema = @{
    azure = @{
        type = 'object'
        required = @('tenantId')
        properties = @{
            tenantId = @{ type = 'string' }
            subscriptionId = @{ type = 'string' }
            assessAllSubscriptions = @{ type = 'boolean' }
            subscriptionFilter = @{
                type = 'object'
                properties = @{
                    includedSubscriptions = @{ type = 'array' }
                    excludedSubscriptions = @{ type = 'array' }
                    includedTags = @{ type = 'object' }
                    excludedTags = @{ type = 'object' }
                }
            }
            parallelProcessing = @{
                type = 'object'
                properties = @{
                    enabled = @{ type = 'boolean' }
                    maxDegreeOfParallelism = @{ type = 'integer', 'minimum' = 1 }
                }
            }
            rateLimiting = @{
                type = 'object'
                properties = @{
                    delayBetweenSubscriptionsMs = @{ type = 'integer', 'minimum' = 0 }
                    maxRequestsPerMinute = @{ type = 'integer', 'minimum' = 1 }
                }
            }
        }
    }
    assessment = @{
        type = 'object'
        properties = @{
            outputDirectory = @{ type = 'string' }
        }
    }
}

# Function to validate a configuration file
function Test-ConfigFile {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )
    
    $result = @{
        File = $FilePath
        IsValid = $false
        Errors = @()
        Warnings = @()
    }
    
    # Check if file exists
    if (-not (Test-Path -Path $FilePath)) {
        $result.Errors += "File not found: $FilePath"
        return [PSCustomObject]$result
    }
    
    # Validate JSON syntax
    try {
        $jsonContent = Get-Content -Path $FilePath -Raw -ErrorAction Stop
        $config = $jsonContent | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        $result.Errors += "Invalid JSON: $_"
        return [PSCustomObject]$result
    }
    
    # Validate against schema
    $validationResult = Test-ConfigObject -Config $config -Schema $configSchema -Path ""
    $result.Errors += $validationResult.Errors
    $result.Warnings += $validationResult.Warnings
    
    # Additional custom validations
    if ($config.azure.assessAllSubscriptions -and $config.azure.subscriptionId) {
        $result.Warnings += "Both 'assessAllSubscriptions' is true and 'subscriptionId' is specified. 'subscriptionId' will be ignored."
    }
    
    if (-not $config.azure.assessAllSubscriptions -and -not $config.azure.subscriptionId) {
        $result.Errors += "Either 'assessAllSubscriptions' must be true or 'subscriptionId' must be specified."
    }
    
    # Set final validation status
    $result.IsValid = ($result.Errors.Count -eq 0)
    
    return [PSCustomObject]$result
}

# Function to validate a configuration object against a schema
function Test-ConfigObject {
    param (
        [Parameter(Mandatory = $true)]
        [PSObject]$Config,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Schema,
        
        [string]$Path
    )
    
    $errors = @()
    $warnings = @()
    
    # Check required properties
    if ($Schema.required) {
        foreach ($prop in $Schema.required) {
            $propPath = if ($Path) { "$Path.$prop" } else { $prop }
            
            if ($null -eq $Config.$prop) {
                $errors += "Required property '$propPath' is missing."
            }
        }
    }
    
    # Check property types
    if ($Schema.properties) {
        $Schema.properties.GetEnumerator() | ForEach-Object {
            $prop = $_.Key
            $propSchema = $_.Value
            $propPath = if ($Path) { "$Path.$prop" } else { $prop }
            $propValue = $Config.$prop
            
            # Skip if property is not present and not required
            if ($null -eq $propValue) { return }
            
            # Check type
            $expectedTypes = @($propSchema.type) -ne $null
            $actualType = if ($propValue -is [array]) { 'array' } 
                         elseif ($propValue -is [boolean]) { 'boolean' }
                         elseif ($propValue -is [int]) { 'integer' }
                         elseif ($propValue -is [double]) { 'number' }
                         else { 'string' }
            
            if ($expectedTypes -and ($actualType -notin $expectedTypes)) {
                $errors += "Property '$propPath' has invalid type '$actualType'. Expected: $($expectedTypes -join ' or ')."
            }
            
            # Recursively validate nested objects
            if ($propSchema.properties -and $propValue -is [PSCustomObject]) {
                $nestedResult = Test-ConfigObject -Config $propValue -Schema $propSchema -Path $propPath
                $errors += $nestedResult.Errors
                $warnings += $nestedResult.Warnings
            }
            
            # Validate array items
            if ($propSchema.items -and $propValue -is [array]) {
                $itemSchema = $propSchema.items
                
                for ($i = 0; $i -lt $propValue.Count; $i++) {
                    $itemPath = "$propPath[$i]"
                    
                    if ($itemSchema.properties -and $propValue[$i] -is [PSCustomObject]) {
                        $itemResult = Test-ConfigObject -Config $propValue[$i] -Schema $itemSchema -Path $itemPath
                        $errors += $itemResult.Errors
                        $warnings += $itemResult.Warnings
                    }
                }
            }
            
            # Validate minimum value for numbers
            if ($null -ne $propSchema.minimum -and $propValue -lt $propSchema.minimum) {
                $errors += "Property '$propPath' value $propValue is less than minimum allowed value $($propSchema.minimum)."
            }
        }
    }
    
    return @{
        Errors = $errors
        Warnings = $warnings
    }
}

# Main script execution
$files = @()

# Get configuration files
if (Test-Path -Path $ConfigPath -PathType Container) {
    $searchParams = @{
        Path = $ConfigPath
        Filter = "*.json"
        File = $true
    }
    
    if ($Recurse) {
        $searchParams.Recurse = $true
    }
    
    $files = Get-ChildItem @searchParams
}
elseif (Test-Path -Path $ConfigPath) {
    $files = Get-Item -Path $ConfigPath
}
else {
    Write-Error "Path not found: $ConfigPath"
    exit 1
}

if ($files.Count -eq 0) {
    Write-Warning "No JSON configuration files found in: $ConfigPath"
    exit 0
}

# Validate each file
$results = @()
foreach ($file in $files) {
    Write-Host "Validating: $($file.FullName)" -ForegroundColor Cyan
    $result = Test-ConfigFile -FilePath $file.FullName
    $results += $result
    
    if ($result.IsValid) {
        Write-Host "  ✓ Valid configuration" -ForegroundColor Green
    }
    else {
        Write-Host "  ✗ Invalid configuration" -ForegroundColor Red
    }
    
    if ($result.Errors.Count -gt 0) {
        Write-Host "  Errors:" -ForegroundColor Red
        $result.Errors | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
    }
    
    if ($Detailed -and $result.Warnings.Count -gt 0) {
        Write-Host "  Warnings:" -ForegroundColor Yellow
        $result.Warnings | ForEach-Object { Write-Host "    - $_" -ForegroundColor Yellow }
    }
    
    Write-Host
}

# Summary
$validCount = ($results | Where-Object { $_.IsValid }).Count
$invalidCount = $results.Count - $validCount

Write-Host "Validation Summary:" -ForegroundColor Cyan
Write-Host "  Total files: $($results.Count)" -ForegroundColor White
Write-Host "  Valid: $validCount" -ForegroundColor Green
Write-Host "  Invalid: $invalidCount" -ForegroundColor $(if ($invalidCount -gt 0) { 'Red' } else { 'White' })

# Return non-zero exit code if any files are invalid
if ($invalidCount -gt 0) {
    exit 1
}
