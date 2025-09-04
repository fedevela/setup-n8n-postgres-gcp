## GCP n8n Cloud Run + Postgres Setup

This repository contains a small set of guided shell scripts to create a minimal, secure n8n deployment on Google Cloud Platform (GCP) using Cloud Run and Cloud SQL (Postgres).

High level: the scripts automate common setup tasks so you can create a "blank" n8n instance backed by a Postgres database with secrets stored in Secret Manager and the n8n Docker image hosted in Artifact Registry.

This repo is intentionally lightweight: each script performs one focused task and the `main.sh` orchestrator runs them in sequence.

Key features
- Creates required GCP APIs and networking pieces for Cloud Run + Cloud SQL private IP.
- Creates a Cloud SQL (Postgres) instance and database/user (non-destructive by default).
- Stores secrets (database password and n8n encryption key) in Secret Manager.
- Pulls the official n8n Docker image and pushes it into Artifact Registry via Cloud Build.
- Deploys n8n to Cloud Run with Cloud SQL connectivity and secrets injected.

Why this repo exists
This provides a reproducible, opinionated baseline for running n8n on GCP with secure defaults (private IP Cloud SQL, Secret Manager, minimum permissions) so you can get started quickly without manual console steps.

Prerequisites
- A GCP account with billing enabled and the Google Cloud SDK (`gcloud`) installed and authenticated.
- You have permission to enable APIs, create Cloud SQL instances, Artifact Registry repos, and deploy Cloud Run services.
- `openssl` is required on the machine running some scripts (for generating random passwords/keys).

Important security notes
- The scripts save a local `.env` file (created with restrictive permissions 600) to persist values used across steps. The `.env` file is ignored by `.gitignore` to avoid accidental commits.
- Secrets are stored in Secret Manager in your GCP project. The scripts grant the Cloud Run service account access to those secrets during deployment.
- Review IAM bindings before running in production. The scripts grant the Compute default service account `roles/cloudsql.client` and `roles/secretmanager.secretAccessor` for the deployed service; you may want to use a dedicated service account instead.

Quick start
1. Clone this repo and cd into it.
2. Authenticate with gcloud and select or create a project:

```bash
# Example: set a default project (or set GCLOUD_PROJECT/GCP_PROJECT env var)
gcloud auth login
gcloud config set project YOUR_PROJECT_ID
```

3. Run the orchestrator. This will run the scripts in order and persist values in a local `.env` file.

```bash
bash main.sh
```

### DB_ACTION options
- ignore (default): perform non-destructive setup; existing instance, database, and user are preserved.
- drop_db: delete only the database and user, then recreate them on the existing Cloud SQL instance.
- destroy_sql_instance: delete the entire Cloud SQL instance (and all its databases), then recreate it.

Pass the desired action when running `main.sh`:
```bash
# Non-destructive (default)
bash main.sh

# Drop only database and user
bash main.sh DB_ACTION=drop_db

# Destroy the entire SQL instance
bash main.sh DB_ACTION=destroy_sql_instance
```

Files and purpose
- `main.sh` - orchestrator; runs the numbered scripts in sequence and accepts simple env overrides like `DB_ACTION=value`.
- `env_utils.sh` - small helper that loads/saves a local `.env` file and exposes `save_var` which writes and exports values.
- `0_setup.sh` - enables required GCP services, sets project and region defaults, and ensures Serverless VPC connector (for private Cloud SQL access) exists.
- `1_setup_psql.sh` - creates a Cloud SQL Postgres instance, database, and user (creates a random password when creating a new instance).
- `2_setup_secrets.sh` - stores the DB user password and an n8n encryption key in Secret Manager (creates or adds versions).
- `3_setup_docker_n8n.sh` - pulls the official n8n image and uses Cloud Build to push it to Artifact Registry.
- `4_deploy_cloudrun_n8n.sh` - deploys the n8n Docker image to Cloud Run, configures Cloud SQL access, injects secrets, and sets basic auth for the admin user.
- `5_display_logs.sh` - convenience script to fetch recent Cloud Run logs for the service.
- `.gitignore` - ignores local `.env` and ephemeral artifact directory `n8n-cloudrun/`.

How to publish this repo to GitHub (public)
1. Create a new repo on GitHub (don't initialize with a README or .gitignore if you want to push this repo as-is).
2. Locally, create a git repo, commit files, and push:

```bash
git init
git add .
git commit -m "Initial: GCP n8n Cloud Run + Postgres setup scripts"
git branch -M main
git remote add origin git@github.com:YOUR_USERNAME/YOUR_REPO.git
git push -u origin main
```

Replace `YOUR_USERNAME` and `YOUR_REPO` with your GitHub details. Use HTTPS remote URL if you prefer.

Next steps & suggestions
- Consider converting the wide-ranging IAM grants to use a dedicated service account for Cloud Run and grant least-privilege roles.
- Add automated checks (shellcheck) and tests in CI before publishing to ensure scripts remain healthy.

License
Add a LICENSE file if you want this repo to be published with an explicit license. No license is included in this repo by default.

If anything in these scripts should be explained in more detail, open an issue or edit the README to match your project's policies.
