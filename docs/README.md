# WARA Documentation

Welcome to the Well-Architected Reliability Assessment (WARA) documentation. This directory contains detailed documentation about the WARA tool's architecture, usage, and best practices.

## Documentation Structure

- [Architecture](./architecture.md) - High-level architecture and component diagrams
- [Glossary](./glossary.md) - Definitions of key terms and concepts

## Getting Started

### Prerequisites

Before using WARA, ensure you have:

- An Azure subscription with appropriate permissions
- PowerShell 7.4 or later
- Required PowerShell modules (see main README for details)

### Quick Start

1. Install the WARA module
2. Run the collector to gather data:
   ```powershell
   Start-WARACollector -OutputPath "./assessment_data.json"
   ```
3. Analyze the collected data:
   ```powershell
   Start-WARAAnalyzer -InputPath "./assessment_data.json" -OutputPath "./action_plan.xlsx"
   ```
4. Generate a report:
   ```powershell
   Start-WARAReport -InputPath "./action_plan.xlsx" -OutputPath "./report.html"
   ```

## Documentation Conventions

- **Bold** text indicates important concepts or UI elements
- `Code` formatting is used for commands, parameters, and file paths
- > Note: Provides additional information or context
- ⚠️ Warning: Highlights important considerations or potential issues

## Contributing to Documentation

We welcome contributions to improve our documentation. Please follow these guidelines:

1. Use clear, concise language
2. Follow the existing documentation style
3. Include relevant examples
4. Update the table of contents when adding new sections
5. Use Mermaid.js for diagrams when possible

## Documentation Style Guide

### Headers
- Use title case for headers
- Include only one H1 (#) per document
- Be descriptive with header text

### Code Examples
- Include the language after the opening triple backticks
- Keep examples focused and relevant
- Include comments to explain complex operations

### Links
- Use descriptive link text (not "click here")
- Link to related documentation when relevant
- Keep links up-to-date

## Feedback

We value your feedback! If you find any issues with the documentation or have suggestions for improvement, please [open an issue](https://github.com/Azure/Well-Architected-Reliability-Assessment/issues) on our GitHub repository.
