# Regenerate the architecture diagrams

The architecture diagrams are authored as Mermaid sources in `docs/mermaids/*.mmd` and rendered to PNG (in `docs/images/`) with [`@mermaid-js/mermaid-cli`](https://github.com/mermaid-js/mermaid-cli).

### Install the CLI

```bash
# Mermaid CLI (provides the `mmdc` command)
npm install -g @mermaid-js/mermaid-cli
```

The CLI renders through headless Chrome (Puppeteer). Inside the DevContainer, install the required system libraries once:

```bash
sudo apt-get install -y \
  libatk1.0-0 libatk-bridge2.0-0 libcups2 libxkbcommon0 libxcomposite1 \
  libxdamage1 libxrandr2 libgbm1 libpango-1.0-0 libcairo2 libasound2 \
  libnss3 libnspr4 libxss1 libxtst6 libgtk-3-0
```

### Render the diagrams

Run the helper script from the **root** of the project. It regenerates every PNG in `docs/` from its `.mmd` source:

```bash
./scripts/render_diagrams.sh
```

> The script inlines the SVG icons as base64 data URIs into a temporary copy before rendering (the `.mmd` sources keep relative `./docs/icons/...` paths so they still render natively on GitHub) and runs Chrome with `--no-sandbox` for container compatibility.
>
