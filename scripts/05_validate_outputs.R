#!/usr/bin/env Rscript

source(file.path(getwd(), "scripts", "phase2_helpers.R"))

ensure_phase2_dirs()
tree_files <- list_tree_files()
if (length(tree_files) == 0) {
  stop("No standardized tree Parquet files found. Run scripts/02_build_standardized_parquet.R first.")
}
if (!file.exists(city_summary_path)) {
  stop("Missing city summary output. Run scripts/03_build_city_summary.R first.")
}

expected_columns <- canonical_schema$column_name
expected_types <- setNames(canonical_schema$storage_type, canonical_schema$column_name)

row_count_rows <- vector("list", length(tree_files))
schema_rows <- vector("list", length(tree_files))
species_rows <- vector("list", length(tree_files))
coordinate_rows <- vector("list", length(tree_files))
completeness_rows <- vector("list", length(tree_files))

for (i in seq_along(tree_files)) {
  tree_file <- tree_files[[i]]
  tree_tbl <- read_tree_parquet(tree_file)
  city_key <- tree_tbl$city_key[[1]]

  actual_classes <- vapply(tree_tbl, function(col) class(col)[1], character(1))

  row_count_rows[[i]] <- tibble::tibble(
    city_key = city_key,
    city = tree_tbl$city[[1]],
    state = tree_tbl$state[[1]],
    row_count = nrow(tree_tbl)
  )

  coordinate_rows[[i]] <- tibble::tibble(
    city_key = city_key,
    city = tree_tbl$city[[1]],
    state = tree_tbl$state[[1]],
    valid_coordinate_count = sum(tree_tbl$has_valid_coordinates),
    invalid_coordinate_count = sum(!tree_tbl$has_valid_coordinates),
    missing_longitude_count = sum(is.na(tree_tbl$longitude)),
    missing_latitude_count = sum(is.na(tree_tbl$latitude))
  )

  species_rows[[i]] <- tibble::tibble(
    city_key = city_key,
    city = tree_tbl$city[[1]],
    state = tree_tbl$state[[1]],
    missing_species_count = sum(is.na(tree_tbl$scientific_name) & is.na(tree_tbl$common_name)),
    missing_common_name_count = sum(is.na(tree_tbl$common_name)),
    missing_scientific_name_count = sum(is.na(tree_tbl$scientific_name)),
    distinct_species_count = dplyr::n_distinct(tree_tbl$species_key[!is.na(tree_tbl$species_key) & tree_tbl$species_key != "unknown_species"])
  )

  schema_rows[[i]] <- tibble::tibble(
    city_key = city_key,
    city = tree_tbl$city[[1]],
    column_name = expected_columns,
    expected_storage_type = unname(expected_types[expected_columns]),
    actual_r_class = unname(actual_classes[expected_columns]),
    column_present = expected_columns %in% names(tree_tbl),
    non_missing_count = vapply(expected_columns, function(col_name) sum(!is.na(tree_tbl[[col_name]])), numeric(1)),
    schema_match = expected_columns %in% names(tree_tbl)
  )

  completeness_rows[[i]] <- collect_optional_field_completeness(tree_tbl) %>%
    mutate(
      city_key = city_key,
      city = tree_tbl$city[[1]],
      state = tree_tbl$state[[1]],
      .before = 1
    )
}

row_counts_tbl <- bind_rows(row_count_rows) %>% arrange(city_key)
coordinate_tbl <- bind_rows(coordinate_rows) %>% arrange(city_key)
species_tbl <- bind_rows(species_rows) %>% arrange(city_key)
schema_tbl <- bind_rows(schema_rows) %>% arrange(city_key, column_name)
completeness_tbl <- bind_rows(completeness_rows) %>% arrange(city_key, field_name)

aggregate_manifest_path <- file.path(metadata_dir, "aggregate_manifest.parquet")
if (!file.exists(aggregate_manifest_path)) {
  stop("Missing aggregate manifest. Run scripts/04_build_aggregates.R first.")
}
aggregate_manifest_tbl <- arrow::read_parquet(aggregate_manifest_path, as_data_frame = TRUE)
city_summary_tbl <- arrow::read_parquet(city_summary_path, as_data_frame = TRUE)

summary_tbl <- tibble::tibble(
  generated_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  standardized_city_count = nrow(row_counts_tbl),
  standardized_row_count = sum(row_counts_tbl$row_count),
  city_summary_row_count = nrow(city_summary_tbl),
  aggregate_file_count = nrow(aggregate_manifest_tbl),
  aggregate_bin_count = sum(aggregate_manifest_tbl$bin_count),
  schema_column_count = length(expected_columns),
  schema_missing_column_issues = sum(!schema_tbl$column_present),
  total_invalid_coordinate_count = sum(coordinate_tbl$invalid_coordinate_count),
  total_missing_species_count = sum(species_tbl$missing_species_count)
)

write_parquet_file(row_counts_tbl, file.path(metadata_dir, "validation_row_counts.parquet"))
readr::write_csv(row_counts_tbl, file.path(metadata_dir, "validation_row_counts.csv"))
write_parquet_file(coordinate_tbl, file.path(metadata_dir, "validation_coordinate_quality.parquet"))
readr::write_csv(coordinate_tbl, file.path(metadata_dir, "validation_coordinate_quality.csv"))
write_parquet_file(species_tbl, file.path(metadata_dir, "validation_species_missingness.parquet"))
readr::write_csv(species_tbl, file.path(metadata_dir, "validation_species_missingness.csv"))
write_parquet_file(schema_tbl, file.path(metadata_dir, "validation_schema_types.parquet"))
readr::write_csv(schema_tbl, file.path(metadata_dir, "validation_schema_types.csv"))
write_parquet_file(completeness_tbl, file.path(metadata_dir, "validation_optional_field_completeness.parquet"))
readr::write_csv(completeness_tbl, file.path(metadata_dir, "validation_optional_field_completeness.csv"))
write_parquet_file(summary_tbl, file.path(metadata_dir, "validation_summary.parquet"))
readr::write_csv(summary_tbl, file.path(metadata_dir, "validation_summary.csv"))

write_json(
  list(
    generated_at_utc = summary_tbl$generated_at_utc[[1]],
    standardized_city_count = summary_tbl$standardized_city_count[[1]],
    standardized_row_count = summary_tbl$standardized_row_count[[1]],
    total_invalid_coordinate_count = summary_tbl$total_invalid_coordinate_count[[1]],
    total_missing_species_count = summary_tbl$total_missing_species_count[[1]],
    schema_missing_column_issues = summary_tbl$schema_missing_column_issues[[1]]
  ),
  file.path(metadata_dir, "validation_summary.json"),
  pretty = TRUE,
  auto_unbox = TRUE
)

message("Wrote validation outputs under ", metadata_dir)
