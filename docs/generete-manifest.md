# Prod — tout depuis azd env
./scripts/build_manifest.sh --teams-app-id e34ac10b-... --short-name "Alfred"

# Dev — valeurs différentes, zip différent
./scripts/build_manifest.sh \
  --teams-app-id e34ac10b-...dde7 \
  --bot-id "$(azd env get-value DEV_BOT_ID)" \
  --domain "$(azd env get-value DEV_BOT_DOMAIN)" \
  --short-name "Alfred Dev" \
  --full-name "Alfred (dev)" \
  --zip appPackage.dev.zip