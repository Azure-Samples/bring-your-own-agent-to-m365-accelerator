import base64
import subprocess
import uuid


def main():
    # Get tenant ID from Azure CLI (equivalent to: az account show --query tenantId --output tsv)
    try:
        result = subprocess.run(['az', 'account', 'show', '--query', 'tenantId', '--output', 'tsv'],
                                capture_output=True, text=True, check=True)
        tenant_id = result.stdout.strip()
        print(f"Converting GUID: {tenant_id}")
    except subprocess.CalledProcessError as e:
        print(f"Error getting tenant ID: {e}")
        return

    # Create UUID object from string
    guid = uuid.UUID(tenant_id)

    # Convert UUID to byte array (using bytes_le for little-endian like C#)
    byte_array = guid.bytes_le

    # Encode byte array to Base64 URL-safe string
    base64_url = base64.b64encode(byte_array).decode('utf-8') \
        .replace('+', '-') \
        .replace('/', '_') \
        .rstrip('=')

    print(f"Base64URL encoded: {base64_url}")

    # Export with azd env set
    try:
        subprocess.run(
            f'azd env set AZURE_TENANT_ID_BASE64_ENCODED={base64_url}', shell=True, check=True)
        print("Successfully set AZURE_TENANT_ID_BASE64_ENCODED environment variable")
    except subprocess.CalledProcessError as e:
        print(f"Error setting environment variable: {e}")


if __name__ == "__main__":
    main()
