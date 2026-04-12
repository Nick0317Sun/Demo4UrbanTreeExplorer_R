# Phase 1 Schema Inspection

Date: 2026-04-12

## Scope

Inspected all CSV files under `city_tree_filtered_with_coords_species/` without starting full preprocessing.

## Raw file inventory

- Files inspected: 49
- Header width: 28 columns in every file
- Structural consistency: all files use the same 28 column names
- Main schema drift: column order, data typing, and field population vary by city

## Shared raw column set

The raw inputs share this 28-column superset:

1. `city_ID`
2. `tree_ID`
3. `city`
4. `state`
5. `greater_metro`
6. `scientific_name`
7. `common_name`
8. `longitude_coordinate`
9. `latitude_coordinate`
10. `address`
11. `location_type`
12. `location_name`
13. `zipcode`
14. `neighborhood`
15. `ward`
16. `district`
17. `native`
18. `condition`
19. `overhead_utility`
20. `diameter_breast_height_CM`
21. `diameter_breast_height_binned_CM`
22. `height_M`
23. `height_binned_M`
24. `planted_date`
25. `most_recent_observation`
26. `most_recent_observation_type`
27. `retired_date`
28. `percent_population`

## Major differences across cities

### 1. Column order is not stable

The same 28 fields appear in different orders. Phase 2 should reorder columns explicitly during standardization.

### 2. ID fields are not type-stable

- `city_ID` appears as integer, character, or all-`NA` depending on city
- `tree_ID` is often empty and sometimes effectively missing
- some city-specific IDs contain formatted strings rather than numeric values

### 3. Name fields are unevenly populated

- `scientific_name` is usually more reliable than `common_name`
- some cities have missing `common_name`
- some scientific names are genus-only or inconsistent in casing/granularity

### 4. Measurement fields vary in completeness

- `diameter_breast_height_CM` is numeric in some cities and entirely empty in others
- `height_M` is numeric in some cities and entirely empty in others
- binned measurement fields are often present even where numeric measurements are missing

### 5. Date fields vary in format and sparsity

- observed formats include `m/d/YYYY` and `mm/dd/YYYY`
- several cities leave observation and planting dates empty
- `most_recent_observation_type` is inconsistently populated

### 6. Location metadata is city-specific

- `address`, `location_name`, `ward`, `district`, `zipcode`, and `neighborhood` are highly uneven across cities
- some cities expose useful governance or utility fields, others leave them fully empty

### 7. Logical NA inference from base R reads is misleading

When raw files are sampled with `read.csv()`, all-empty columns are inferred as logical. Phase 2 should avoid relying on guessed types from small samples.

## Canonical schema proposal

Phase 2 should standardize raw inputs into a runtime tree table with stable names and stable types.

### Core required runtime fields

- `city` character
- `state` character
- `metro_name` character
- `source_file` character
- `source_city_id` character
- `source_tree_id` character
- `longitude` double
- `latitude` double
- `scientific_name` character
- `common_name` character
- `species_display` character

### Optional runtime attributes

- `address` character
- `location_type` character
- `location_name` character
- `zipcode` character
- `neighborhood` character
- `ward` character
- `district` character
- `native_status` character
- `condition` character
- `overhead_utility` character
- `dbh_cm` double
- `dbh_bin` character
- `height_m` double
- `height_bin` character
- `planted_date` date
- `observed_date` date
- `observation_type` character
- `retired_date` date
- `percent_population` double

### Derived fields to add during preprocessing

- `city_key` lower-snake or slug identifier
- `record_id` stable surrogate key
- `has_valid_coordinates` logical
- `species_key` normalized species identifier

## Standardization rules for Phase 2

1. Preserve raw provenance with `source_file`, `source_city_id`, and `source_tree_id`.
2. Rename geographic columns from `*_coordinate` to `longitude` and `latitude`.
3. Coerce IDs and code-like fields to character, not numeric.
4. Parse dates with tolerant month/day/year handling.
5. Keep both raw measurement bins and numeric measurements where available.
6. Use `scientific_name` as the primary species key when `common_name` is missing.
7. Exclude rows with invalid coordinates from map outputs, but count and log them in validation.

## Phase 2 outputs expected from this schema

- `data_processed/city_summary.parquet`
- `data_processed/trees/city=.../*.parquet`
- `data_processed/aggregates/{coarse,medium,fine}/*.parquet`
- validation metadata under `data_processed/metadata/`
