"""
Post-provision hook: placeholder for future setup tasks.

The search token is now acquired via Bot Framework Token Service
(search_access_token OAuth connection), no client secret needed.
"""

def main():
    print("Postprovision: no additional setup required.")
    print("  Search token: acquired via Bot Framework Token Service (search_access_token)")
    print("  No client secret needed.")


if __name__ == "__main__":
    main()
