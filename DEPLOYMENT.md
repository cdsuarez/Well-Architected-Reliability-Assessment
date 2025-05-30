# WARA Deployment Guide

This guide provides instructions for deploying and using the Well-Architected Reliability Assessment (WARA) tool.

## Prerequisites

- PowerShell 7.0 or later
- Azure PowerShell module (Az) version 8.0.0 or later
- Required permissions in Azure:
  - Reader role at the subscription level (minimum)
  - Contributor or Owner role for resource creation if using deployment features

## Installation

### Option 1: Install from PowerShell Gallery (Recommended)

```powershell
# Install the module from PowerShell Gallery
Install-Module -Name WARA -Repository PSGallery -Force -AllowClobber -Scope CurrentUser

# Import the module
Import-Module WARA
```

### Option 2: Install from Source

1. Clone the repository:
   ```bash
   git clone https://github.com/Azure/Well-Architected-Reliability-Assessment.git
   ```

2. Navigate to the source directory:
   ```bash
   cd Well-Architected-Reliability-Assessment
   ```

3. Import the module:
   ```powershell
   Import-Module .\src\WARA.psd1 -Force
   ```

## Configuration

1. Create a configuration file (e.g., `wara-tenant-config.json`) based on the example:
   ```json
   {
       "azure": {
           "tenantId": "your-tenant-id",
           "subscriptionId": "your-subscription-id",
           "assessAllSubscriptions": false,
           "subscriptionFilter": {
               "includedSubscriptions": [],
               "excludedSubscriptions": [],
               "includedTags": {},
               "excludedTags": {}
           },
           "parallelProcessing": {
               "enabled": true,
               "maxDegreeOfParallelism": 5
           },
           "rateLimiting": {
               "delayBetweenSubscriptionsMs": 1000,
               "maxRequestsPerMinute": 30
           }
       },
       "assessment": {
           "outputDirectory": "./assessment-results"
       }
   }
   ```

## Running the Assessment

### Single Subscription Assessment

```powershell
# Run the collector
$collectorOutput = Start-WARACollector -ConfigFile .\wara-tenant-config.json

# Analyze the results
$analyzerOutput = Start-WARAAnalyzer -InputFile $collectorOutput

# Generate reports
Start-WARAReport -InputFile $analyzerOutput
```

### Multi-Subscription (Tenant) Assessment

```powershell
# Run tenant assessment
$results = .\scripts\Invoke-WARATenantAssessment.ps1 -ConfigFile .\wara-tenant-config.json

# View results
$results | Format-Table -AutoSize
```

## CI/CD Integration

### GitHub Actions

1. Add a workflow file (e.g., `.github/workflows/wara-assessment.yml`):
   ```yaml
   name: WARA Assessment
   
   on:
     workflow_dispatch:
     schedule:
       - cron: '0 0 1 * *'  # Run on the 1st of every month
   
   jobs:
     assess:
       runs-on: windows-latest
       steps:
         - uses: actions/checkout@v3
         
         - name: Install PowerShell modules
           shell: pwsh
           run: |
             Install-Module -Name Az -Force -AllowClobber -Scope CurrentUser
             Install-Module -Name Pester -Force -AllowClobber -SkipPublisherCheck -Scope CurrentUser
             Install-Module -Name PSScriptAnalyzer -Force -AllowClobber -Scope CurrentUser
         
         - name: Run WARA Assessment
           shell: pwsh
           env:
             AZURE_CREDENTIALS: ${{ secrets.AZURE_CREDENTIALS }}
           run: |
             $creds = $env:AZURE_CREDENTIALS | ConvertFrom-Json
             $securePassword = ConvertTo-SecureString $creds.clientSecret -AsPlainText -Force
             $psCred = New-Object System.Management.Automation.PSCredential($creds.clientId, $securePassword)
             
             Connect-AzAccount -ServicePrincipal -Credential $psCred -Tenant $creds.tenantId
             
             # Run the assessment
             .\scripts\Invoke-WARATenantAssessment.ps1 -ConfigFile .\wara-tenant-config.json
             
             # Upload results as artifact
             $artifactName = "wara-results-$(Get-Date -Format 'yyyyMMdd')"
             Compress-Archive -Path ".\assessment-results\*" -DestinationPath "$artifactName.zip" -Force
             
             # Upload artifact (GitHub Actions specific)
             Write-Output "artifact_name=$artifactName" >> $env:GITHUB_ENV
           
         - name: Upload artifact
           uses: actions/upload-artifact@v3
           with:
             name: ${{ env.artifact_name }}
             path: ${{ env.artifact_name }}.zip
   ```

### Azure DevOps

1. Create a new pipeline YAML file (e.g., `azure-pipelines.yml`):
   ```yaml
   trigger:
     - main
   
   pool:
     vmImage: 'windows-latest'
   
   variables:
     azureSubscription: 'your-azure-subscription'
     resourceGroupName: 'your-resource-group'
     location: 'eastus'
   
   steps:
   - task: AzurePowerShell@5
     displayName: 'Run WARA Assessment'
     inputs:
       azureSubscription: '$(azureSubscription)'
       ScriptType: 'FilePath'
       ScriptPath: '$(System.DefaultWorkingDirectory)/scripts/Invoke-WARATenantAssessment.ps1'
       ScriptArguments: '-ConfigFile $(System.DefaultWorkingDirectory)/wara-tenant-config.json'
       azurePowerShellVersion: 'LatestVersion'
       pwsh: true
   
   - task: PublishBuildArtifacts@1
     displayName: 'Publish Assessment Results'
     inputs:
       PathtoPublish: '$(System.DefaultWorkingDirectory)/assessment-results'
       ArtifactName: 'WARA-Results-$(Build.BuildId)'
       publishLocation: 'Container'
   ```

## Security Considerations

1. **Least Privilege**: Use the principle of least privilege when creating service principals for automation.
2. **Secrets Management**: Store sensitive information (like service principal credentials) in a secure secret store (Azure Key Vault, GitHub Secrets, Azure DevOps Variables).
3. **Network Security**: Ensure proper network security rules are in place when accessing resources across different networks.
4. **Data Residency**: Be aware of data residency requirements when processing and storing assessment results.

## Troubleshooting

### Common Issues

1. **Authentication Errors**:
   - Ensure the service principal has the correct permissions
   - Verify the tenant ID and subscription ID are correct
   - Check if the service principal has not expired

2. **Rate Limiting**:
   - If you encounter throttling errors, increase the `delayBetweenSubscriptionsMs` in the config
   - Reduce the `maxDegreeOfParallelism` if running into API limits

3. **Module Not Found**:
   - Ensure the module is properly installed and imported
   - Check the module path is in `$env:PSModulePath`

### Logging

Enable verbose logging for detailed troubleshooting:

```powershell
# Enable verbose logging
$VerbosePreference = 'Continue'

# Run with detailed logging
Start-WARACollector -ConfigFile .\wara-tenant-config.json -Verbose
```

## Support

For issues and feature requests, please open an issue in the [GitHub repository](https://github.com/Azure/Well-Architected-Reliability-Assessment/issues).

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
