# Codex Build Spec — **R Urban Tree Explorer (V1)**

## 1) Project summary

Build a **visualization-first** web app for exploring urban/street tree data from multiple U.S. cities.

This project is **R-first**. Do **not** continue the older React/FastAPI implementation as the main path.  
You may use a small amount of JS/CSS inside the R app when needed for UI polish, but the primary stack should be:

- **R**
- **Shiny**
- **bslib**
- **mapgl** (preferred) or another R-friendly MapLibre-based approach if needed
- **DuckDB**
- **Arrow / Parquet**
- internal **H3-based aggregation** if useful

The immediate goal is **not** LLM integration.  
For this version, the **Data Assistant is only a collapsible placeholder panel**.

---

## 2) Main design goal

The final experience should feel closer to:

- BOSL High Seas Explorer (layout / collapsible floating panels / map-first UI)
- OpenTrees (map behavior and tree display logic)

The app should be:

- mostly map
- visually clean
- minimal UI chrome
- smooth across zoom levels
- not overcrowded with controls

---

## 3) What this V1 must do

### V1 must include
1. A **single-page map app**
2. A **large main map** occupying most of the screen
3. A **top-right collapsible floating panel** for:
   - basemap choice
   - city dropdown
   - species dropdown
   - city statistics
   - one automatically generated chart
4. A **bottom-right collapsible floating panel** labeled **Data Assistant**
   - placeholder only for now
5. Multi-scale map behavior:
   - small zoom / national extent: show cities only
   - more zoom: show city names
   - city-scale zoom: show aggregated “green” tree pattern
   - very high zoom: show individual tree points
6. Fast enough local performance for ~49 cities and ~4.7M tree records
7. A preprocessing pipeline that converts raw per-city CSVs into a better runtime format

### V1 should NOT include
- real LLM integration
- click-on-hexagon statistics workflow
- authentication
- editing
- user uploads
- complicated dashboards
- overdesigned animation
- globe mode

---

## 4) User's exact UI preference

The UI should be **very simple**.

### Main layout
- **Full-screen 2D map** (U.S. study area, not globe)
- **Top-right floating panel**: collapsible
- **Bottom-right floating Data Assistant panel**: collapsible
- default map controls can stay on the map (zoom buttons, etc.)

### Top-right panel contents
This panel replaces the BOSL “basemap / overlays” style panel with a simpler urban-tree-specific panel.

Suggested sections:

#### A. Basemap
User can switch among a few basemap styles, for example:
- Light / Plain
- Satellite
- Minimal gray

Do not add too many choices.

#### B. City
A dropdown with all available cities.

Behavior:
- selecting a city should automatically:
  - fly to the city
  - use a sensible zoom level
  - update city statistics
  - update the chart
  - make the relevant tree layers visible

#### C. Species
A dropdown or searchable select input.

Behavior:
- empty / All species = normal view
- if one species is selected, the map should filter the tree layers for that species within the relevant city context
- stats/chart should update accordingly

#### D. Statistics
Show a compact summary for the selected city:
- total trees
- number of species
- top species
- optional additional metrics if easy

#### E. One chart
Keep only **one** chart in V1.

Recommended chart:
- **Top 10 species in selected city** (bar chart)

If a species filter is active:
- keep the chart simple
- either highlight the selected species in the top-10 ranking
- or switch to a very simple filtered summary chart
- do not overcomplicate this

### Bottom-right panel
- title: **Data Assistant**
- collapsible like BOSL
- can contain:
  - a short “Coming later” note
  - optional disabled input field
- but do **not** implement assistant logic yet

---

## 5) Visual style requirements

The app should feel polished and calm, not like a classroom dashboard.

### Style direction
- map-first
- minimal
- soft floating cards
- subtle glass / translucent panel look is OK
- rounded corners
- restrained green palette for tree layers
- clean typography
- very limited number of controls

### Strong design constraints
- do **not** split the page into many plots/tables
- do **not** make the side panel huge
- do **not** expose many advanced controls in V1
- do **not** use loud rainbow GIS colors
- do **not** use 3D tree icons

---

## 6) Map behavior requirements (very important)

This is the core of the project.

The app should behave like a good map product, not just plot all points at once.

### Behavior by scale / zoom

#### National / low zoom
When the user is viewing a large area:
- show **city markers only**
- do not show all tree points
- city markers should be clean and readable
- city names may appear once zoom is large enough

Possible display:
- small green circles or minimal markers
- labels appear progressively

#### Mid zoom
As the user zooms into an area:
- show more city labels
- if the viewport is clearly focused on one city (or a very small number of cities), begin loading that city’s **aggregated tree layer**
- this aggregated layer should create a **green, dense, OpenTrees-like look**
- do **not** show hard-edged hexes by default

#### City zoom
At city scale:
- show a **green aggregation / density-style view**
- it should look “lush” and informative, not sparse and empty
- this can be implemented internally from H3 or another binning method
- visually, it should look like a continuous or softly tiled green tree layer

#### High zoom
At high zoom:
- show individual tree points
- points should be visible and crisp
- tree rendering should remain green, subtle, and readable
- avoid heavy outlines or giant symbols

### Important rule
The map should never feel empty during the transition from national scale to city scale.

The whole point is to avoid the old behavior:
- city overview only
- then nothing useful
- then suddenly only at very high zoom: tree points

We need **progressive spatial detail**.

---

## 7) Recommendation on hexagons

The user likes that BOSL can show a hex layer, but does **not** want hex clicking/statistics in V1.

### Recommendation
- Use **H3 internally** for preprocessing and multi-scale aggregation
- but **do not expose a visible hex grid layer as a main UI element in V1**
- do **not** put a left-bottom public “hex toggle” in the first version unless it becomes clearly useful later

Reason:
- internally, hex aggregation is useful for scale transitions and performance
- visually, explicit hex borders may make the app feel too analytical and less polished
- the default public-facing map should look like a clean urban tree explorer, not a debug view

If helpful, a hidden developer/debug toggle is acceptable, but it should not be the public default.

---

## 8) Data source and location

The cleaned city CSV files are here:

`C:/sjl/Projects_codes/R_UrbanTreeExplorer/city_tree_filtered_with_coords_species`

There are about:
- 49 cities
- ~4,726,911 tree records
- ~1,871 species

Each city currently exists as one CSV, e.g.:
- `Albuquerque_with_coords_species.csv`
- `Anaheim_with_coords_species.csv`
- `Arlington_with_coords_species.csv`
- ...

Treat these CSVs as the **raw cleaned input**, but **do not use them directly at runtime if a better format is possible**.

---

## 9) Required data pipeline

Codex should build a small preprocessing pipeline before the app relies on the data.

### Goals of preprocessing
1. standardize schema
2. create fast runtime data products
3. support multi-scale map rendering
4. keep future deployment options open

### Required runtime outputs

#### A. `city_summary`
Create a city summary table, ideally in Parquet and/or RDS.

Each record should include at least:
- city
- file_name
- n_trees
- n_species
- lon_center
- lat_center
- xmin
- ymin
- xmax
- ymax
- default_zoom (estimated)
- top_species_1..N or a compact list field

This is used for:
- national city overview
- city dropdown
- fly-to behavior
- statistics panel

#### B. standardized tree table(s)
Convert raw CSVs into a standardized runtime dataset, preferably:
- Parquet
- partitioned by city if practical

At minimum retain:
- city
- longitude
- latitude
- species
- any useful species-clean/common-name fields if available
- optional DBH / condition / other attributes if present

Use stable column names.

#### C. multi-scale aggregate layers
Precompute one or more city-level aggregate datasets for zoom-dependent display.

Recommended approach:
- use H3 or another spatial binning system internally
- precompute multiple resolutions (for example coarse / medium / fine)
- store aggregated counts and maybe richness per bin

Possible fields:
- city
- resolution_level
- cell_id
- count_trees
- count_species
- lon_center
- lat_center
- geometry (optional, depending on implementation)
- dominant_species (optional)

### Important implementation note
The app does **not** need public hex-click statistics in V1.  
These aggregate datasets are primarily for **display and performance**.

---

## 10) Runtime architecture recommendation

### Preferred V1 architecture
Use:

- **Shiny** for app framework
- **mapgl** for the main map if feasible
- **DuckDB** for runtime querying
- **Parquet** for on-disk storage
- **Arrow** for reading/writing Parquet
- **ggplot2** or **echarts4r / plotly** for the single stats chart
- CSS for floating collapsible panels

### Why
This keeps the system:
- R-first
- local-friendly
- performant enough
- future-proof for deployment

### Important note on PMTiles
If PMTiles/vector tiles become helpful later, structure the preprocessing so that later export is possible.

But for **V1 local development**, do **not** overengineer around PMTiles unless it is clearly necessary.  
A good DuckDB + Parquet + zoom-aware query pipeline is acceptable for V1.

---

## 11) Interaction logic

### A. App start
On load:
- show U.S.-wide view
- show city markers
- show the top-right panel expanded
- show the Data Assistant panel collapsed or minimally expanded
- default basemap = light/plain

### B. City selection
When a city is selected:
1. fly to city center / extent
2. set a city-focused zoom
3. update summary stats
4. update species options if needed
5. update the chart
6. load the correct map layers for that city

### C. Species selection
When a species is selected:
1. filter relevant city tree data / aggregate display
2. refresh stats
3. refresh the chart
4. preserve map position unless the user explicitly changes city

### D. Zooming
When zoom changes:
- switch layer detail progressively
- do not hard-reset map style
- do not produce visible flicker if avoidable

### E. No city selected + manual zoom
If the user manually zooms into a city area without using the dropdown:
- allow the app to progressively reveal city labels and tree aggregation when practical
- but keep the logic stable and simple
- avoid loading too many cities’ full point data at once

A reasonable rule:
- at low zoom: cities only
- mid zoom: only aggregate layers for cities intersecting the viewport
- high zoom: only individual points for a single city or a small bounded viewport

---

## 12) Performance rules

This part matters.

### Required performance behavior
- Do not load all 4.7M points into the map at once
- Use zoom-aware queries
- Use viewport/city filtering
- Use precomputed aggregates
- Use cached city summaries and cached aggregate results when possible

### Good runtime strategy
- national mode: read only `city_summary`
- city mode, mid zoom: read aggregated bins only
- high zoom: read only visible points in current city / current viewport

### Optional caching
It is acceptable to cache:
- city summary
- species list per city
- aggregate layer objects
- recent queries

---

## 13) Suggested project structure

Use a clean structure inside:

`C:/sjl/Projects_codes/R_UrbanTreeExplorer`

Suggested layout:

```text
R_UrbanTreeExplorer/
├─ city_tree_filtered_with_coords_species/   # raw cleaned CSV input (existing)
├─ data_processed/
│  ├─ city_summary.parquet
│  ├─ trees/
│  │  └─ city=.../*.parquet
│  ├─ aggregates/
│  │  ├─ coarse/
│  │  ├─ medium/
│  │  └─ fine/
│  └─ metadata/
├─ scripts/
│  ├─ 01_inspect_schema.R
│  ├─ 02_build_standardized_parquet.R
│  ├─ 03_build_city_summary.R
│  ├─ 04_build_aggregates.R
│  └─ 05_validate_outputs.R
├─ app/
│  ├─ app.R
│  ├─ R/
│  │  ├─ data_access.R
│  │  ├─ map_layers.R
│  │  ├─ ui_panels.R
│  │  ├─ server_logic.R
│  │  ├─ stats_helpers.R
│  │  └─ utils.R
│  ├─ www/
│  │  ├─ styles.css
│  │  └─ optional_js.js
│  └─ assets/
└─ README.md
```

---

## 14) Recommended implementation phases

### Phase 1 — data inspection
- inspect all CSVs
- confirm column consistency
- define canonical column names
- document any city-specific exceptions

### Phase 2 — preprocessing
- write standardized Parquet outputs
- build `city_summary`
- build aggregate datasets for multi-scale display

### Phase 3 — app shell
- build full-screen Shiny app
- implement floating top-right and bottom-right panels
- implement panel collapse / expand behavior
- implement basemap switching

### Phase 4 — map behavior
- national city markers
- city labels
- city fly-to
- zoom-based layer transitions
- aggregated green city layer
- high-zoom individual points

### Phase 5 — statistics
- city summary metrics
- top-10 species chart
- species filter logic

### Phase 6 — polish
- color tuning
- smoother transitions
- loading states
- empty-state handling
- responsive resizing
- simple README

---

## 15) Acceptance criteria

The build is successful if all of the following are true:

1. The app opens to a clean U.S.-wide 2D map
2. City markers render quickly
3. The top-right panel is collapsible and visually polished
4. The bottom-right Data Assistant panel is collapsible and present as a placeholder
5. Selecting a city flies to the city and updates stats/chart
6. Selecting a species updates map + stats/chart
7. Zooming in progressively reveals:
   - cities
   - labels
   - aggregated green tree layer
   - individual trees
8. The map never feels empty in the middle zoom range
9. The app uses preprocessed runtime data rather than raw CSVs directly
10. The app is stable enough to run locally without obvious lag spikes

---

## 16) What to avoid

Please avoid the following:

- building a complex multi-tab dashboard
- exposing too many filters
- relying on raw CSV reads during every interaction
- loading all point data at once
- showing explicit hex borders as the default public layer
- building assistant logic now
- turning this into a generic GIS viewer
- adding many nonessential UI widgets

---

## 17) Final guidance to Codex

Prioritize:

1. **clean map product behavior**
2. **good zoom transitions**
3. **simple, beautiful UI**
4. **fast local runtime**
5. **future-ready data structure**

Do not optimize for “most advanced architecture.”  
Optimize for a **strong V1 that already feels like a real product**.

If there is a tradeoff between:
- fancy engineering
- and a simpler stable implementation with good UX

choose the simpler stable implementation.

The most important thing is to make the map feel right.
