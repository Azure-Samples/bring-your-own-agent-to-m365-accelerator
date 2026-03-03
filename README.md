# M365 Copilot Pro Code Approach

## Disclaimer

This sample scripts are not supported under any Microsoft standard support program or service. The sample script is provided AS IS without warranty of any kind. Microsoft further disclaims all implied warranties including, without limitation, any implied warranties of merchantability or of fitness for a particular purpose. The entire risk arising out of the use or performance of the sample scripts and documentation remains with you. In no event shall Microsoft, its authors, or anyone else involved in the creation, production, or delivery of the scripts be liable for any damages whatsoever (including, without limitation, damages for loss of business profits, business interruption, loss of business information, or other pecuniary loss) arising out of the use of or inability to use the sample scripts or documentation, even if Microsoft has been advised of the possibility of such damages.

This project is an M365 Agent Application built with Python and the Microsoft Agent Framework, deployable to Azure using the Azure Developer CLI (`azd`).

## Prerequisites

- [Azure Developer CLI (azd)](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd)
- [Python 3.13+](https://www.python.org/downloads/)
- [uv](https://docs.astral.sh/uv/)
- [Teams App Test Tool](https://learn.microsoft.com/microsoftteams/platform/toolkit/debug-your-teams-app-test-tool)

## Azure Authentication

Before provisioning or deploying, authenticate with Azure:

```bash
az login --use-device-code
azd auth login --use-device-code
```

## Azure Provisioning & Deployment

### Provision infrastructure

```bash
azd provision
```

This will provision all the required Azure resources defined in the `infra/` folder.

### Deploy the application

```bash
azd deploy
```

This will package and deploy the Python application to the provisioned Azure App Service.

> You can also run `azd up` to provision and deploy in a single command.

## Local Development

### 1. Install dependencies

From the project root, navigate to the Python app folder and sync dependencies:

```bash
cd src/m365_agent_app
uv sync
```

### 2. Activate the virtual environment

```bash
source .venv/bin/activate
```

### 3. Run the application

```bash
uv run python main.py
```

### 4. Test with Teams App Test Tool

Launch the **Teams App Test Tool** to interact with your agent locally:

```bash
teamsapptester
```

This opens a local test harness that simulates the Teams environment, allowing you to send messages to your agent and debug its responses.
