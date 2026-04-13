---
title: Urban Tree Explorer
sdk: docker
app_port: 7860
---

# Urban Tree Explorer

R-first Shiny app for exploring urban tree inventories across multiple U.S. cities.

## Hugging Face Docker Space

This repository is prepared for deployment as a Hugging Face Docker Space.

Runtime expectations:
- the app runs from `app/`
- processed runtime data is read from `data_processed/`
- the assistant reads the API key only from `Sys.getenv("NRP_API_KEY")`
- no preprocessing runs at startup

The Space should have the `NRP_API_KEY` secret configured in Hugging Face Settings.

## Local Run

Use the container R installation only:

```bash
/usr/bin/R -q -e "shiny::runApp('app', host = '0.0.0.0', port = 7860, launch.browser = FALSE)"
```

## Deployment Notes

- `Dockerfile` builds the production image for Hugging Face Spaces
- `.dockerignore` excludes raw CSV inputs, local secrets, git history, and other non-runtime files
- `city_tree_filtered_with_coords_species/` is intentionally excluded from the deployment image
- `data_processed/` is included because it contains the runtime Parquet outputs used by the app

## Repository Layout

- `app/`: Shiny app and assistant integration
- `data_processed/`: runtime Parquet data used by the deployed app
- `docs/`: project specification and inspection notes
- `scripts/`: preprocessing pipeline scripts for local rebuilds
