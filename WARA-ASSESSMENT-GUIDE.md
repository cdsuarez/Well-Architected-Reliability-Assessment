# Azure Well-Architected Reliability Assessment (WARA) Guide

This guide explains how to use the WARA assessment tool with the configuration file approach.

## Prerequisites

### 1. Azure DevOps Organization and Project

- An Azure DevOps organization and project to host the pipeline

### 2. Azure Subscription Access

- A service principal with the following Azure RBAC roles at the subscription level:
  - **Reader** - For reading resource configurations and properties
  - **Resource Graph Reader** - Required for running Azure Resource Graph queries
- These roles provide the minimum permissions needed for the assessment

### 3. Local Development (if running locally)

- PowerShell 7.4 or later
- Azure PowerShell module (`Az`)
- `Az.ResourceGraph` module (for local execution)

## Configuration File

The WARA assessment is configured using a JSON file (`wara-tenant-config.json`). This file contains all the necessary settings for the assessment.

### Configuration File Structure

```json
{
  "azure": {
    "subscriptionId": "00000000-0000-0000-0000-000000000000",
    "subscriptionName": "Your Subscription Name",
    "tenantId": "00000000-0000-0000-0000-000000000000",
    "resourceGroups": [
      "resource-group-1",
      "resource-group-2"
    ]
  },
  "assessment": {
    "customerName": "Contoso",
    "workloadName": "Production",
    "environment": "Production",
    "regions": ["eastus", "westus"],
    "tags": {
      "Environment": "Production",
      "Department": "IT"
    },
    "outputDirectory": "wara-results",
    "includeSpecializedWorkloads": true,
    "specializedWorkloads": [
      "SAP",
      "AVD"
    ]
  },
  "publishing": {
    "publishToWiki": false,
    "wikiPath": "wiki/",
    "publishToStorage": false,
    "storageAccountName": "",
    "storageContainer": "wara-reports"
  },
  "notifications": {
    "sendEmail": false,
    "emailRecipients": ["admin@contoso.com"],
    "slackWebhookUrl": ""
  }
}
```

### Configuration Options

#### Azure Settings

- `tenantId`: (Required) Azure AD tenant ID
- `subscriptionId`: (Optional) The Azure subscription ID to assess (required if `assessAllSubscriptions` is false)
- `subscriptionName`: (Optional) Display name of the subscription (for reference)
- `assessAllSubscriptions`: (Optional, default: `false`) If `true`, the assessment will run against all accessible subscriptions in the tenant
- `subscriptionFilter`: (Optional) Filter criteria for subscriptions when `assessAllSubscriptions` is `true`
  - `includedSubscriptions`: Array of subscription IDs or names to include
  - `excludedSubscriptions`: Array of subscription IDs or names to exclude
  - `includedTags`: Object of tag names and values to include (subscriptions must have all specified tags)
  - `excludedTags`: Object of tag names and values to exclude (subscriptions with any of these tags will be excluded)
- `resourceGroups`: (Optional) Specific resource groups to include in the assessment

#### Assessment Settings

- `customerName`: Name of the customer or organization
- `workloadName`: Name of the workload being assessed
- `environment`: Environment type (e.g., Production, Staging, Development)
- `regions`: (Optional) Azure regions to include in the assessment
- `tags`: (Optional) Resource tags to filter the assessment
- `includeSpecializedWorkloads`: Whether to include specialized workload assessments
- `specializedWorkloads`: List of specialized workloads to assess (e.g., SAP, AVD)

#### Publishing Settings

- `publishToWiki`: Whether to publish results to a wiki
- `wikiPath`: Path to the wiki repository
- `publishToStorage`: Whether to publish results to Azure Storage
- `storageAccountName`: Name of the storage account
- `storageContainer`: Name of the container for reports

#### Notification Settings

- `sendEmail`: Whether to send email notifications
- `emailRecipients`: List of email recipients
- `slackWebhookUrl`: Slack webhook URL for notifications

## Running the WARA Assessment

### Prerequisites

1. Clone the WARA repository
2. Install required PowerShell modules:

   ```powershell
   Install-Module -Name Az.Accounts, Az.Resources, Az.Storage, ImportExcel, Pester -Force -AllowClobber
   ```

3. Update the `wara-tenant-config.json` file with your settings

### Running Locally

#### Single Subscription Assessment

To assess a single subscription, use the following steps:

1. Open a PowerShell session
2. Navigate to the repository root
3. Run the following command:

   ```powershell
   .\scripts\Invoke-WARATenantAssessment.ps1 -ConfigFile .\wara-tenant-config.json
   ```

#### Tenant-Wide Assessment

You can run tenant-wide assessments either locally or through a CI/CD pipeline.

**Local Execution**

1. Update your configuration file to set `assessAllSubscriptions` to `true`:

```json
{
  "azure": {
    "tenantId": "your-tenant-id",
    "assessAllSubscriptions": true,
    "subscriptionFilter": {
      "includedSubscriptions": [],
      "excludedSubscriptions": ["00000000-0000-0000-0000-000000000001"],
      "includedTags": {
        "Environment": "Production"
      },
      "excludedTags": {
        "ExcludeFromAssessment": "true"
      }
    }
  },
  "assessment": {
    "outputDirectory": "./assessment-results"
  }
}
```

2. Run the assessment locally:

```powershell
.\scripts\Invoke-WARATenantAssessment.ps1 -ConfigFile .\wara-tenant-config.json
```

**Pipeline Integration**

The WARA pipeline (`azure-pipelines.wara.yml`) supports both single subscription and tenant-wide assessments. The pipeline automatically detects the assessment scope based on the configuration file.

### Azure DevOps Setup

#### 1. Create a Service Connection

1. Go to Project Settings > Service connections > New service connection
2. Select "Azure Resource Manager" > "Service principal (automatic)"
3. Configure with appropriate Azure AD permissions (Reader role at minimum)
4. Name it `wara-azure-connection` or update the `azureSubscription` variable

#### 2. Configure the Pipeline

The pipeline is pre-configured to handle both scenarios:

- **Single subscription**: Set `assessmentScope: 'single'` in variables
- **Tenant-wide**: Set `assessmentScope: 'tenant'` and provide `tenantId`

#### 3. Example Pipeline Trigger

```yaml
# Example pipeline trigger for tenant-wide assessment
resources:
  pipelines:
  - pipeline: wara-pipeline
    source: 'WARA-Assessment-Pipeline'  # Name of your pipeline
    trigger:
      branches:
        include:
        - main

variables:
  - name: assessmentScope
    value: 'tenant'  # or 'single' for single subscription
  - name: tenantId
    value: 'your-tenant-id'  # Required for tenant-wide
  - name: configFile
    value: 'wara-tenant-config.json'  # Your config file
```

### GitHub Actions Setup

#### 1. Create Azure Credentials Secret
   ```bash
   az ad sp create-for-rbac --name "WARA-GitHub-Actions" \
     --role reader \
     --scopes /subscriptions/your-subscription-id \
     --sdk-auth | ConvertTo-Json | Out-File -Encoding utf8 -FilePath ./azure-credentials.json
   ```
   Add the output as a GitHub secret named `AZURE_CREDENTIALS`

#### 2. Example Workflow

```yaml
name: WARA Assessment

on:
  workflow_dispatch:
    inputs:
      scope:
        description: 'Assessment scope (single or tenant)'
        required: true
        default: 'single'
  schedule:
    - cron: '0 0 * * 0'  # Weekly on Sunday at midnight

jobs:
  assess:
    runs-on: windows-latest
    
    steps:
    - name: Checkout code
      uses: actions/checkout@v3
      
    - name: Login to Azure
      uses: azure/login@v1
      with:
        creds: ${{ secrets.AZURE_CREDENTIALS }}
        
    - name: Run WARA Assessment
      shell: pwsh
      run: |
        if ('${{ github.event.inputs.scope }}' -eq 'tenant') {
          .\scripts\Invoke-WARATenantAssessment.ps1 -ConfigFile .\wara-tenant-config.json
        } else {
          Import-Module .\src\modules\wara -Force
          Start-WARACollector -ConfigFile .\wara-tenant-config.json
          $jsonFile = Get-ChildItem -Path . -Filter 'WARA_*.json' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
          Start-WARAAnalyzer -JSONFile $jsonFile.FullName
        }
        
    - name: Upload assessment results
      uses: actions/upload-artifact@v3
      with:
        name: wara-results
        path: |
          ./assessment-results/*.json
          ./assessment-results/*.xlsx
          ./assessment-results/*.pptx
        retention-days: 7

### Configuration File Examples

#### 1. Tenant-Wide Configuration (`wara-tenant-config.json`)
```json
{
  "azure": {
    "subscriptionId": "00000000-0000-0000-0000-000000000000",
    "tenantId": "00000000-0000-0000-0000-000000000000"
  },
  "assessment": {
    "outputDirectory": "./assessment-results"
  }
}
```

2. **Tenant-Wide** (`wara-tenant-config.json`):
```json
{
  "azure": {
    "tenantId": "00000000-0000-0000-0000-000000000000",
    "assessAllSubscriptions": true,
    "subscriptionFilter": {
      "includedSubscriptions": [],
      "excludedSubscriptions": ["00000000-0000-0000-0000-000000000001"],
      "includedTags": {
        "Environment": "Production"
      }
    }
  },
  "assessment": {
    "outputDirectory": "./assessment-results"
  }
}
```

#### Subscription Filtering Options

The `subscriptionFilter` object supports the following properties:

- `includedSubscriptions`: Array of subscription IDs or names to include
- `excludedSubscriptions`: Array of subscription IDs or names to exclude
- `includedTags`: Object of tag names and values that must all be present on a subscription to be included
- `excludedTags`: Object of tag names and values that will exclude a subscription if any match

Example with all filter options:

```json
"subscriptionFilter": {
  "includedSubscriptions": ["sub-id-1", "sub-name-2"],
  "excludedSubscriptions": ["00000000-0000-0000-0000-000000000003"],
  "includedTags": {
    "Environment": "Production",
    "Department": "IT"
  },
  "excludedTags": {
    "ExcludeFromAssessment": "true",
    "Status": "Decommissioning"
  }
}
```

### Example: Filtering Subscriptions by Tags

To assess all subscriptions with specific tags:

```json
{
  "azure": {
    "tenantId": "00000000-0000-0000-0000-000000000000",
    "assessAllSubscriptions": true,
    "subscriptionFilter": {
      "includedTags": {
        "Environment": "Production",
        "Department": "IT"
      },
      "excludedSubscriptions": ["00000000-0000-0000-0000-000000000001"]
    }
  }
}
```

### Running in Azure DevOps

1. Create a service connection in Azure DevOps:
   - Go to Project Settings > Service connections
   - Create a new service connection of type "Azure Resource Manager"
   - Select "Service principal (automatic)" and follow the wizard

2. Update the pipeline variables in `azure-pipelines.wara.yml`:
   - `azureSubscription`: The name of your Azure DevOps service connection
   - `configFile`: Path to your configuration file (default: `wara-tenant-config.json`)

3. Commit and push your changes to the repository

4. Run the pipeline:
   - Go to Pipelines in Azure DevOps
   - Select the WARA pipeline
   - Click "Run pipeline"
   - Select the branch and click "Run"

## Output

The assessment generates the following outputs:

1. **Collector Output**: JSON file containing collected data
2. **Analyzer Output**: Excel file with detailed analysis
3. **Reports**:
   - HTML summary report
   - CSV files for each worksheet in the analysis
   - Detailed HTML reports for key areas

## Customizing the Assessment

### Adding Custom Checks

1. Create a new PowerShell script in the `src/checks` directory
2. Implement your custom check following the pattern of existing checks
3. Update the `wara.psd1` file to include your new check

### Modifying Report Templates

1. Locate the report templates in the `src/reports` directory
2. Modify the HTML/CSS as needed
3. Update the `Export-WARAReport` function to use your custom template

## Troubleshooting

### Common Issues

1. **Authentication Failures**:
   - Verify the service principal has the correct permissions
   - Check that the tenant ID is correct
   - If using `assessAllSubscriptions`, ensure the service principal has access to list subscriptions
   - For cross-tenant access, ensure the service principal has the necessary permissions in all relevant tenants

2. **Missing Data**:
   - Verify the service principal has read access to all resources
   - Check the resource group and region filters in the configuration

3. **Report Generation Failures**:
   - Ensure the ImportExcel module is installed
   - Check for special characters in the output paths

## Support

For issues and feature requests, please open an issue in the repository.
