# WARA Architecture

## High-Level Architecture

```mermaid
flowchart TD
    A[User] -->|Runs| B[Start-WARACollector]
    B -->|Collects Data| C[Azure Resources]
    B -->|Generates| D[Assessment Data JSON]
    D -->|Input for| E[Start-WARAAnalyzer]
    E -->|Processes Data| F[Assessment Rules]
    F -->|Generates| G[Action Plan Excel]
    G -->|Input for| H[Start-WARAReport]
    H -->|Generates| I[HTML/PDF Report]
    
    subgraph Azure Environment
    C
    end
    
    subgraph WARA Workflow
    B
    D
    E
    F
    G
    H
    I
    end
```

## Data Flow

```mermaid
sequenceDiagram
    participant User
    participant Collector[WARA Collector]
    participant Azure[Azure Resources]
    participant Analyzer[WARA Analyzer]
    participant Reporter[WARA Reporter]
    
    User->>+Collector: Start-WARACollector
    Collector->>+Azure: Query Resources
    Azure-->>-Collector: Resource Data
    Collector-->>-User: Assessment Data (JSON)
    
    User->>+Analyzer: Start-WARAAnalyzer
    Analyzer->>Analyzer: Process Data
    Analyzer->>Analyzer: Apply Rules
    Analyzer-->>-User: Action Plan (Excel)
    
    User->>+Reporter: Start-WARAReport
    Reporter->>Reporter: Generate Report
    Reporter-->>-User: HTML/PDF Report
```

## Component Relationships

```mermaid
erDiagram
    USER ||--o{ ASSESSMENT : creates
    ASSESSMENT ||--|{ RESOURCE : contains
    ASSESSMENT ||--|{ RECOMMENDATION : generates
    RESOURCE ||--|{ METRIC : has
    RECOMMENDATION ||--|{ RESOURCE : applies_to
    
    USER {
        string UserId
        string Name
        string Email
    }
    
    ASSESSMENT {
        string AssessmentId
        string Timestamp
        string SubscriptionId
    }
    
    RESOURCE {
        string ResourceId
        string Type
        string Name
    }
    
    METRIC {
        string MetricId
        string Name
        string Value
    }
    
    RECOMMENDATION {
        string RecommendationId
        string Severity
        string Description
    }
```

## Assessment Process Flow

```mermaid
stateDiagram-v2
    [*] --> Initialization
    Initialization --> Authentication
    Authentication --> DataCollection
    DataCollection --> DataProcessing
    DataProcessing --> RuleEvaluation
    RuleEvaluation --> ReportGeneration
    ReportGeneration --> [*]
    
    state DataCollection {
        [*] --> CollectResources
        CollectResources --> CollectMetrics
        CollectMetrics --> [*]
    }
    
    state RuleEvaluation {
        [*] --> ApplyRules
        ApplyRules --> GenerateFindings
        GenerateFindings --> [*]
    }
```

## Azure Resource Collection

```mermaid
classDiagram
    class WaraCollector {
        +string TenantId
        +string[] SubscriptionIds
        +string[] ResourceTypes
        +CollectResources()
        +ExportToJson()
    }
    
    class AzureResource {
        +string Id
        +string Name
        +string Type
        +string Location
        +object Properties
        +GetMetrics()
    }
    
    class WaraAnalyzer {
        +string[] Rules
        +ProcessData()
        +GenerateReport()
    }
    
    WaraCollector --> "0..*" AzureResource : collects
    WaraAnalyzer --> "1..*" AzureResource : analyzes
```

## Deployment Options

```mermaid
graph TD
    A[Deployment Options] --> B[Local Machine]
    A --> C[Azure DevOps Pipeline]
    A --> D[GitHub Actions]
    A --> E[Azure Container Instance]
    
    B --> |Run interactively| F[PowerShell]
    C --> |CI/CD| G[YAML Pipeline]
    D --> |CI/CD| H[GitHub Workflow]
    E --> |Container| I[Docker]
    
    F --> J[Assessment Results]
    G --> J
    H --> J
    I --> J
```

## Legend

- **Solid arrows** indicate direct data flow
- **Dashed arrows** indicate optional or conditional flow
- **Rectangles** represent processes or components
- **Ovals** represent data stores or outputs
- **Diamonds** represent decision points

For more detailed diagrams or specific aspects of the architecture, please refer to the respective documentation sections.
