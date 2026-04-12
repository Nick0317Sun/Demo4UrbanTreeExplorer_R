#!/usr/bin/env Rscript

source(file.path(getwd(), "scripts", "phase2_helpers.R"))

ensure_phase2_dirs()
tree_files <- list_tree_files()
if (length(tree_files) == 0) {
  stop("No standardized tree Parquet files found. Run scripts/02_build_standardized_parquet.R first.")
}

summary_rows <- vector("list", length(tree_files))
top_species_rows <- vector("list", length(tree_files))

for (i in seq_along(tree_files)) {
  tree_file <- tree_files[[i]]
  tree_tbl <- read_tree_parquet(tree_file)
  valid_tbl <- tree_tbl %>% filter(has_valid_coordinates)

  bbox <- if (nrow(valid_tbl) > 0) {
    list(
      xmin = min(valid_tbl$longitude),
      xmax = max(valid_tbl$longitude),
      ymin = min(valid_tbl$latitude),
      ymax = max(valid_tbl$latitude)
    )
  } else {
    list(xmin = NA_real_, xmax = NA_real_, ymin = NA_real_, ymax = NA_real_)
  }

  top_species <- compute_top_species(tree_tbl, top_n = 10)
  top_species_rows[[i]] <- top_species %>%
    mutate(
      city_key = tree_tbl$city_key[[1]],
      city = tree_tbl$city[[1]],
      state = tree_tbl$state[[1]],
      rank = row_number(),
      .before = 1
    )

  summary_rows[[i]] <- tibble::tibble(
    city_key = tree_tbl$city_key[[1]],
    city = tree_tbl$city[[1]],
    state = tree_tbl$state[[1]],
    metro_name = tree_tbl$metro_name[[1]],
    source_file = tree_tbl$source_file[[1]],
    n_trees = nrow(tree_tbl),
    n_valid_coordinates = sum(tree_tbl$has_valid_coordinates),
    n_invalid_coordinates = sum(!tree_tbl$has_valid_coordinates),
    n_species = dplyr::n_distinct(tree_tbl$species_key[!is.na(tree_tbl$species_key) & tree_tbl$species_key != "unknown_species"]),
    missing_species_count = sum(is.na(tree_tbl$scientific_name) & is.na(tree_tbl$common_name)),
    lon_center = if (nrow(valid_tbl) > 0) (bbox$xmin + bbox$xmax) / 2 else NA_real_,
    lat_center = if (nrow(valid_tbl) > 0) (bbox$ymin + bbox$ymax) / 2 else NA_real_,
    xmin = bbox$xmin,
    ymin = bbox$ymin,
    xmax = bbox$xmax,
    ymax = bbox$ymax,
    default_zoom = estimate_default_zoom(bbox$xmin, bbox$xmax, bbox$ymin, bbox$ymax),
    top_species_1 = top_species$species_display[[1]] %||% NA_character_,
    top_species_2 = top_species$species_display[[2]] %||% NA_character_,
    top_species_3 = top_species$species_display[[3]] %||% NA_character_,
    top_species_json = as.character(jsonlite::toJSON(top_species, auto_unbox = TRUE))
  )

  message(
    sprintf(
      "[%02d/%02d] summarized %s (%s trees)",
      i, length(tree_files), tree_tbl$city[[1]], format(nrow(tree_tbl), big.mark = ",")
    )
  )
}

city_summary_tbl <- bind_rows(summary_rows) %>% arrange(city_key)
top_species_tbl <- bind_rows(top_species_rows) %>% arrange(city_key, rank)

write_parquet_file(city_summary_tbl, city_summary_path)
write_parquet_file(top_species_tbl, file.path(metadata_dir, "city_top_species.parquet"))
readr::write_csv(city_summary_tbl, file.path(metadata_dir, "city_summary_preview.csv"))
readr::write_csv(top_species_tbl, file.path(metadata_dir, "city_top_species.csv"))

message("Wrote city summary to ", city_summary_path)
