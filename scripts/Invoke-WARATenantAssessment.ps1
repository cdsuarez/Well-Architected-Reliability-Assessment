<#
.SYNOPSIS
    Performs a Well-Architected Reliability Assessment across multiple subscriptions in a tenant.

.DESCRIPTION
    This script runs the WARA collector across multiple subscriptions in a tenant, either all accessible subscriptions
    or a filtered subset based on the provided configuration. It supports parallel processing and rate limiting.

.PARAMETER ConfigFile
    Path to the JSON configuration file containing assessment settings.

.PARAMETER ResumeFrom
    Optional. Subscription ID to resume processing from (useful for resuming failed runs).

.PARAMETER ThrottleLimit
    Optional. Maximum number of parallel assessments to run. Default is 5.

.EXAMPLE
    # Run with default settings
    .\Invoke-WARATenantAssessment.ps1 -ConfigFile .\wara-tenant-config.json

.EXAMPLE
    # Run with custom parallelism and resume from a subscription
    .\Invoke-WARATenantAssessment.ps1 -ConfigFile .\wara-tenant-config.json -ThrottleLimit 3 -ResumeFrom '00000000-0000-0000-0000-000000000001'

.NOTES
    Version: 2.0.0
    Author: Microsoft Corporation
    Features:
    - Parallel subscription processing
    - Rate limiting and throttling
    - Resume capability
    - Detailed progress reporting
    - Comprehensive error handling
#>

#region Script Parameters
<#
.SYNOPSIS
    Performs a Well-Architected Reliability Assessment across multiple subscriptions in a tenant.

.DESCRIPTION
    This script runs the WARA collector across multiple subscriptions in a tenant, either all accessible subscriptions
    or a filtered subset based on the provided configuration. It supports parallel processing and rate limiting.

.PARAMETER ConfigFile
    Path to the JSON configuration file containing assessment settings.

.PARAMETER ResumeFrom
    Optional. Subscription ID to resume processing from (useful for resuming failed runs).

.PARAMETER ThrottleLimit
    Optional. Maximum number of parallel assessments to run. Default is 5.

.EXAMPLE
    # Run with default settings
    .\Invoke-WARATenantAssessment.ps1 -ConfigFile .\wara-tenant-config.json

.EXAMPLE
    # Run with custom parallelism and resume from a subscription
    .\Invoke-WARATenantAssessment.ps1 -ConfigFile .\wara-tenant-config.json -ThrottleLimit 3 -ResumeFrom '00000000-0000-0000-0000-000000000001'
#>
# Suppress script analyzer warnings for this section
[Diagnostics.CodeAnalysis.SuppressMessage('PSUseShouldProcessForStateChangingFunctions', '')]
[Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '')]

# Define script parameters
param (
    [Parameter(Mandatory = $true,
               HelpMessage = 'Path to the JSON configuration file')]
    [ValidateScript({
        if (-not (Test-Path $_ -PathType 'Leaf')) {
            throw "Config file $_ not found"
        }
        return $true
    })]
    [string]$ConfigFile,

    [Parameter(Mandatory = $false,
               HelpMessage = 'Subscription ID to resume processing from')]
    [string]$ResumeFrom,

    [Parameter(Mandatory = $false,
               HelpMessage = 'Maximum number of parallel assessments')]
    [ValidateRange(1, 20)]
    [int]$ThrottleLimit = 5
)
#endregion

# Initialize counters and tracking
$script:totalProcessed = 0
$script:totalSucceeded = 0
$script:totalFailed = 0
$script:startTime = Get-Date
$script:rateLimitLastCall = $null
$script:rateLimitDelayMs = 1000  # Default delay between API calls in ms
$script:lock = [System.Threading.ReaderWriterLockSlim]::new()

# Function to respect rate limits
function Invoke-RateLimitedRequest {
    param (
        [scriptblock]$ScriptBlock
    )
    
    $script:lock.EnterWriteLock()
    try {
        $now = Get-Date
        if ($null -ne $script:rateLimitLastCall) {
            $timeSinceLastCall = ($now - $script:rateLimitLastCall).TotalMilliseconds
            if ($timeSinceLastCall -lt $script:rateLimitDelayMs) {
                $sleepTime = [math]::Ceiling($script:rateLimitDelayMs - $timeSinceLastCall)
                Start-Sleep -Milliseconds $sleepTime
            }
        }
        
        $result = & $ScriptBlock
        $script:rateLimitLastCall = Get-Date
        return $result
    }
    finally {
        $script:lock.ExitWriteLock()
    }
}

# Import required modules
$requiredModules = @(
    @{ Name = 'Az.Accounts'; Version = '2.0.0' },
    @{ Name = 'Az.Resources'; Version = '6.0.0' }
)

foreach ($module in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $module.Name -ErrorAction SilentlyContinue)) {
        Install-Module -Name $module.Name -RequiredVersion $module.Version -Force -Scope CurrentUser -AllowClobber -ErrorAction Stop
    }
    Import-Module $module.Name -RequiredVersion $module.Version -ErrorAction Stop
}

# Import WARA module
$waraModulePath = Join-Path $PSScriptRoot '..\src\modules\wara'
if (-not (Test-Path $waraModulePath)) {
    throw "WARA module not found at $waraModulePath"
}
Import-Module $waraModulePath -Force -ErrorAction Stop

# Load and validate configuration
function Get-ValidatedConfig {
    param (
        [string]$ConfigPath
    )
    
    if (-not (Test-Path $ConfigPath)) {
        throw "Configuration file not found: $ConfigPath"
    }
    
    try {
        $config = Get-Content -Path $ConfigPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Failed to parse configuration file: $_"
    }
    
    # Validate required fields
    $requiredFields = @('azure')
    foreach ($field in $requiredFields) {
        if (-not $config.PSObject.Properties.Name -contains $field) {
            throw "Missing required configuration section: $field"
        }
    }
    
    # Set defaults
    if (-not $config.azure.PSObject.Properties.Name -contains 'subscriptionFilter') {
        $config.azure | Add-Member -MemberType NoteProperty -Name 'subscriptionFilter' -Value @{
            includedSubscriptions = @()
            excludedSubscriptions = @()
            includedTags = @{}
            excludedTags = @{}
        } -Force
    }
    
    # Set parallel processing defaults
    if (-not $config.azure.PSObject.Properties.Name -contains 'parallelProcessing') {
        $config.azure | Add-Member -MemberType NoteProperty -Name 'parallelProcessing' -Value @{
            enabled = $true
            maxDegreeOfParallelism = $ThrottleLimit
        } -Force
    }
    
    # Set rate limiting defaults
    if (-not $config.azure.PSObject.Properties.Name -contains 'rateLimiting') {
        $config.azure | Add-Member -MemberType NoteProperty -Name 'rateLimiting' -Value @{
            delayBetweenSubscriptionsMs = 1000
            maxRequestsPerMinute = 30
        } -Force
    }
    
    # Set assessment defaults
    if (-not $config.PSObject.Properties.Name -contains 'assessment') {
        $config | Add-Member -MemberType NoteProperty -Name 'assessment' -Value @{
            outputDirectory = "./assessment-results"
        } -Force
    }
    
    # Validate tenant ID
    if (-not $config.azure.tenantId) {
        throw "Tenant ID is required in the configuration file"
    }
    
    # Validate subscription configuration
    if (-not $config.azure.assessAllSubscriptions -and -not $config.azure.subscriptionId) {
        throw "Either subscriptionId must be provided or assessAllSubscriptions must be set to true"
    }
    
    return $config
}

# Load configuration
$config = Get-ValidatedConfig -ConfigPath $ConfigFile

# Rate limiting variables
$script:rateLimitDelayMs = [math]::Max(1000 / ($config.azure.rateLimiting.maxRequestsPerMinute / 60), 100)  # Minimum 100ms between calls
$script:lastRequestTime = [DateTime]::MinValue
$script:rateLimitLock = [System.Threading.ReaderWriterLockSlim]::new()
$script:resumeFrom = $ResumeFromSubscriptionId
$script:resumeFound = $false

# Function to handle rate limiting for API calls
function Invoke-RateLimitedRequest {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        
        [int]$MaxRetries = 3,
        [int]$InitialDelayMs = 1000
    )
    
    $retryCount = 0
    $delayMs = $InitialDelayMs
    $lastError = $null
    
    do {
        try {
            # Apply rate limiting
            $script:rateLimitLock.EnterWriteLock()
            try {
                $timeSinceLastRequest = (Get-Date) - $script:lastRequestTime
                $timeToWait = [math]::Max(0, $script:rateLimitDelayMs - $timeSinceLastRequest.TotalMilliseconds)
                
                if ($timeToWait -gt 0) {
                    Start-Sleep -Milliseconds $timeToWait
                }
                
                $result = & $ScriptBlock
                $script:lastRequestTime = Get-Date
                return $result
            }
            finally {
                $script:rateLimitLock.ExitWriteLock()
            }
        }
        catch [Microsoft.Rest.Azure.CloudException] {
            $lastError = $_
            
            # Check for rate limit exceeded (429) or server error (5xx)
            $statusCode = $_.Exception.Response.StatusCode.value__
            $isRateLimitError = $statusCode -eq 429 -or ($statusCode -ge 500 -and $statusCode -lt 600)
            
            if (-not $isRateLimitError -or $retryCount -ge $MaxRetries) {
                throw
            }
            
            # Exponential backoff with jitter
            $jitter = Get-Random -Minimum 500 -Maximum 1000
            $delayMs = [math]::Min($delayMs * 2 + $jitter, 30000)  # Max 30 seconds
            
            Write-Warning "Request failed with status $statusCode. Retrying in $($delayMs)ms... (Attempt $($retryCount + 1)/$MaxRetries)"
            Start-Sleep -Milliseconds $delayMs
            $retryCount++
        }
    } while ($retryCount -lt $MaxRetries)
    
    # If we get here, all retries failed
    throw $lastError
}

# Function to check if a subscription matches the filter criteria
function Test-SubscriptionFilter {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [Microsoft.Azure.Commands.Profile.Models.PSAzureSubscription]$Subscription,
        
        [Parameter(
            Mandatory = $true,
            HelpMessage = 'The filter criteria for subscriptions',
            ValueFromPipelineByPropertyName = $true
        )]
        [PSCustomObject]$Filter,
        
        [Parameter(Mandatory = $false)]
        [switch]$SkipResumeCheck
    )

    # Skip if we're resuming and this subscription hasn't been processed yet
    if (-not $SkipResumeCheck -and $script:resumeFrom -and $Subscription.Id -ne $script:resumeFrom) {
        if (-not $script:resumeFound) {
            Write-Verbose "Skipping subscription $($Subscription.Name) (ID: $($Subscription.Id)) - resuming from $($script:resumeFrom)"
            return $false
        }
    }
    elseif ($script:resumeFrom -and $Subscription.Id -eq $script:resumeFrom) {
        $script:resumeFound = $true
        Write-Host "Resuming from subscription: $($Subscription.Name) (ID: $Subscription.Id)" -ForegroundColor Cyan
    }

    # Check if subscription is in the excluded list
    if ($Filter.excludedSubscriptions.Count -gt 0) {
        if ($Subscription.Id -in $Filter.excludedSubscriptions -or 
            $Subscription.Name -in $Filter.excludedSubscriptions) {
            Write-Verbose "Excluding subscription: $($Subscription.Name) (ID: $($Subscription.Id)) - Matched excluded list"
            return $false
        }
    }

    # Check if subscription is in the included list (if any included filters are specified)
    if ($Filter.includedSubscriptions.Count -gt 0) {
        if ($Subscription.Id -notin $Filter.includedSubscriptions -and 
            $Subscription.Name -notin $Filter.includedSubscriptions) {
            Write-Verbose "Excluding subscription: $($Subscription.Name) (ID: $($Subscription.Id)) - Not in included list"
            return $false
        }
    }

    # Check included tags (all must match)
    if ($Filter.includedTags -and $Filter.includedTags.PSObject.Properties.Count -gt 0) {
        $tags = $Subscription.Tags
        if (-not $tags) {
            Write-Verbose "Excluding subscription: $($Subscription.Name) (ID: $($Subscription.Id)) - No tags found but included tags are required"
            return $false
        }

        foreach ($tag in $Filter.includedTags.PSObject.Properties) {
            $tagName = $tag.Name
            $tagValue = $tag.Value
            
            if (-not $tags.ContainsKey($tagName) -or 
                ($null -ne $tagValue -and $tags[$tagName] -ne $tagValue)) {
                Write-Verbose "Excluding subscription: $($Subscription.Name) (ID: $($Subscription.Id)) - Missing or mismatched tag: $tagName"
                return $false
            }
        }
    }

    # Check excluded tags (none should match)
    if ($Filter.excludedTags -and $Filter.excludedTags.PSObject.Properties.Count -gt 0) {
        $tags = $Subscription.Tags
        if ($tags) {
            foreach ($tag in $Filter.excludedTags.PSObject.Properties) {
                $tagName = $tag.Name
                $tagValue = $tag.Value
                
                if ($tags.ContainsKey($tagName) -and 
                    ($null -eq $tagValue -or $tags[$tagName] -eq $tagValue)) {
                    Write-Verbose "Excluding subscription: $($Subscription.Name) (ID: $($Subscription.Id)) - Matched excluded tag: $tagName"
                    return $false
                }
            }
        }
    }

    return $true
}

# Function to process a single subscription
function Invoke-SubscriptionProcessing {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [Microsoft.Azure.Commands.Profile.Models.PSAzureSubscription]$Subscription,
        
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config,
        
        [Parameter(Mandatory = $true)]
        [string]$OutputDir,
        
        [Parameter(Mandatory = $true)]
        [int]$TotalSubscriptions,
        
        [Parameter(Mandatory = $true)]
        [ref]$ProcessedCount,
        
        [Parameter(Mandatory = $true)]
        [ref]$SucceededCount,
        
        [Parameter(Mandatory = $true)]
        [ref]$FailedCount
    )
    
    $subscriptionId = $Subscription.Id
    $subscriptionName = $Subscription.Name
    $subscriptionNumber = $ProcessedCount.Value++
    
    $result = [PSCustomObject]@{
        SubscriptionId = $subscriptionId
        SubscriptionName = $subscriptionName
        OutputFile = $null
        Status = 'NotStarted'
        StartTime = Get-Date
        EndTime = $null
        Duration = $null
        Error = $null
    }
    
    $tempConfigFile = $null
    
    try {
        Write-Progress -Activity "Processing Subscriptions" -Status "($subscriptionNumber/$TotalSubscriptions) $subscriptionName" `
            -PercentComplete (($subscriptionNumber / $TotalSubscriptions) * 100)
        
        # Set the current subscription context with rate limiting
        $null = Invoke-RateLimitedRequest -ScriptBlock {
            Set-AzContext -Subscription $subscriptionId -Force -ErrorAction Stop | Out-Null
        }
        
        # Create a temporary config file for this subscription
        $tempConfig = $Config.PSObject.Copy()
        $tempConfig.azure.subscriptionId = $subscriptionId
        $tempConfig.azure.subscriptionName = $subscriptionName
        $tempConfig.azure.assessAllSubscriptions = $false
        
        $tempConfigFile = Join-Path $env:TEMP "wara_temp_$(Get-Date -Format 'yyyyMMddHHmmss')_${subscriptionId}.json"
        $tempConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $tempConfigFile -Force
        
        # Run the WARA collector for this subscription with error handling
        try {
            $outputFile = Start-WARACollector -ConfigFile $tempConfigFile -PassThru -ErrorAction Stop
        }
        catch {
            Write-Error "Failed to run WARA collector for subscription $subscriptionName ($subscriptionId): $_"
            throw
        }
        
        if ($outputFile) {
            $result.OutputFile = $outputFile
            $result.Status = 'Success'
            $SucceededCount.Value++
            
            Write-Host "  ✓ [$subscriptionNumber/$TotalSubscriptions] Assessment completed for $subscriptionName" -ForegroundColor Green
            Write-Host "    Output: $outputFile" -ForegroundColor DarkGray
        } else {
            $result.Status = 'Failed - No output file generated'
            $result.Error = 'No output file generated by collector'
            $FailedCount.Value++
            
            Write-Warning "  ✗ [$subscriptionNumber/$TotalSubscriptions] Assessment did not generate output for $subscriptionName"
        }
    }
    catch {
        $errorMsg = $_.Exception.Message
        $result.Status = "Failed - $errorMsg"
        $result.Error = $errorMsg
        $FailedCount.Value++
        
        Write-Warning "  ✗ [$subscriptionNumber/$TotalSubscriptions] Assessment failed for $subscriptionName : $errorMsg"
        Write-Debug $_.ScriptStackTrace
    }
    finally {
        # Clean up temporary config file
        if ($tempConfigFile -and (Test-Path $tempConfigFile)) {
            Remove-Item -Path $tempConfigFile -Force -ErrorAction SilentlyContinue
        }
        
        $result.EndTime = Get-Date
        $result.Duration = $result.EndTime - $result.StartTime
        
        # Add delay between subscriptions if configured
        if ($config.azure.rateLimiting.delayBetweenSubscriptionsMs -gt 0) {
            Start-Sleep -Milliseconds $config.azure.rateLimiting.delayBetweenSubscriptionsMs
        }
    }
    
    return $result
}

# Main execution
$ErrorActionPreference = 'Stop'

# Create output directory if it doesn't exist
$outputDir = $OutputDirectory
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

# Initialize counters
$subscriptionResults = @()
$processedCount = 0
$succeededCount = 0
$failedCount = 0

try {
    # Connect to Azure if not already connected
    $context = Get-AzContext -ErrorAction SilentlyContinue
    if (-not $context) {
        Write-Host "Connecting to Azure..."
        $context = Connect-AzAccount -Tenant $config.azure.tenantId -ErrorAction Stop
    }
    
    # Get all subscriptions
    Write-Host "Retrieving subscriptions..."
    $allSubscriptions = @()
    
    try {
        $allSubscriptions = Invoke-RateLimitedRequest -ScriptBlock {
            Get-AzSubscription -TenantId $config.azure.tenantId -ErrorAction Stop | Where-Object { $_.State -eq 'Enabled' }
        }
    }
    catch {
        Write-Error "Failed to retrieve subscriptions: $_"
        exit 1
    }
    
    if (-not $allSubscriptions) {
        Write-Warning "No active subscriptions found in the tenant."
        return
    }
    
    # Filter subscriptions
    $filteredSubscriptions = @()
    $subscriptionCount = $allSubscriptions.Count
    $currentSubscription = 0
    
    Write-Host "Filtering subscriptions..."
    foreach ($sub in $allSubscriptions) {
        $currentSubscription++
        Write-Progress -Activity "Filtering Subscriptions" -Status "$currentSubscription/$subscriptionCount" `
            -PercentComplete (($currentSubscription / $subscriptionCount) * 100)
        
        # Skip if we're resuming and haven't found the resume point yet
        if (-not (Test-SubscriptionFilter -Subscription $sub -Filter $config.azure.subscriptionFilter)) {
            continue
        }
        
        $filteredSubscriptions += $sub
    }
    
    $totalSubscriptions = $filteredSubscriptions.Count
    
    if ($totalSubscriptions -eq 0) {
        Write-Warning "No subscriptions match the specified filters."
        return
    }
    
    Write-Host "Found $totalSubscriptions subscription(s) to process."
    
    # Process subscriptions in parallel or sequentially
    $scriptBlock = {
        param($subscription, $config, $outputDir, $totalSubscriptions, $processedCountRef, $succeededCountRef, $failedCountRef)
        
        try {
            $result = Invoke-SubscriptionProcessing -Subscription $subscription -Config $config -OutputDir $outputDir `
                -TotalSubscriptions $totalSubscriptions -ProcessedCount $processedCountRef `
                -SucceededCount $succeededCountRef -FailedCount $failedCountRef
            return $result
        }
        catch {
            Write-Error "Error processing subscription $($subscription.Name) ($($subscription.Id)): $_"
            return @{
                SubscriptionId = $subscription.Id
                SubscriptionName = $subscription.Name
                Status = "Error: $_"
                Error = $_.ToString()
            }
        }
    }
    
    # Create runspace pool if parallel processing is enabled
    if ($config.azure.parallelProcessing.enabled -and $totalSubscriptions -gt 1) {
        $maxThreads = [math]::Min($config.azure.parallelProcessing.maxDegreeOfParallelism, $totalSubscriptions)
        Write-Host "Processing $totalSubscriptions subscriptions in parallel (max $maxThreads at a time)..."
        
        # Create runspace pool
        $runspacePool = [runspacefactory]::CreateRunspacePool(1, $maxThreads)
        $runspacePool.Open()
        
        $runspaces = @()
        $subscriptionResults = @()
        
        try {
            # Create and start runspaces
            foreach ($sub in $filteredSubscriptions) {
                $ps = [powershell]::Create()
                $ps.RunspacePool = $runspacePool
                
                [void]$ps.AddScript($scriptBlock).AddParameters(@(
                    $sub, $config, $outputDir, $totalSubscriptions,
                    ([ref]$processedCount), ([ref]$succeededCount), ([ref]$failedCount)
                ))
                
                $runspace = @{
                    PowerShell = $ps
                    Handle = $ps.BeginInvoke()
                }
                
                $runspaces += $runspace
            }
            
            # Process results as they complete
            while ($runspaces.Count -gt 0) {
                for ($i = $runspaces.Count - 1; $i -ge 0; $i--) {
                    $runspace = $runspaces[$i]
                    
                    if ($runspace.Handle.IsCompleted) {
                        try {
                            $result = $runspace.PowerShell.EndInvoke($runspace.Handle)
                            if ($result) {
                                $subscriptionResults += $result
                            }
                        }
                        catch {
                            Write-Error "Error in runspace: $_"
                        }
                        finally {
                            $runspace.PowerShell.Dispose()
                            $runspaces.RemoveAt($i)
                        }
                    }
                }
                
                if ($runspaces.Count -gt 0) {
                    Start-Sleep -Milliseconds 100
                }
            }
        }
        finally {
            # Clean up runspace pool
            if ($runspacePool) {
                $runspacePool.Close()
                $runspacePool.Dispose()
            }
        }
    }
    else {
        # Sequential processing
        Write-Host "Processing $totalSubscriptions subscriptions sequentially..."
        
        foreach ($sub in $filteredSubscriptions) {
            $result = & $scriptBlock $sub $config $outputDir $totalSubscriptions `
                ([ref]$processedCount) ([ref]$succeededCount) ([ref]$failedCount)
            
            if ($result) {
                $subscriptionResults += $result
            }
        }
    }
    
    # Generate summary report
    $summary = @{
        Timestamp = Get-Date -Format "o"
        TotalSubscriptions = $totalSubscriptions
        Succeeded = $succeededCount
        Failed = $failedCount
        SubscriptionResults = $subscriptionResults | ForEach-Object { 
            [PSCustomObject]@{
                SubscriptionId = $_.SubscriptionId
                SubscriptionName = $_.SubscriptionName
                Status = $_.Status
                OutputFile = $_.OutputFile
                Duration = if ($_.Duration) { $_.Duration.TotalSeconds } else { $null }
                Error = $_.Error
            }
        }
    }
    
    $summaryFile = Join-Path $outputDir "assessment_summary_$(Get-Date -Format 'yyyyMMddHHmmss').json"
    $summary | ConvertTo-Json -Depth 5 | Out-File -FilePath $summaryFile -Force
    
    # Display summary
    Write-Host "`n=== Assessment Summary ===" -ForegroundColor Cyan
    Write-Host "Total Subscriptions: $totalSubscriptions"
    Write-Host "Succeeded: $succeededCount" -ForegroundColor Green
    
    if ($failedCount -gt 0) {
        Write-Host "Failed: $failedCount" -ForegroundColor Red
        $subscriptionResults | Where-Object { $_.Status -notlike 'Success*' } | ForEach-Object {
            Write-Host "  - $($_.SubscriptionName) ($($_.SubscriptionId)): $($_.Status)" -ForegroundColor Red
        }
    }
    
    Write-Host "`nSummary report saved to: $summaryFile" -ForegroundColor Cyan
    
    # Output results for pipeline
    $subscriptionResults | ForEach-Object { [PSCustomObject]$_ }

    # Get all accessible subscriptions
    Write-Host "Retrieving accessible subscriptions..."
    $allSubs = Get-AzSubscription -TenantId $config.azure.tenantId -WarningAction SilentlyContinue
    Write-Error "An error occurred: $_"
    Write-Error $_.ScriptStackTrace
    exit 1
}
finally {
    # Clean up any remaining progress bars
    Write-Progress -Activity "Completed" -Completed
    
    # Clean up any remaining runspaces
    if ($runspacePool) {
        $runspacePool.Close()
        $runspacePool.Dispose()
    }
    
    # Ensure all runspaces are disposed
    if ($runspaces) {
        foreach ($runspace in $runspaces) {
            if ($runspace.PowerShell) {
                $runspace.PowerShell.Dispose()
            }
        }
    }
}
