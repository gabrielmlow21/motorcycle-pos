# Phase 0 Runbook — Stand Up the Infrastructure & Get Both Apps Live

Goal: by the end, a `git push` to `main` deploys the correct half automatically, the
React PWA loads from a live URL, and it can call the live Laravel API. **No real features
yet** — this phase is purely about proving the pipeline end to end.

Work top to bottom. Commands use Azure CLI (`az`). Run `az login` first.

> Heads-up on accuracy: Azure renames flags between CLI versions and App Service + Laravel
> has genuinely fiddly bits (document root, MySQL SSL). I've flagged both. If a command
> errors on a flag, check the authoritative doc:
> https://learn.microsoft.com/azure/app-service/configure-language-php

---

## Prerequisites

- An Azure subscription, and the Azure CLI installed (`az version`).
- A GitHub repo containing your four files (CLAUDE.md, DESIGN.md, the two workflows) plus the
  scaffolded apps in `/api` and `/web` (the two `create-project` / `create vite` commands).
- PHP + Composer locally, so you can generate the Laravel app key.

---

## Step 0 — Set shell variables (so the rest is copy-paste)

Pick globally-unique names where noted (App Service and MySQL names share a global namespace).

```bash
# --- Naming ---
RG=motorcycle-pos-rg
LOCATION=southeastasia          # Singapore — lowest latency to Malaysia for compute + DB
SWA_LOCATION=eastasia           # Static Web Apps only supports a few regions; this is the Asia one
API_NAME=motorcycle-pos-api     # must be globally unique
WEB_NAME=motorcycle-pos-web
PLAN=motorcycle-pos-plan
MYSQL_NAME=motorcycle-pos-db    # must be globally unique
KV_NAME=motopos-kv              # must be globally unique, <=24 chars
AI_NAME=motorcycle-pos-insights

# --- Database credentials (use a strong password; you'll store it as a secret) ---
DB_ADMIN=posadmin
DB_PASSWORD='ChangeMe-Strong-Passw0rd!'   # generate a real one
DB_NAME=pos
```

---

## Step 1 — Resource group

```bash
az group create --name $RG --location $LOCATION
```

Everything below goes into this group. Deleting this group later tears down *everything* in
one command — handy for a clean restart.

---

## Step 2 — MySQL Flexible Server

```bash
az mysql flexible-server create \
  --resource-group $RG \
  --name $MYSQL_NAME \
  --location $LOCATION \
  --admin-user $DB_ADMIN \
  --admin-password "$DB_PASSWORD" \
  --tier Burstable --sku-name Standard_B1ms \
  --storage-size 20 \
  --version 8.0 \
  --public-access None

# Create the database
az mysql flexible-server db create \
  --resource-group $RG --server-name $MYSQL_NAME --database-name $DB_NAME

# Allow Azure-hosted services (your App Service) to connect.
# The 0.0.0.0/0.0.0.0 special rule means "Azure services", not "the whole internet".
az mysql flexible-server firewall-rule create \
  --resource-group $RG --name $MYSQL_NAME \
  --rule-name AllowAzureServices \
  --start-ip-address 0.0.0.0 --end-ip-address 0.0.0.0
```

> ⚠️ **MySQL SSL gotcha.** Azure MySQL Flexible Server requires encrypted connections by
> default (`require_secure_transport = ON`). Laravel connects fine over SSL, but you may need
> to point it at Azure's CA certificate. Easiest path for Phase 0: download Azure's CA bundle,
> commit it to `/api`, and set `MYSQL_ATTR_SSL_CA` in your DB config. If you hit a TLS error on
> first migrate, this is why — don't disable SSL on a production DB to "fix" it.

---

## Step 3 — App Service (the Laravel API host)

```bash
# Linux plan (B1 is a cheap starter tier; scale later)
az appservice plan create \
  --resource-group $RG --name $PLAN --location $LOCATION --is-linux --sku B1

# Confirm the PHP runtime string available to you (formats change between CLI versions)
az webapp list-runtimes --os-type linux | grep -i php

# Create the web app on PHP 8.3
az webapp create \
  --resource-group $RG --plan $PLAN --name $API_NAME \
  --runtime "PHP:8.3"
```

### 3a — Fix the Laravel document root (the must-do step)

App Service's nginx serves `/home/site/wwwroot`, but Laravel's entry point is in `/public`.
nginx config resets on every restart, so the durable fix is a custom config file in your repo
plus a startup script that installs it on boot.

Create **`/api/default`** (a custom nginx config) with this content:

```nginx
server {
    listen 8080;
    listen [::]:8080;
    root /home/site/wwwroot/public;     # <-- Laravel's public dir
    index index.php index.html index.htm;

    location / {
        try_files $uri $uri/ /index.php?$args;
    }

    location ~ [^/]\.php(/|$) {
        fastcgi_split_path_info ^(.+?\.php)(|/.*)$;
        fastcgi_pass 127.0.0.1:9000;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param PATH_INFO $fastcgi_path_info;
    }
}
```

Create **`/api/startup.sh`**:

```bash
#!/bin/bash
# Install the Laravel-aware nginx config and reload
cp /home/site/wwwroot/default /etc/nginx/sites-available/default
service nginx reload

# Cache config/routes for production speed; link storage for uploads
cd /home/site/wwwroot
php artisan config:cache
php artisan route:cache
php artisan storage:link || true
```

Point App Service at the startup script:

```bash
az webapp config set \
  --resource-group $RG --name $API_NAME \
  --startup-file "/home/site/wwwroot/startup.sh"
```

### 3b — App settings (environment variables)

Generate the Laravel key locally first:

```bash
# run inside /api
php artisan key:generate --show
# copy the "base64:...." value into APP_KEY below
```

```bash
az webapp config appsettings set --resource-group $RG --name $API_NAME --settings \
  APP_ENV=production \
  APP_DEBUG=false \
  APP_KEY="base64:PASTE_YOURS_HERE" \
  DB_CONNECTION=mysql \
  DB_HOST="$MYSQL_NAME.mysql.database.azure.com" \
  DB_PORT=3306 \
  DB_DATABASE=$DB_NAME \
  DB_USERNAME=$DB_ADMIN \
  DB_PASSWORD="$DB_PASSWORD" \
  SCM_DO_BUILD_DURING_DEPLOYMENT=false
```

> `SCM_DO_BUILD_DURING_DEPLOYMENT=false` because your GitHub Actions workflow already runs
> `composer install` and ships `vendor/`. Letting Azure *also* build causes confusing
> double-builds. Pick one place to build; we chose CI.

---

## Step 4 — Static Web App (the React PWA host)

```bash
az staticwebapp create \
  --name $WEB_NAME --resource-group $RG --location $SWA_LOCATION

# Get the deployment token (this is the AZURE_STATIC_WEB_APPS_API_TOKEN GitHub secret)
az staticwebapp secrets list \
  --name $WEB_NAME --resource-group $RG \
  --query "properties.apiKey" -o tsv
```

Copy that token output — you'll paste it into GitHub in Step 7.

---

## Step 5 — Key Vault (secrets store)

```bash
az keyvault create --name $KV_NAME --resource-group $RG --location $LOCATION

# Store the DB password as a secret
az keyvault secret set --vault-name $KV_NAME --name "DbPassword" --value "$DB_PASSWORD"
```

For Phase 0 you've already put the password directly in App Service settings to keep moving.
The production-grade upgrade (do it in Phase 1 or 8): give the web app a **managed identity**,
grant it `get` on the vault, and replace the raw value with a Key Vault reference of the form
`@Microsoft.KeyVault(SecretUri=...)`. That removes the secret from app settings entirely.

---

## Step 6 — Application Insights (monitoring)

```bash
az monitor app-insights component create \
  --app $AI_NAME --location $LOCATION --resource-group $RG --application-type web

# Grab the connection string
az monitor app-insights component show \
  --app $AI_NAME --resource-group $RG --query connectionString -o tsv
```

Add it to the API as an app setting:

```bash
az webapp config appsettings set --resource-group $RG --name $API_NAME --settings \
  APPLICATIONINSIGHTS_CONNECTION_STRING="PASTE_CONNECTION_STRING"
```

> PHP auto-instrumentation is limited, so for now this mainly captures platform metrics and
> request logs. Deeper Laravel tracing comes later — for Phase 0, just having it wired is enough.

---

## Step 7 — Wire up GitHub secrets (so the workflows can fire)

Get the App Service publish profile:

```bash
az webapp deployment list-publishing-profiles \
  --resource-group $RG --name $API_NAME --xml
```

In **GitHub → repo → Settings → Secrets and variables → Actions**, add:

| Secret name | Value |
|---|---|
| `AZURE_WEBAPP_PUBLISH_PROFILE` | the full XML from the command above |
| `AZURE_STATIC_WEB_APPS_API_TOKEN` | the token from Step 4 |
| `VITE_API_URL` | `https://<API_NAME>.azurewebsites.net` |

These names match the placeholders in your two workflow files. Also update `AZURE_WEBAPP_NAME`
inside `api-deploy.yml` to your real `$API_NAME`.

---

## Step 8 — Configure CORS (so the PWA may call the API)

Handle this **in Laravel**, not at the Azure level (setting it in both places produces
duplicate headers and breaks requests). In `/api/config/cors.php`, set `allowed_origins` to
your Static Web App URL (e.g. `https://<WEB_NAME>.azurestaticapps.net`). Commit and let it deploy.

---

## Step 9 — First deploy & smoke test

```bash
git add .
git commit -m "Phase 0: infra + pipeline"
git push origin main
```

Watch both workflows run under the repo's **Actions** tab. Then check:

1. **API health** — visit `https://<API_NAME>.azurewebsites.net/up`
   (Laravel ships a built-in `/up` health route). Expect HTTP 200.
2. **Web loads** — visit your Static Web App URL; the React app renders.
3. **Cross-origin call works** — from the PWA, make one fetch to the API's `/up`. No CORS error.

Run the **first migration deliberately** (not from CI — see DESIGN.md on why money data must
never be auto-migrated):

```bash
# Open an SSH session into the running API container, then:
az webapp ssh --resource-group $RG --name $API_NAME
# inside the container:
cd /home/site/wwwroot && php artisan migrate --force
```

---

## Phase 0 is done when…

- [ ] Pushing a change under `api/**` redeploys *only* the API.
- [ ] Pushing a change under `web/**` redeploys *only* the web app.
- [ ] `https://<API_NAME>.azurewebsites.net/up` returns 200.
- [ ] The PWA loads from its live URL and can call the API without CORS errors.
- [ ] You can SSH in and run a migration against the live MySQL database.
- [ ] You can explain, in one sentence each, what every resource you created does.

That last box is the learning checkpoint — don't skip it.

---

## Cost & teardown

You're on starter tiers (B1 plan, Burstable B1ms MySQL, free Static Web Apps, minimal Key Vault
+ Insights), which keeps Phase 0 cheap — but confirm current figures on the Azure pricing
calculator, since rates change and aren't worth quoting from memory. To wipe everything and
start fresh:

```bash
az group delete --name $RG --yes --no-wait
```

---

## Known gotchas (the ones that actually cost people hours)

- **502 on first load** → the nginx document-root step (3a) didn't take. Re-check `startup.sh`
  ran and the `default` file deployed to `/home/site/wwwroot/default`.
- **MySQL TLS error on migrate** → the SSL CA issue in Step 2. Point Laravel at Azure's CA cert;
  don't disable secure transport.
- **Double CORS headers** → you set CORS in both Laravel and App Service. Keep it in Laravel only.
- **Double build / slow deploys** → `SCM_DO_BUILD_DURING_DEPLOYMENT` left on while CI also builds.
- **`PHP:8.3` runtime rejected** → run `az webapp list-runtimes --os-type linux` and use the exact
  string your CLI version reports.

---

*Authoritative reference for the App Service + PHP specifics:*
https://learn.microsoft.com/azure/app-service/configure-language-php
