<#
.SYNOPSIS
    Rotates log files by compressing old logs and removing very old ones.
    
.DESCRIPTION
    This script helps manage log files by compressing logs older than a specified number of days
    and removing compressed logs older than a specified retention period.
    
.PARAMETER LogDirectory
    The directory containing log files. Defaults to './logs'.
    
.PARAMETER FilePattern
    The pattern to match log files. Default is '*.log'.
    
.PARAMETER DaysToKeepLogs
    Number of days to keep uncompressed log files. Default is 7 days.
    
.PARAMETER DaysToKeepArchives
    Number of days to keep compressed log archives. Default is 90 days.
    
.PARAMETER CompressionLevel
    The compression level to use (Fastest, NoCompression, Optimal). Default is 'Optimal'.
    
.EXAMPLE
    .\Rotate-LogFiles.ps1 -LogDirectory "C:\WARA\logs" -DaysToKeepLogs 7 -DaysToKeepArchives 90
    
    Compresses logs older than 7 days and removes compressed logs older than 90 days.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param (
    [string]$LogDirectory = "./logs",
    [string]$FilePattern = "*.log",
    [int]$DaysToKeepLogs = 7,
    [int]$DaysToKeepArchives = 90,
    [ValidateSet('Fastest', 'NoCompression', 'Optimal')]
    [string]$CompressionLevel = 'Optimal'
)

# Ensure the log directory exists
if (-not (Test-Path -Path $LogDirectory)) {
    Write-Warning "Log directory '$LogDirectory' does not exist."
    return
}

# Create archive directory if it doesn't exist
$archiveDir = Join-Path -Path $LogDirectory -ChildPath "archives"
if (-not (Test-Path -Path $archiveDir)) {
    New-Item -ItemType Directory -Path $archiveDir -Force | Out-Null
}

# Calculate cutoff dates
$compressCutoffDate = (Get-Date).AddDays(-$DaysToKeepLogs)
$deleteCutoffDate = (Get-Date).AddDays(-$DaysToKeepArchives)

# Get log files to compress
$logFiles = Get-ChildItem -Path $LogDirectory -Filter $FilePattern -File | 
    Where-Object { $_.LastWriteTime -lt $compressCutoffDate -and $_.Extension -eq '.log' }

# Compress old log files
foreach ($file in $logFiles) {
    $zipFileName = "$($file.BaseName)_$(Get-Date -Format 'yyyyMMdd').zip"
    $zipPath = Join-Path -Path $archiveDir -ChildPath $zipFileName
    
    Write-Verbose "Compressing $($file.FullName) to $zipPath"
    
    try {
        Compress-Archive -Path $file.FullName -DestinationPath $zipPath -CompressionLevel $CompressionLevel -WhatIf:$false -Force
        
        # Remove the original log file if compression was successful
        if (Test-Path $zipPath) {
            Remove-Item -Path $file.FullName -Force -WhatIf:$false
            Write-Host "Compressed and removed: $($file.Name)" -ForegroundColor Green
        }
    }
    catch {
        Write-Error "Failed to compress $($file.FullName): $_"
    }
}

# Clean up old archive files
$oldArchives = Get-ChildItem -Path $archiveDir -Filter "*.zip" -File | 
    Where-Object { $_.LastWriteTime -lt $deleteCutoffDate }

foreach ($archive in $oldArchives) {
    Write-Host "Removing old archive: $($archive.Name)" -ForegroundColor Yellow
    Remove-Item -Path $archive.FullName -Force -WhatIf:$false
}

Write-Host "Log rotation completed. $($logFiles.Count) log files processed, $($oldArchives.Count) old archives removed." -ForegroundColor Cyan
