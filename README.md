# R Urban Tree Explorer

R-first Shiny project for exploring urban tree inventories across multiple U.S. cities.

## Phase 1 status

Phase 1 establishes:

- raw CSV schema inspection
- canonical schema proposal
- initial project structure
- placeholder preprocessing scripts
- placeholder Shiny app shell

Phase 2 will implement the actual preprocessing pipeline into `data_processed/`.

## Run the placeholder app

Use the container R installation only:

```bash
/usr/bin/R -q -e "shiny::runApp('app')"
```

The current app is intentionally a scaffold and shows placeholder panels only.
