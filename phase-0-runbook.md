# Phase 0 Runbook — Stand Up the Infrastructure & Get Both Apps Live

Goal: by the end, a `git push` to `main` deploys the correct half automatically, the
React PWA loads from a live URL, and it can call the live Laravel API. **No real features
yet** — this phase is purely about proving the pipeline end to end.

Everything here is done through the Azure portal at https://portal.azure.com. No Azure CLI
required. Work top to bottom.

> **On portal accuracy:** Azure moves blades and renames labels between releases, more often
> than it changes the underlying settings. So this runbook names the **setting** you're looking
> for as well as where it lives today. If a blade has moved, search the setting name in the
> portal's own search bar rather than hunting through menus. The authoritative doc for the
> App Service + PHP specifics is:
> https://learn.microsoft.com/azure/app-service/configure-language-php

---

## Prerequisites

- An Azure subscription (the portal's free tier is enough to start).
- A GitHub repo containing this repo's docs plus the scaffolded apps in `/api` and `/web`.
- PHP + Composer locally, so you can generate the Laravel app key.

---

## Step 0 — Decide your names up front

App Service and MySQL names live in a **global** namespace, so yours must be unique across all
of Azure. Write your choices down here before you start clicking — you'll retype them a lot.

| What | Suggested value | Notes |
|---|---|---|
| Resource group | `motorcycle-pos-rg` | Holds everything; deleting it tears down all of Phase 0 |
| Region | **Southeast Asia** (Singapore) | Lowest latency to Malaysia for compute + database |
| Static Web Apps region | **East Asia** | Static Web Apps only offers a few regions; this is the Asian one |
| API app name | `motorcycle-pos-api` | Must be globally unique → becomes `<name>.azurewebsites.net` |
| Web app name | `motorcycle-pos-web` | |
| App Service plan | `motorcycle-pos-plan` | |
| MySQL server | `motorcycle-pos-db` | Must be globally unique |
| Key Vault | `motopos-kv` | Must be globally unique, max 24 characters |
| App Insights | `motorcycle-pos-insights` | |
| DB admin user | `posadmin` | |
| DB name | `pos` | |
| DB password | *generate a strong one* | You'll store it in Key Vault in Step 5 |

---

## Step 1 — Resource group

Portal → search **Resource groups** → **Create**.

- Subscription: yours
- Resource group: `motorcycle-pos-rg`
- Region: **Southeast Asia**

**Review + create** → **Create**.

Every resource below goes into this group. That's the point of it: one container you can delete
later to wipe the whole experiment in a single action.

---

## Step 2 — MySQL Flexible Server

Portal → search **Azure Database for MySQL flexible servers** → **Create** → choose
**Flexible server**.

**Basics tab:**
- Resource group: `motorcycle-pos-rg`
- Server name: `motorcycle-pos-db`
- Region: **Southeast Asia**
- MySQL version: **8.0**
- Workload type: **For development or hobby projects** — this preselects the cheap tier
- Compute + storage → **Configure server**: confirm it reads **Burstable, Standard_B1ms**,
  storage **20 GiB**. ⚠️ If the wizard defaulted you to General Purpose, change it here —
  that's the single biggest cost mistake available on this page.
- Authentication method: **MySQL authentication only**
- Admin username: `posadmin`, and your generated password

**Networking tab:**
- Connectivity method: **Public access (allowed IP addresses)**
- Tick **Allow public access from any Azure service within Azure to this server**. This is what
  lets your App Service reach the database. It is *not* "open to the whole internet" — it admits
  Azure-hosted callers only.
- Also tick **Add current client IP address** so you can connect from your laptop while setting up.

**Review + create** → **Create**. Provisioning takes several minutes.

**Then create the database itself:** open the server → **Settings → Databases** → **Add**.
Name it `pos`.

> ⚠️ **MySQL SSL gotcha.** Azure MySQL Flexible Server requires encrypted connections by default
> (`require_secure_transport = ON`). Laravel connects fine over SSL, but you may need to point it
> at Azure's CA certificate. Easiest path for Phase 0: download Azure's CA bundle (the server's
> **Networking** blade has a download link), commit it to `/api`, and set `MYSQL_ATTR_SSL_CA` in
> your database config. If you hit a TLS error on your first migration, this is why — do not
> disable secure transport on a production database to "fix" it.

---

## Step 3 — App Service (the Laravel API host)

Portal → search **App Services** → **Create** → **Web App**.

**Basics tab:**
- Resource group: `motorcycle-pos-rg`
- Name: `motorcycle-pos-api`
- Publish: **Code**
- Runtime stack: **PHP 8.3** (or the newest 8.x offered)
- Operating System: **Linux**
- Region: **Southeast Asia**
- Pricing plan: create a new plan named `motorcycle-pos-plan` and click **Change size** to pick
  **Basic B1**. ⚠️ The wizard often preselects a Premium tier — change it.

**Deployment tab:** leave GitHub Actions **disabled**. You're writing your own path-filtered
workflow rather than letting Azure generate one.

**Review + create** → **Create**.

### 3a — Fix the Laravel document root (the must-do step)

App Service's nginx serves `/home/site/wwwroot`, but Laravel's entry point is in `/public`.
The nginx config resets on every restart, so the durable fix is a config file committed to your
repo plus a startup script that installs it on boot.

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

Now point App Service at that script.

App Service → **Settings → Configuration** → **General settings** tab → **Startup Command**:

```
/home/site/wwwroot/startup.sh
```

**Save**, then **Continue** when it warns about restarting.

> Miss this step and you get a 502 on first load. It is the most commonly skipped setting in this
> entire runbook, because nothing on the create wizard hints that it exists.

### 3b — Turn on basic auth publishing (portal-specific gotcha)

Newer App Service instances ship with SCM basic authentication **disabled**, which makes
publish-profile deployment from GitHub Actions fail with a 403 that doesn't explain itself.

App Service → **Settings → Configuration** → **General settings** tab → set
**SCM Basic Auth Publishing Credentials** to **On** → **Save**.

*(The more secure long-term option is deploying via a federated credential / managed identity
instead of a publish profile. That's a good Phase 8 hardening task; for Phase 0, basic auth keeps
you moving.)*

### 3c — App settings (environment variables)

Generate the Laravel key locally first:

```bash
# run inside /api
php artisan key:generate --show
# copy the "base64:...." value
```

App Service → **Settings → Environment variables** → **App settings** tab. *(On older portal
versions this is Configuration → Application settings.)* Add each of these with **+ Add**:

| Name | Value |
|---|---|
| `APP_ENV` | `production` |
| `APP_DEBUG` | `false` |
| `APP_KEY` | the `base64:...` value you just generated |
| `DB_CONNECTION` | `mysql` |
| `DB_HOST` | `motorcycle-pos-db.mysql.database.azure.com` |
| `DB_PORT` | `3306` |
| `DB_DATABASE` | `pos` |
| `DB_USERNAME` | `posadmin` |
| `DB_PASSWORD` | your database password |
| `SCM_DO_BUILD_DURING_DEPLOYMENT` | `false` |

**Apply** → **Confirm**.

> `SCM_DO_BUILD_DURING_DEPLOYMENT=false` because your GitHub Actions workflow already runs
> `composer install` and ships `vendor/`. Letting Azure *also* build causes confusing
> double-builds. Pick one place to build; we chose CI.

---

## Step 4 — Static Web App (the React PWA host)

Portal → search **Static Web Apps** → **Create**.

**Basics tab:**
- Resource group: `motorcycle-pos-rg`
- Name: `motorcycle-pos-web`
- Plan type: **Free**
- Region: **East Asia**
- Deployment source: **Other**

> ⚠️ **Why "Other" and not GitHub.** If you pick GitHub here, the portal asks for repo access and
> then **commits a generated workflow file into your repository** on your behalf. That workflow
> has no path filtering, so every backend-only change would rebuild and redeploy the frontend —
> exactly the thing this project's CI design is meant to avoid. Choosing **Other** gives you a
> deployment token to use from a workflow you control.

**Review + create** → **Create**.

**Then get the deployment token:** open the Static Web App → **Overview** → **Manage deployment
token** → copy the value. You'll paste it into GitHub in Step 7.

---

## Step 5 — Key Vault (secrets store)

Portal → search **Key vaults** → **Create**.

- Resource group: `motorcycle-pos-rg`
- Name: `motopos-kv`
- Region: **Southeast Asia**
- Pricing tier: **Standard**
- Permission model (Access configuration tab): **Azure role-based access control**

**Review + create** → **Create**.

> ⚠️ **RBAC gotcha.** With the RBAC permission model, *creating* the vault does not give you
> permission to read or write secrets in it — not even as the subscription owner. If "Generate/
> Import" greys out or you get "the operation is not permitted", go to the vault →
> **Access control (IAM)** → **Add role assignment** → role **Key Vault Secrets Officer** →
> assign to your own user. Role assignments can take a minute or two to take effect.

**Store the database password:** vault → **Objects → Secrets** → **Generate/Import** →
Name `DbPassword`, Value = your database password → **Create**.

For Phase 0 you've already put the password directly in App Service settings to keep moving.
The production-grade upgrade (do it in Phase 1 or 8): give the web app a **managed identity**,
grant it the **Key Vault Secrets User** role on the vault, and replace the raw value in app
settings with a Key Vault reference of the form `@Microsoft.KeyVault(SecretUri=...)`. That removes
the secret from app settings entirely.

---

## Step 6 — Application Insights (monitoring)

Portal → search **Application Insights** → **Create**.

- Resource group: `motorcycle-pos-rg`
- Name: `motorcycle-pos-insights`
- Region: **Southeast Asia**
- Log Analytics workspace: let it create a default one

**Review + create** → **Create**.

Open the resource → **Overview** → copy the **Connection String**.

Add it to the API: App Service → **Settings → Environment variables** → **App settings** →
**+ Add**:

| Name | Value |
|---|---|
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | the connection string you copied |

**Apply** → **Confirm**.

> PHP auto-instrumentation is limited, so for now this mainly captures platform metrics and
> request logs. Deeper Laravel tracing comes later — for Phase 0, just having it wired is enough.

---

## Step 7 — Wire up GitHub secrets (so the workflows can fire)

**Get the App Service publish profile:** App Service → **Overview** → **Download publish profile**
(in the top command bar; it may be tucked under the **…** overflow menu). Open the downloaded
`.PublishSettings` file in a text editor and copy its entire contents — it's XML.

*(If the download button is missing or the deploy later fails with 403, revisit Step 3b — SCM
basic auth must be On.)*

Then in **GitHub → your repo → Settings → Secrets and variables → Actions → New repository
secret**, add three:

| Secret name | Value |
|---|---|
| `AZURE_WEBAPP_PUBLISH_PROFILE` | the full XML from the publish profile file |
| `AZURE_STATIC_WEB_APPS_API_TOKEN` | the deployment token from Step 4 |
| `VITE_API_URL` | `https://motorcycle-pos-api.azurewebsites.net` |

These names match the placeholders in your two workflow files. Also make sure `AZURE_WEBAPP_NAME`
inside `api-deploy.yml` matches your real API app name.

---

## Step 8 — Configure CORS (so the PWA may call the API)

Handle this **in Laravel**, not in the portal. App Service has its own CORS blade, and setting it
in both places produces duplicate `Access-Control-Allow-Origin` headers, which browsers reject
outright — a confusing failure, because each config looks correct on its own.

In `/api/config/cors.php`, set `allowed_origins` to your Static Web App URL (find it on the
Static Web App's **Overview** blade — it looks like
`https://<random-name>.<region>.azurestaticapps.net`). Commit and let it deploy.

---

## Step 9 — First deploy & smoke test

```bash
git add .
git commit -m "Phase 0: infra + pipeline"
git push origin main
```

Watch both workflows run under the repo's **Actions** tab. Then check:

1. **API health** — visit `https://motorcycle-pos-api.azurewebsites.net/up`
   (Laravel ships a built-in `/up` health route). Expect HTTP 200.
2. **Web loads** — visit your Static Web App URL; the React app renders.
3. **Cross-origin call works** — from the PWA, make one fetch to the API's `/up`. No CORS error.

Run the **first migration deliberately** (not from CI — see DESIGN.md on why money data must
never be auto-migrated). App Service → **Development Tools → SSH** → **Go**. That opens a shell
in the running container, in the browser. Then:

```bash
cd /home/site/wwwroot && php artisan migrate --force
```

---

## Phase 0 is done when…

- [ ] Pushing a change under `api/**` redeploys *only* the API.
- [ ] Pushing a change under `web/**` redeploys *only* the web app.
- [ ] `https://motorcycle-pos-api.azurewebsites.net/up` returns 200.
- [ ] The PWA loads from its live URL and can call the API without CORS errors.
- [ ] You can open the SSH console and run a migration against the live MySQL database.
- [ ] You can explain, in one sentence each, what every resource you created does.

That last box is the checkpoint that makes the rest of this project make sense — don't skip it.

---

## Cost & teardown

You're on starter tiers (B1 plan, Burstable B1ms MySQL, free Static Web Apps, minimal Key Vault
and Application Insights), which keeps Phase 0 cheap — but confirm current figures on the Azure
pricing calculator, since rates change and aren't worth quoting from memory. The **Cost
Management + Billing** blade shows actual spend once resources have run for a day.

To wipe everything and start fresh: portal → **Resource groups** → `motorcycle-pos-rg` →
**Delete resource group**. It makes you type the group name to confirm. This deletes every
resource inside it, permanently, including the database and its backups.

> Two caveats worth knowing before you rely on this. Key Vault has **soft delete** on by default,
> so a deleted vault lingers for 90 days and its name stays reserved — if you recreate Phase 0
> with the same vault name, either purge it (**Key vaults → Manage deleted vaults**) or pick a new
> name. Deleting the resource group also does *not* remove the workflow files or secrets in your
> GitHub repo; those are yours to clean up separately.

---

## Known gotchas (the ones that actually cost people hours)

- **502 on first load** → the nginx document-root step (3a) didn't take. Check the Startup Command
  is set, and that `default` and `startup.sh` actually deployed to `/home/site/wwwroot/`. The SSH
  console is the fastest way to confirm what's really on disk.
- **403 when GitHub Actions deploys the API** → SCM basic auth is off. See Step 3b.
- **MySQL TLS error on migrate** → the SSL CA issue in Step 2. Point Laravel at Azure's CA cert;
  don't disable secure transport.
- **Can't add a Key Vault secret you just created the vault for** → RBAC role assignment missing.
  See Step 5.
- **Double CORS headers** → CORS set in both Laravel and the App Service CORS blade. Keep it in
  Laravel only.
- **Double build / slow deploys** → `SCM_DO_BUILD_DURING_DEPLOYMENT` left on while CI also builds.
- **An extra workflow file you didn't write** → the Static Web Apps create wizard was pointed at
  GitHub instead of "Other". Delete the generated workflow and use your own.
- **Surprise bill** → a create wizard's default tier slipped through. Check the App Service plan is
  B1 and the MySQL compute is Burstable B1ms.

---

*Authoritative reference for the App Service + PHP specifics:*
https://learn.microsoft.com/azure/app-service/configure-language-php
</content>
</invoke>
