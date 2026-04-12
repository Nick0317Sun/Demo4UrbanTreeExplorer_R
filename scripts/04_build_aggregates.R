#!/usr/bin/env Rscript

source(file.path(getwd(), "scripts", "phase2_helpers.R"))

ensure_phase2_dirs()
reset_aggregate_outputs()
ensure_phase2_dirs()
tree_files <- list_tree_files()
if (length(tree_files) == 0) {
  stop("No standardized tree Parquet files found. Run scripts/02_build_standardized_parquet.R first.")
}

aggregate_manifest <- list()
manifest_index <- 1L

for (i in seq_along(tree_files)) {
  tree_file <- tree_files[[i]]
  tree_tbl <- read_tree_parquet(tree_file)
  city_key <- tree_tbl$city_key[[1]]

  for (res_idx in seq_len(nrow(resolution_config))) {
    res_name <- resolution_config$resolution_name[[res_idx]]
    cell_size_deg <- resolution_config$cell_size_deg[[res_idx]]
    aggregate_tbl <- build_single_resolution_aggregate(tree_tbl, res_name, cell_size_deg)
    output_path <- aggregate_output_path(res_name, city_key)

    write_parquet_file(aggregate_tbl, output_path)

    aggregate_manifest[[manifest_index]] <- tibble::tibble(
      city_key = city_key,
      city = tree_tbl$city[[1]],
      state = tree_tbl$state[[1]],
      resolution_name = res_name,
      cell_size_deg = cell_size_deg,
      aggregate_path = output_path,
      bin_count = nrow(aggregate_tbl),
      total_tree_count = sum(aggregate_tbl$count_trees),
      max_bin_tree_count = if (nrow(aggregate_tbl) > 0) max(aggregate_tbl$count_trees) else 0L
    )
    manifest_index <- manifest_index + 1L
  }

  message(
    sprintf(
      "[%02d/%02d] aggregated %s",
      i, length(tree_files), tree_tbl$city[[1]]
    )
  )
}

aggregate_manifest_tbl <- bind_rows(aggregate_manifest) %>% arrange(city_key, resolution_name)
write_parquet_file(aggregate_manifest_tbl, file.path(metadata_dir, "aggregate_manifest.parquet"))
readr::write_csv(aggregate_manifest_tbl, file.path(metadata_dir, "aggregate_manifest.csv"))

message("Wrote aggregate outputs under ", aggregates_dir)
