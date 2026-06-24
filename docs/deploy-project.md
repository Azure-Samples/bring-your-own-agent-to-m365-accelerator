# Azure Provisioning & Deployment

## Prerequisites

### Option 1: Use the DevContainer (recommended)

1. Install [Visual Studio Code](https://code.visualstudio.com/download) and the [Remote - Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers).

2. Open the project in VS Code and click "Reopen in Container" when prompted. This will set up a development environment with all dependencies installed.

### Option 2: Install dependencies locally

- [Azure Developer CLI (azd)](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd)
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)
- [Python 3.13+](https://www.python.org/downloads/)
- [uv](https://docs.astral.sh/uv/)
- An Azure subscription with access to Microsoft Foundry, AI Search, and API Management
- A Microsoft 365 tenant with Teams/Copilot access

## Azure Authentication

Before provisioning or deploying, authenticate with Azure:

```bash
az login --use-device-code
azd auth login --use-device-code
```

## Provision and deploy

At the root of the project, run the following commands to provision and deploy the application to Azure:

```bash
azd provision
```

This provisions all Azure resources (App Service, Bot Service, API Management, AI Search, Microsoft Foundry, app registrations, OAuth connections) and deploys the Python application.

```bash
azd deploy
```