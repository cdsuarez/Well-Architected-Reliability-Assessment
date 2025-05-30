<#
.SYNOPSIS
    Cleans up old assessment results from the output directory.
    
.DESCRIPTION
    This script removes assessment results older than the specified number of days,
    helping to manage disk space by cleaning up old files.
    
.PARAMETER OutputDirectory
    The directory containing assessment results. Defaults to './assessment-results'.
    
.PARAMETER DaysToKeep
    Number of days of assessment results to keep. Files older than this will be deleted.
    Default is 30 days.
    
.PARAMETER WhatIf
    Shows what would happen if the cmdlet runs. The cmdlet is not run.
    
.EXAMPLE
    .\Clear-OldAssessmentResults.ps1 -OutputDirectory "C:\WARA\results" -DaysToKeep 14
    
    Removes assessment result files older than 14 days from the specified directory.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param (
    [string]$OutputDirectory = "./assessment-results",
    [int]$DaysToKeep = 30
)

# Ensure the directory exists
if (-not (Test-Path -Path $OutputDirectory)) {
    Write-Warning "Output directory '$OutputDirectory' does not exist."
    return
}

# Calculate the cutoff date
$cutoffDate = (Get-Date).AddDays(-$DaysToKeep)

# Get all files in the directory and subdirectories
$files = Get-ChildItem -Path $OutputDirectory -Recurse -File | 
    Where-Object { $_.LastWriteTime -lt $cutoffDate }

if ($files.Count -eq 0) {
    Write-Host "No files found older than $DaysToKeep days in '$OutputDirectory'."
    return
}

# Display what will be deleted
Write-Host "Found $($files.Count) files older than $($cutoffDate.ToString('yyyy-MM-dd')) that will be deleted:"
$files | ForEach-Object { Write-Host "  - $($_.FullName) (Last modified: $($_.LastWriteTime))" }

# Confirm before deleting
if ($PSCmdlet.ShouldProcess("$($files.Count) files", "Remove files older than $($cutoffDate.ToString('yyyy-MM-dd'))")) {
    $files | Remove-Item -Force -WhatIf:$false
    Write-Host "Successfully removed $($files.Count) files older than $DaysToKeep days." -ForegroundColor Green
}
