<#
.SYNOPSIS
    Backs up WARA assessment data to a specified location, optionally compressing the results.
    
.DESCRIPTION
    This script creates backups of assessment data, including configuration files,
    results, and logs. It supports both full and incremental backups, with options
    for compression and encryption.
    
.PARAMETER SourceDirectory
    The directory containing the assessment data to back up. Defaults to './assessment-results'.
    
.PARAMETER BackupDirectory
    The directory where backups will be stored. Defaults to './backups'.
    
.PARAMETER BackupName
    The base name for the backup file. Defaults to 'WARA-Backup'.
    
.PARAMETER RetentionDays
    Number of days to keep backup files. Older backups will be deleted. Set to 0 to keep all backups.
    Default is 90 days.
    
.PARAMETER CompressionLevel
    The compression level to use (NoCompression, Fastest, Optimal, SmallestSize).
    Default is 'Optimal'.
    
.PARAMETER Encrypt
    If specified, encrypts the backup using the provided password.
    
.PARAMETER Password
    The password to use for encryption. If not provided and -Encrypt is specified,
    you will be prompted to enter a password.
    
.PARAMETER Incremental
    If specified, performs an incremental backup (only new or changed files).
    
.PARAMETER WhatIf
    Shows what would happen if the cmdlet runs. The cmdlet is not run.
    
.EXAMPLE
    .\Backup-AssessmentData.ps1 -SourceDirectory ".\results" -BackupDirectory ".\backups" -RetentionDays 30
    
    Backs up the contents of the 'results' directory to 'backups', keeping backups for 30 days.
    
.EXAMPLE
    .\Backup-AssessmentData.ps1 -Encrypt -Incremental -Verbose
    
    Performs an incremental backup of the default directory, encrypting the backup with a password prompt.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param (
    [string]$SourceDirectory = "./assessment-results",
    [string]$BackupDirectory = "./backups",
    [string]$BackupName = "WARA-Backup",
    [int]$RetentionDays = 90,
    [ValidateSet('NoCompression', 'Fastest', 'Optimal', 'SmallestSize')]
    [string]$CompressionLevel = 'Optimal',
    [switch]$Encrypt,
    [securestring]$Password,
    [switch]$Incremental
)

# Ensure source directory exists
if (-not (Test-Path -Path $SourceDirectory -PathType Container)) {
    Write-Error "Source directory does not exist: $SourceDirectory"
    exit 1
}

# Create backup directory if it doesn't exist
if (-not (Test-Path -Path $BackupDirectory)) {
    try {
        New-Item -ItemType Directory -Path $BackupDirectory -Force | Out-Null
        Write-Verbose "Created backup directory: $BackupDirectory"
    }
    catch {
        Write-Error "Failed to create backup directory '$BackupDirectory': $_"
        exit 1
    }
}

# Get timestamp for backup file
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupFileName = "${BackupName}_${timestamp}.zip"
$backupPath = Join-Path -Path $BackupDirectory -ChildPath $backupFileName

# Check for existing files in source directory
$sourceItems = Get-ChildItem -Path $SourceDirectory -Recurse -File
if ($sourceItems.Count -eq 0) {
    Write-Warning "No files found in source directory: $SourceDirectory"
    exit 0
}

# For incremental backup, find files modified since last backup
if ($Incremental) {
    $lastBackup = Get-ChildItem -Path $BackupDirectory -Filter "${BackupName}_*.zip" | 
        Sort-Object LastWriteTime -Descending | 
        Select-Object -First 1
    
    if ($lastBackup) {
        Write-Host "Performing incremental backup since last backup at $($lastBackup.LastWriteTime)" -ForegroundColor Cyan
        $sourceItems = $sourceItems | Where-Object { $_.LastWriteTime -gt $lastBackup.LastWriteTime }
        
        if ($sourceItems.Count -eq 0) {
            Write-Host "No files have been modified since the last backup. No backup needed." -ForegroundColor Green
            exit 0
        }
    }
    else {
        Write-Host "No previous backup found. Performing full backup." -ForegroundColor Yellow
    }
}

# Prompt for password if encrypting and no password provided
if ($Encrypt -and -not $Password) {
    $Password = Read-Host -AsSecureString -Prompt "Enter password for encryption"
    $confirmPassword = Read-Host -AsSecureString -Prompt "Confirm password"
    
    # Compare secure strings
    $password1 = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
    )
    $password2 = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($confirmPassword)
    )
    
    if ($password1 -ne $password2) {
        Write-Error "Passwords do not match."
        exit 1
    }
    
    # Clear the plaintext passwords from memory
    $password1 = $null
    $password2 = $null
    [GC]::Collect()
}

# Create backup
$compressionLevelMap = @{
    'NoCompression' = [System.IO.Compression.CompressionLevel]::NoCompression
    'Fastest' = [System.IO.Compression.CompressionLevel]::Fastest
    'Optimal' = [System.IO.Compression.CompressionLevel]::Optimal
    'SmallestSize' = [System.IO.Compression.CompressionLevel]::SmallestSize
}

$compressionLevelValue = $compressionLevelMap[$CompressionLevel]

try {
    # Create a temporary directory for the backup
    $tempDir = Join-Path -Path $env:TEMP -ChildPath ([System.IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Path $tempDir | Out-Null
    
    # Copy files to temporary directory
    $fileCount = 0
    $totalSize = 0
    
    foreach ($item in $sourceItems) {
        $relativePath = $item.FullName.Substring($SourceDirectory.Length).TrimStart('\', '/')
        $destination = Join-Path -Path $tempDir -ChildPath $relativePath
        
        # Create directory structure
        $destinationDir = [System.IO.Path]::GetDirectoryName($destination)
        if (-not (Test-Path -Path $destinationDir)) {
            New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
        }
        
        # Copy the file
        Copy-Item -Path $item.FullName -Destination $destination -Force
        $fileCount++
        $totalSize += $item.Length
        
        Write-Progress -Activity "Preparing files for backup" -Status "$fileCount files processed" -PercentComplete (($fileCount / $sourceItems.Count) * 100)
    }
    
    # Create the backup
    Write-Host "Creating backup archive: $backupPath" -ForegroundColor Cyan
    
    if ($PSCmdlet.ShouldProcess($backupPath, "Create backup archive")) {
        Add-Type -Assembly "System.IO.Compression.FileSystem"
        
        # Create the zip file
        [System.IO.Compression.ZipFile]::CreateFromDirectory(
            $tempDir,
            $backupPath,
            $compressionLevelValue,
            $false  # includeBaseDirectory
        )
        
        # Encrypt the zip file if requested
        if ($Encrypt) {
            $encryptedPath = $backupPath + ".encrypted"
            
            # Convert secure string to byte array
            $key = [System.Text.Encoding]::UTF8.GetBytes(
                [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
                )
            )
            
            # Use AES encryption
            $aes = New-Object System.Security.Cryptography.AesCryptoServiceProvider
            $aes.Key = (New-Object System.Security.Cryptography.SHA256Managed).ComputeHash($key)[0..31]
            $aes.IV = (1..16 | ForEach-Object { [byte]$_ })
            
            $encryptor = $aes.CreateEncryptor()
            
            $inFile = [System.IO.File]::OpenRead($backupPath)
            $outFile = [System.IO.File]::Create($encryptedPath)
            
            # Write the IV at the beginning of the file
            $outFile.Write($aes.IV, 0, $aes.IV.Length)
            
            # Create crypto stream
            $cryptoStream = New-Object System.Security.Cryptography.CryptoStream(
                $outFile,
                $encryptor,
                [System.Security.Cryptography.CryptoStreamMode]::Write
            )
            
            # Copy and encrypt the data
            $inFile.CopyTo($cryptoStream)
            
            # Clean up
            $cryptoStream.FlushFinalBlock()
            $cryptoStream.Dispose()
            $inFile.Dispose()
            $outFile.Dispose()
            $aes.Dispose()
            
            # Remove the original zip and rename the encrypted file
            Remove-Item -Path $backupPath -Force
            Rename-Item -Path $encryptedPath -NewName (Split-Path -Leaf $backupPath) -Force
            
            Write-Host "Backup encrypted successfully." -ForegroundColor Green
        }
        
        $backupSize = (Get-Item $backupPath).Length
        Write-Host "Backup created successfully: $backupPath" -ForegroundColor Green
        Write-Host "  Files: $fileCount"
        Write-Host "  Size: $([math]::Round($backupSize / 1MB, 2)) MB"
    }
}
catch {
    Write-Error "Backup failed: $_"
    exit 1
}
finally {
    # Clean up temporary directory
    if (Test-Path -Path $tempDir) {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Clean up old backups if retention is enabled
if ($RetentionDays -gt 0) {
    $cutoffDate = (Get-Date).AddDays(-$RetentionDays)
    $oldBackups = Get-ChildItem -Path $BackupDirectory -Filter "${BackupName}_*" -File |
        Where-Object { $_.LastWriteTime -lt $cutoffDate }
    
    if ($oldBackups.Count -gt 0) {
        Write-Host "Removing $($oldBackups.Count) backups older than $RetentionDays days..." -ForegroundColor Yellow
        
        foreach ($backup in $oldBackups) {
            if ($PSCmdlet.ShouldProcess($backup.FullName, "Remove old backup")) {
                Remove-Item -Path $backup.FullName -Force -ErrorAction SilentlyContinue
                Write-Verbose "Removed old backup: $($backup.Name)"
            }
        }
    }
}

Write-Host "Backup process completed successfully." -ForegroundColor Green
