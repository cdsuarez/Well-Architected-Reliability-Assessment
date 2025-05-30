param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('major', 'minor', 'patch', 'prerelease', '')]
    [string]$BumpType = '',
    
    [Parameter(Mandatory=$false)]
    [string]$PreReleaseId = ""
)

# Import required modules
Import-Module -Name "$PSScriptRoot/../src/modules/wara/wara.psd1" -Force -ErrorAction Stop

# Get current version from module manifest
$manifestPath = "./src/modules/wara/wara.psd1"
$manifest = Import-PowerShellDataFile -Path $manifestPath
$currentVersion = [version]$manifest.ModuleVersion

# Parse version components
$major = $currentVersion.Major
$minor = $currentVersion.Minor
$patch = $currentVersion.Build
$preRelease = $null

# If no bump type specified, try to determine from commit message
if ([string]::IsNullOrEmpty($BumpType)) {
    try {
        $commitMsg = git log -1 --pretty=%B
        
        if ($commitMsg -match '\bBREAKING[ -]CHANGE\b') {
            $BumpType = 'major'
        }
        elseif ($commitMsg -match '^feat\b') {
            $BumpType = 'minor'
        }
        else {
            $BumpType = 'patch'
        }
        
        Write-Host "Detected version bump type from commit message: $BumpType"
    }
    catch {
        Write-Warning "Could not determine version bump type from git history. Using 'patch' as default."
        $BumpType = 'patch'
    }
}

# Bump version based on type
switch ($BumpType.ToLower()) {
    'major' {
        $major++
        $minor = 0
        $patch = 0
    }
    'minor' {
        $minor++
        $patch = 0
    }
    'patch' {
        $patch++
    }
    'prerelease' {
        if ([string]::IsNullOrEmpty($PreReleaseId)) {
            $PreReleaseId = "beta"
        }
        $preRelease = "-$PreReleaseId.1"
    }
}

# Construct new version
$newVersion = if ($preRelease) {
    "$major.$minor.$patch$preRelease"
} else {
    "$major.$minor.$patch"
}

# Update module manifest
$manifestContent = Get-Content -Path $manifestPath -Raw
$manifestContent = $manifestContent -replace 
    "ModuleVersion\s*=\s*'[^']*'", 
    "ModuleVersion = '$newVersion'"

# Update changelog with new version
$changelogPath = "./CHANGELOG.md"
if (Test-Path $changelogPath) {
    $changelog = Get-Content -Path $changelogPath -Raw
    $date = Get-Date -Format "yyyy-MM-dd"
    $newChangelog = $changelog -replace 
        '(?s)(## \[Unreleased\]\s*\n)', 
        "`$1## [$newVersion] - $date`n"
    
    if ($newChangelog -ne $changelog) {
        $newChangelog | Set-Content -Path $changelogPath -NoNewline
        Write-Host "Updated CHANGELOG.md with version $newVersion"
    }
}

# Save the updated manifest
$manifestContent | Set-Content -Path $manifestPath -NoNewline

# Output the new version for use in CI/CD
Write-Host "##vso[task.setvariable variable=NEW_VERSION]$newVersion"
Write-Host "New version: $newVersion"

# Return the new version
return $newVersion
