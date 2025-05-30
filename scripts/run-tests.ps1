param()

# Ensure test results directory exists
$testResultsDir = "./testResults"
if (-not (Test-Path $testResultsDir)) {
    New-Item -ItemType Directory -Path $testResultsDir | Out-Null
}

# Install dependencies
Write-Host "Installing required modules..."
Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted
Install-Module -Name Pester -Force -SkipPublisherCheck -AllowClobber
Install-Module -Name PSScriptAnalyzer -Force -AllowClobber
Install-Module -Name Az -Force -AllowClobber

# Import required modules
Import-Module Pester -MinimumVersion 5.0.0
Import-Module PSScriptAnalyzer

# Run Pester tests
Write-Host "Running Pester tests..."
$testResultsFile = "$testResultsDir/test-results.xml"
$testResults = Invoke-Pester -Path ./src/tests -OutputFile $testResultsFile -OutputFormat NUnitXml -PassThru

# Output test results
Write-Host "Test Results:"
Write-Host "  Total: $($testResults.TotalCount)"
Write-Host "  Passed: $($testResults.PassedCount)"
Write-Host "  Failed: $($testResults.FailedCount)"

# Run PSScriptAnalyzer
Write-Host "Running PSScriptAnalyzer..."
$analysisResults = Invoke-ScriptAnalyzer -Path ./src -Recurse -Severity @('Error', 'Warning')

if ($analysisResults) {
    Write-Host "PSScriptAnalyzer found issues:"
    $analysisResults | Format-Table -AutoSize
    $analysisResults | Format-List * -Force
    
    # Fail the build if there are errors
    $errors = $analysisResults | Where-Object { $_.Severity -eq 'Error' }
    if ($errors) {
        Write-Error "PSScriptAnalyzer found $($errors.Count) errors"
        exit 1
    }
}

# Exit with non-zero code if tests failed
if ($testResults.FailedCount -gt 0) {
    Write-Error "Tests failed: $($testResults.FailedCount) failed, $($testResults.PassedCount) passed"
    exit 1
}

Write-Host "All tests passed successfully!"
