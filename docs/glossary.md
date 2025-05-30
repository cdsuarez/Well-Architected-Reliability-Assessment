# WARA Glossary

This document defines key terms and concepts used throughout the Well-Architected Reliability Assessment (WARA) tool and documentation.

## Core Concepts

### Assessment
A comprehensive evaluation of an Azure workload against the reliability pillar of the Microsoft Azure Well-Architected Framework.

### Workload
A resource or collection of resources that provide end-to-end functionality to one or multiple clients (humans or systems).

### Reliability
The ability of a system to recover from failures and continue to function.

### Resilience
The ability of a system to gracefully handle and recover from failures.

## Components

### WARA Collector
A PowerShell module that collects data about Azure resources for assessment.

### WARA Analyzer
A component that processes collected data and applies assessment rules to identify reliability issues.

### WARA Reporter
A component that generates reports from the assessment results.

## Data Types

### Resource Metrics
Quantitative measurements about the state of Azure resources.

### Assessment Rules
Conditions used to evaluate the reliability of Azure resources.

### Findings
Issues or recommendations identified during the assessment process.

## Workflow Terms

### Data Collection
Phase where the WARA Collector gathers information about Azure resources.

### Analysis
Phase where the collected data is evaluated against reliability best practices.

### Reporting
Phase where assessment results are formatted and presented to the user.

## Azure-Specific Terms

### Resource Group
A container that holds related resources for an Azure solution.

### Subscription
A logical container used to provision resources in Azure.

### Tenant
A dedicated and trusted instance of Azure Active Directory (Azure AD).

## Assessment Results

### Critical Finding
A severe issue that requires immediate attention.

### Warning
A potential issue that should be addressed.

### Information
Informational note about the assessment.

## Security Terms

### Service Principal
A security identity used by applications, services, and automation tools to access specific Azure resources.

### Managed Identity
An Azure AD identity that provides an automatically managed identity in Azure AD for applications to use when connecting to resources that support Azure AD authentication.

## Networking Terms

### Virtual Network (VNet)
The fundamental building block for private networks in Azure.

### Network Security Group (NSG)
A networking filter (firewall) containing a list of security rules that allow or deny network traffic to Azure resources.

## Storage Terms

### Geo-Redundant Storage (GRS)
Copies your data synchronously three times within a single physical location in the primary region using LRS, then copies it asynchronously to a single physical location in the secondary region.

### Zone-Redundant Storage (ZRS)
Replicates your data synchronously across three Azure availability zones in the primary region.

## Monitoring Terms

### Azure Monitor
A comprehensive solution for collecting, analyzing, and acting on telemetry from your cloud and on-premises environments.

### Log Analytics
A tool in the Azure portal used to edit and run log queries against data in the Azure Monitor Logs store.

## Compliance Terms

### Azure Policy
A service in Azure that enables you to create, assign, and manage policies to enforce rules and effects for your resources.

### Azure Blueprints
A service for orchestrating the deployment of various resource templates and other artifacts, such as role assignments and policy assignments.

## Reliability Patterns

### Circuit Breaker
A design pattern used to detect failures and encapsulate the logic of preventing a failure from constantly recurring during maintenance, temporary external system failure, or unexpected system difficulties.

### Retry Pattern
Enables an application to handle temporary failures when it tries to connect to a service or network resource by transparently retrying a failed operation.
