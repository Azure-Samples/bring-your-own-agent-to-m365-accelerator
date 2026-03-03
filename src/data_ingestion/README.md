# Data Ingestion – Azure AI Search

Python script that indexes **Excel (.xlsx)**, **Word (.docx)** and **PDF (.pdf)** files into an Azure AI Search index.

## Prerequisites

- Python 3.10+
- A provisioned **Azure AI Search** service
- Files to index placed in the `sample/` folder

## Installation

```bash
cd src/data_ingestion
uv sync
```

## Configuration

1. Copy the example file and fill in the values:

```bash
cp .env.example .env
```

2. At a minimum, set `AZURE_SEARCH_ENDPOINT`.  
   - If you use **DefaultAzureCredential** (recommended), leave `AZURE_SEARCH_API_KEY` empty.  
   - Otherwise, provide the admin key of your AI Search service.

| Variable | Description | Required |
|---|---|---|
| `AZURE_SEARCH_ENDPOINT` | AI Search service URL | Yes |
| `AZURE_SEARCH_INDEX_NAME` | Index name (default: `documents-index`) | No |
| `AZURE_SEARCH_API_KEY` | Admin key (if not using managed identity) | No |

## Usage

```bash
uv run python ingest.py
```

The script will:

1. Create (or update) the `documents-index` index in Azure AI Search
2. Scan the `sample/` folder and extract text from each supported file
3. Upload the documents to the index

## Index schema

| Field | Type | Description |
|---|---|---|
| `id` | String (key) | Unique hash of the file name |
| `content` | String (searchable) | Extracted text content |
| `file_name` | String (filterable) | Source file name |
| `file_type` | String (filterable, facet) | Extension (pdf, docx, xlsx) |
| `title` | String (searchable) | File name without extension |
