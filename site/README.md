# tokenholic.app — landing page

Single static page (`index.html` + `icon.png`) for [tokenholic.app](https://tokenholic.app).

## Deploy

Pushes to `main` that touch `site/**` trigger
[`.github/workflows/deploy-site.yml`](../.github/workflows/deploy-site.yml),
which publishes this folder to the **`tokenholic`** Cloudflare Pages project via
`wrangler pages deploy`.

Required repo secrets:

| Secret | Value |
|--------|-------|
| `CLOUDFLARE_API_TOKEN` | API token with **Account › Cloudflare Pages › Edit** |
| `CLOUDFLARE_ACCOUNT_ID` | `18082a2c0c6a78838623151213cca993` |

The custom domain `tokenholic.app` is attached to the Pages project in the
Cloudflare dashboard (Pages → tokenholic → Custom domains).

## Local preview

```sh
cd site && python3 -m http.server 8099   # http://localhost:8099
```
