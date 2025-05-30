# Contributing to Well-Architected Reliability Assessment (WARA)

Thank you for your interest in contributing to the Well-Architected Reliability Assessment (WARA) project! We welcome contributions from the community to help improve this tool.

## Code of Conduct

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/). For more information, see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.

## Getting Started

### Prerequisites

- [PowerShell 7.4 or later](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell)
- [Git](https://git-scm.com/)
- [Pester](https://pester.dev/) (for running tests)
- [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer) (for code linting)

### Setting Up the Development Environment

1. Fork the repository to your GitHub account
2. Clone your forked repository locally:
   ```bash
   git clone https://github.com/your-username/Well-Architected-Reliability-Assessment.git
   cd Well-Architected-Reliability-Assessment
   ```
3. Install the required modules:
   ```powershell
   Install-Module -Name Pester -Force -SkipPublisherCheck
   Install-Module -Name PSScriptAnalyzer -Force -SkipPublisherCheck
   ```

## Contribution Workflow

1. **Create a feature branch** from the `main` branch:
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make your changes** following the coding standards below

3. **Run tests** to ensure your changes don't break existing functionality:
   ```powershell
   .\scripts\run-tests.ps1
   ```

4. **Lint your code** using PSScriptAnalyzer:
   ```powershell
   Invoke-ScriptAnalyzer -Path .\src -Recurse -Severity @('Error', 'Warning') -ReportSummary
   ```

5. **Commit your changes** with a descriptive commit message:
   ```bash
   git commit -m "Add your descriptive commit message here"
   ```

6. **Push your changes** to your fork:
   ```bash
   git push origin feature/your-feature-name
   ```

7. **Create a Pull Request** from your fork to the `main` branch of the upstream repository

## Coding Standards

### PowerShell Coding Standards

- Follow the [PowerShell Best Practices and Style Guide](https://poshcode.gitbook.io/powershell-practice-and-style/)
- Use `PascalCase` for functions, classes, and public variables
- Use `camelCase` for parameters and local variables
- Use `UPPER_SNAKE_CASE` for constants
- Use `Verb-Noun` naming convention for functions
- Include comment-based help for all functions
- Use `[CmdletBinding()]` for advanced functions
- Implement `ShouldProcess` for functions that make changes
- Use `SupportsShouldProcess` for functions that support `-WhatIf` and `-Confirm`

### Documentation

- Update relevant documentation when making functional changes
- Include examples in your function help
- Document all parameters and their types
- Add or update README.md when adding new features

### Testing

- Write Pester tests for new functionality
- Aim for high code coverage (minimum 80%)
- Test edge cases and error conditions
- Update existing tests when modifying functionality

## Pull Request Guidelines

- Keep pull requests focused on a single feature or bug fix
- Ensure all tests pass before submitting a PR
- Update documentation as part of the PR
- Include a clear description of the changes and any related issues
- Reference any related issues in your PR description (e.g., "Fixes #123")

## Reporting Issues

When reporting issues, please include:

1. A clear, descriptive title
2. Steps to reproduce the issue
3. Expected behavior
4. Actual behavior
5. Environment details (PowerShell version, OS version, etc.)
6. Any error messages or logs

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
