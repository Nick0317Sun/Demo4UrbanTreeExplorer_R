#!/usr/bin/env Rscript

source(file.path(getwd(), "scripts", "phase2_helpers.R"))

ensure_phase2_dirs()
reset_standardized_outputs()
ensure_phase2_dirs()
write_canonical_schema_metadata()

raw_files <- list_raw_files()
if (length(raw_files) == 0) {
  stop("No raw CSV files found under ", raw_data_dir)
}

city_manifests <- vector("list", length(raw_files))
completeness_manifests <- vector("list", length(raw_files))

for (i in seq_along(raw_files)) {
  file_path <- raw_files[[i]]
  standardized <- standardize_city_data(file_path)
  city_key <- standardized$city_key[[1]]
  output_path <- tree_output_path(city_key)

  write_parquet_file(standardized, output_path)

  city_manifests[[i]] <- tibble::tibble(
    city_key = city_key,
    city = standardized$city[[1]],
    state = standardized$state[[1]],
    source_file = basename(file_path),
    parquet_path = output_path,
    row_count = nrow(standardized),
    valid_coordinate_count = sum(standardized$has_valid_coordinates),
    invalid_coordinate_count = sum(!standardized$has_valid_coordinates),
    missing_species_count = sum(is.na(standardized$scientific_name) & is.na(standardized$common_name)),
    missing_common_name_count = sum(is.na(standardized$common_name)),
    missing_scientific_name_count = sum(is.na(standardized$scientific_name))
  )

  completeness_manifests[[i]] <- collect_optional_field_completeness(standardized) %>%
    mutate(
      city_key = city_key,
      city = standardized$city[[1]],
      state = standardized$state[[1]],
      .before = 1
    )

  message(
    sprintf(
      "[%02d/%02d] standardized %s (%s rows)",
      i, length(raw_files), basename(file_path), format(nrow(standardized), big.mark = ",")
    )
  )
}

manifest_tbl <- dplyr::bind_rows(city_manifests) %>% arrange(city_key)
completeness_tbl <- dplyr::bind_rows(completeness_manifests) %>% arrange(city_key, field_name)

write_parquet_file(manifest_tbl, file.path(metadata_dir, "standardized_manifest.parquet"))
readr::write_csv(manifest_tbl, file.path(metadata_dir, "standardized_manifest.csv"))
write_parquet_file(completeness_tbl, file.path(metadata_dir, "standardized_optional_field_completeness.parquet"))
readr::write_csv(completeness_tbl, file.path(metadata_dir, "standardized_optional_field_completeness.csv"))

build_manifest <- list(
  generated_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  raw_file_count = length(raw_files),
  standardized_city_count = nrow(manifest_tbl),
  standardized_row_count = sum(manifest_tbl$row_count),
  output_root = processed_dir
)
write_json(build_manifest, file.path(metadata_dir, "standardized_build_manifest.json"), pretty = TRUE, auto_unbox = TRUE)

message("Wrote standardized tree outputs to ", trees_dir)
