# WARA Maintenance Runbooks

This directory contains PowerShell scripts designed to help maintain and manage the Well-Architected Reliability Assessment (WARA) tool. These runbooks automate common maintenance tasks and ensure the tool runs smoothly in production environments.

## Available Runbooks

### 1. Clear-OldAssessmentResults.ps1

**Purpose**: Cleans up old assessment results to manage disk space.

**Features**:
- Removes assessment result files older than a specified number of days
- Supports dry-run mode to preview files that would be deleted
- Handles large directories efficiently

**Example**:
```powershell
# Remove results older than 30 days (default)
.\Clear-OldAssessmentResults.ps1 -OutputDirectory "C:\WARA\results"

# Preview what would be deleted
.\Clear-OldAssessmentResults.ps1 -OutputDirectory "C:\WARA\results" -WhatIf
```

### 2. Rotate-LogFiles.ps1

**Purpose**: Manages log files by compressing old logs and removing very old archives.

**Features**:
- Compresses log files older than a specified number of days
- Removes compressed archives older than the retention period
- Supports different compression levels
- Creates a structured archive directory

**Example**:
```powershell
# Rotate logs (compress older than 7 days, keep archives for 90 days)
.\Rotate-LogFiles.ps1 -LogDirectory "C:\WARA\logs" -DaysToKeepLogs 7 -DaysToKeepArchives 90
```

### 3. Update-ModuleDependencies.ps1

**Purpose**: Updates PowerShell module dependencies to their latest versions.

**Features**:
- Updates all required WARA modules
- Supports both CurrentUser and AllUsers scopes
- Validates module versions against minimum requirements
- Provides detailed update summaries

**Example**:
```powershell
# Update modules for current user (requires admin for AllUsers)
.\Update-ModuleDependencies.ps1 -Scope CurrentUser -Verbose
```

### 4. Test-ConfigurationFile.ps1

**Purpose**: Validates WARA configuration files for syntax and required settings.

**Features**:
- Validates JSON syntax
- Checks for required fields and data types
- Validates values against allowed ranges/enums
- Supports recursive directory scanning
- Provides detailed error reporting

**Example**:
```powershell
# Validate all JSON files in a directory
.\Test-ConfigurationFile.ps1 -ConfigPath "C:\WARA\config" -Recurse -Detailed
```

### 5. Backup-AssessmentData.ps1

**Purpose**: Creates backups of assessment data with optional encryption.

**Features**:
- Full and incremental backup support
- Optional AES-256 encryption
- Configurable retention policy
- Compression with multiple levels
- Detailed progress reporting

**Example**:
```powershell
# Create an encrypted backup with 30-day retention
.\Backup-AssessmentData.ps1 -SourceDirectory "C:\WARA\results" -BackupDirectory "D:\Backups" -Encrypt -RetentionDays 30
```

## Scheduling Runbooks

These runbooks can be scheduled using Windows Task Scheduler or as cron jobs on Linux. For example, to schedule a weekly log rotation:

### Windows Task Scheduler

```powershell
$action = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -File "C:\path\to\Rotate-LogFiles.ps1" -LogDirectory "C:\WARA\logs"'
$trigger = New-ScheduledTaskTrigger -Weekly -At "3:00AM"
Register-ScheduledTask -Action $action -Trigger $trigger -TaskName "WARA Log Rotation" -Description "Rotates WARA log files weekly"
```

### Linux (cron)

```bash
# Add to crontab (crontab -e)
0 3 * * 0 /usr/bin/pwsh /path/to/Rotate-LogFiles.ps1 -LogDirectory "/var/log/wara"
```

## Security Considerations

- Always run scripts with the minimum required permissions
- Store encryption passwords securely (e.g., Azure Key Vault, AWS Secrets Manager)
- Review script contents before execution, especially when downloaded
- Consider signing scripts for production use

## Contributing

When adding new runbooks:
1. Follow the existing style and documentation format
2. Include comprehensive parameter validation
3. Add support for -WhatIf and -Verbose parameters
4. Document all parameters and provide examples
5. Test thoroughly before submitting a pull request
