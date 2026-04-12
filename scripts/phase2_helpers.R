suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(jsonlite)
  library(lubridate)
  library(readr)
  library(stringr)
})

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0) {
    y
  } else {
    x
  }
}

project_root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
raw_data_dir <- file.path(project_root, "city_tree_filtered_with_coords_species")
processed_dir <- file.path(project_root, "data_processed")
trees_dir <- file.path(processed_dir, "trees")
aggregates_dir <- file.path(processed_dir, "aggregates")
metadata_dir <- file.path(processed_dir, "metadata")
city_summary_path <- file.path(processed_dir, "city_summary.parquet")

raw_column_names <- c(
  "city_ID", "tree_ID", "city", "state", "greater_metro", "scientific_name",
  "common_name", "longitude_coordinate", "latitude_coordinate", "address",
  "location_type", "location_name", "zipcode", "neighborhood", "ward",
  "district", "native", "condition", "overhead_utility",
  "diameter_breast_height_CM", "diameter_breast_height_binned_CM", "height_M",
  "height_binned_M", "planted_date", "most_recent_observation",
  "most_recent_observation_type", "retired_date", "percent_population"
)

canonical_schema <- tibble::tribble(
  ~column_name, ~storage_type, ~required, ~description,
  "record_id", "string", TRUE, "Deterministic record identifier derived from city file and row order.",
  "city_key", "string", TRUE, "Lower snake-case city identifier used for partitioning.",
  "city", "string", TRUE, "Display city name from the source inventory.",
  "state", "string", TRUE, "Display state name from the source inventory.",
  "metro_name", "string", FALSE, "Source greater metro field standardized for runtime use.",
  "source_file", "string", TRUE, "Source CSV filename.",
  "source_city_id", "string", FALSE, "City-level source identifier preserved as text.",
  "source_tree_id", "string", FALSE, "Tree-level source identifier preserved as text.",
  "longitude", "float64", TRUE, "Tree longitude in WGS84 decimal degrees.",
  "latitude", "float64", TRUE, "Tree latitude in WGS84 decimal degrees.",
  "scientific_name", "string", FALSE, "Scientific species name after whitespace normalization.",
  "common_name", "string", FALSE, "Common species name after whitespace normalization.",
  "species_display", "string", TRUE, "Preferred display label, favoring common name then scientific name.",
  "species_key", "string", TRUE, "Normalized species identifier for filtering and aggregation.",
  "address", "string", FALSE, "Source address text.",
  "location_type", "string", FALSE, "Source location type text.",
  "location_name", "string", FALSE, "Source location name text.",
  "zipcode", "string", FALSE, "Source postal code text.",
  "neighborhood", "string", FALSE, "Source neighborhood text.",
  "ward", "string", FALSE, "Source ward text.",
  "district", "string", FALSE, "Source district text.",
  "native_status", "string", FALSE, "Source native classification.",
  "condition", "string", FALSE, "Source condition text.",
  "overhead_utility", "string", FALSE, "Source overhead utility text.",
  "dbh_cm", "float64", FALSE, "Diameter at breast height in centimeters.",
  "dbh_bin", "string", FALSE, "Binned DBH category from the source.",
  "height_m", "float64", FALSE, "Tree height in meters.",
  "height_bin", "string", FALSE, "Binned height category from the source.",
  "planted_date", "date32", FALSE, "Parsed planting date.",
  "observed_date", "date32", FALSE, "Parsed most recent observation date.",
  "observation_type", "string", FALSE, "Source observation type.",
  "retired_date", "date32", FALSE, "Parsed retirement date.",
  "percent_population", "float64", FALSE, "Source percent population value parsed as numeric.",
  "has_valid_coordinates", "bool", TRUE, "TRUE when longitude and latitude are present and within valid bounds."
)

optional_field_columns <- c(
  "source_city_id", "source_tree_id", "address", "location_type", "location_name",
  "zipcode", "neighborhood", "ward", "district", "native_status", "condition",
  "overhead_utility", "dbh_cm", "dbh_bin", "height_m", "height_bin",
  "planted_date", "observed_date", "observation_type", "retired_date",
  "percent_population"
)

resolution_config <- tibble::tribble(
  ~resolution_name, ~cell_size_deg,
  "coarse", 0.020,
  "medium", 0.005,
  "fine", 0.001
)

ensure_phase2_dirs <- function() {
  dir.create(processed_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(trees_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(aggregates_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(metadata_dir, recursive = TRUE, showWarnings = FALSE)
  for (res_name in resolution_config$resolution_name) {
    dir.create(file.path(aggregates_dir, res_name), recursive = TRUE, showWarnings = FALSE)
  }
}

clean_directory_contents <- function(dir_path, keep_names = character()) {
  if (!dir.exists(dir_path)) {
    return(invisible(NULL))
  }
  entries <- list.files(dir_path, full.names = TRUE, all.files = TRUE, no.. = TRUE)
  if (length(keep_names) > 0) {
    entries <- entries[basename(entries) %in% keep_names == FALSE]
  }
  if (length(entries) > 0) {
    unlink(entries, recursive = TRUE, force = TRUE)
  }
  invisible(NULL)
}

reset_standardized_outputs <- function() {
  clean_directory_contents(trees_dir)
  clean_directory_contents(metadata_dir, keep_names = c("README.md"))
  if (file.exists(city_summary_path)) {
    unlink(city_summary_path, force = TRUE)
  }
  for (res_name in resolution_config$resolution_name) {
    clean_directory_contents(file.path(aggregates_dir, res_name))
  }
}

reset_aggregate_outputs <- function() {
  for (res_name in resolution_config$resolution_name) {
    clean_directory_contents(file.path(aggregates_dir, res_name))
  }
}

list_raw_files <- function() {
  files <- list.files(raw_data_dir, pattern = "[.]csv$", full.names = TRUE)
  files[order(basename(files))]
}

normalize_text <- function(x) {
  if (is.null(x)) {
    return(rep(NA_character_, 0))
  }
  x <- as.character(x)
  x <- str_squish(x)
  x[x %in% c("", "NA", "N/A", "NULL", "null", "NaN", "nan")] <- NA_character_
  x
}

parse_number_safe <- function(x) {
  x <- normalize_text(x)
  suppressWarnings(readr::parse_double(x, na = c("", "NA", "N/A", "NULL", "null")))
}

parse_date_safe <- function(x) {
  x <- normalize_text(x)
  parsed <- suppressWarnings(
    parse_date_time(
      x,
      orders = c("mdY", "m/d/Y", "m/d/y", "Ymd", "Y-m-d", "Y/m/d"),
      quiet = TRUE,
      tz = "UTC"
    )
  )
  as.Date(parsed)
}

first_non_missing_scalar <- function(x, fallback = NA_character_) {
  x <- normalize_text(x)
  x <- x[!is.na(x)]
  if (length(x) == 0) {
    fallback
  } else {
    x[[1]]
  }
}

slugify_value <- function(x, fallback = "unknown") {
  x <- normalize_text(x)
  x[is.na(x)] <- fallback
  x <- str_to_lower(x)
  x <- str_replace_all(x, "[^a-z0-9]+", "_")
  x <- str_replace_all(x, "^_+|_+$", "")
  x[x == ""] <- fallback
  x
}

default_city_name_from_file <- function(file_path) {
  stem <- basename(file_path)
  stem <- str_remove(stem, "_with_coords_species[.]csv$")
  spaced <- str_replace_all(stem, "([a-z])([A-Z])", "\\1 \\2")
  str_trim(spaced)
}

make_record_ids <- function(city_key, n_rows) {
  width <- max(7L, nchar(as.character(n_rows)))
  paste0(city_key, "_", formatC(seq_len(n_rows), width = width, flag = "0"))
}

compute_valid_coordinates <- function(longitude, latitude) {
  !is.na(longitude) &
    !is.na(latitude) &
    longitude >= -180 & longitude <= 180 &
    latitude >= -90 & latitude <= 90
}

read_raw_city_csv <- function(file_path) {
  readr::read_csv(
    file_path,
    col_types = readr::cols(.default = readr::col_character()),
    progress = FALSE,
    show_col_types = FALSE,
    na = c("", "NA", "N/A", "NULL", "null")
  )
}

standardize_city_data <- function(file_path) {
  raw_tbl <- read_raw_city_csv(file_path)

  missing_cols <- setdiff(raw_column_names, names(raw_tbl))
  if (length(missing_cols) > 0) {
    stop("Missing expected raw columns in ", basename(file_path), ": ", paste(missing_cols, collapse = ", "))
  }

  raw_tbl <- raw_tbl[, raw_column_names]
  raw_tbl[] <- lapply(raw_tbl, normalize_text)

  n_rows <- nrow(raw_tbl)
  fallback_city <- default_city_name_from_file(file_path)
  city <- rep(fallback_city, n_rows)
  city_key <- rep(slugify_value(fallback_city), n_rows)
  state_value <- first_non_missing_scalar(raw_tbl$state)
  metro_value <- first_non_missing_scalar(raw_tbl$greater_metro)

  scientific_name <- normalize_text(raw_tbl$scientific_name)
  common_name <- normalize_text(raw_tbl$common_name)
  species_display <- dplyr::coalesce(common_name, scientific_name, "Unknown species")
  species_key <- slugify_value(dplyr::coalesce(scientific_name, common_name, "unknown_species"))

  longitude <- parse_number_safe(raw_tbl$longitude_coordinate)
  latitude <- parse_number_safe(raw_tbl$latitude_coordinate)
  standardized <- tibble::tibble(
    record_id = make_record_ids(city_key[[1]], n_rows),
    city_key = city_key,
    city = city,
    state = rep(state_value, n_rows),
    metro_name = rep(metro_value, n_rows),
    source_file = basename(file_path),
    source_city_id = raw_tbl$city_ID,
    source_tree_id = raw_tbl$tree_ID,
    longitude = longitude,
    latitude = latitude,
    scientific_name = scientific_name,
    common_name = common_name,
    species_display = species_display,
    species_key = species_key,
    address = raw_tbl$address,
    location_type = raw_tbl$location_type,
    location_name = raw_tbl$location_name,
    zipcode = raw_tbl$zipcode,
    neighborhood = raw_tbl$neighborhood,
    ward = raw_tbl$ward,
    district = raw_tbl$district,
    native_status = raw_tbl$native,
    condition = raw_tbl$condition,
    overhead_utility = raw_tbl$overhead_utility,
    dbh_cm = parse_number_safe(raw_tbl$diameter_breast_height_CM),
    dbh_bin = raw_tbl$diameter_breast_height_binned_CM,
    height_m = parse_number_safe(raw_tbl$height_M),
    height_bin = raw_tbl$height_binned_M,
    planted_date = parse_date_safe(raw_tbl$planted_date),
    observed_date = parse_date_safe(raw_tbl$most_recent_observation),
    observation_type = raw_tbl$most_recent_observation_type,
    retired_date = parse_date_safe(raw_tbl$retired_date),
    percent_population = parse_number_safe(raw_tbl$percent_population),
    has_valid_coordinates = compute_valid_coordinates(longitude, latitude)
  )

  standardized
}

tree_output_path <- function(city_key) {
  file.path(trees_dir, paste0("city=", city_key), "trees.parquet")
}

aggregate_output_path <- function(resolution_name, city_key) {
  file.path(aggregates_dir, resolution_name, paste0("city=", city_key), "aggregates.parquet")
}

write_canonical_schema_metadata <- function() {
  schema_csv_path <- file.path(metadata_dir, "canonical_schema.csv")
  schema_json_path <- file.path(metadata_dir, "canonical_schema.json")
  readr::write_csv(canonical_schema, schema_csv_path)
  write_json(canonical_schema, schema_json_path, pretty = TRUE, auto_unbox = TRUE)
}

write_parquet_file <- function(tbl, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  arrow::write_parquet(tbl, sink = path, compression = "zstd")
}

read_tree_parquet <- function(path) {
  arrow::read_parquet(path, as_data_frame = TRUE)
}

list_tree_files <- function() {
  files <- list.files(trees_dir, pattern = "[.]parquet$", recursive = TRUE, full.names = TRUE)
  files[order(files)]
}

compute_top_species <- function(tbl, top_n = 10) {
  species_summary <- tbl %>%
    filter(!is.na(species_display), species_display != "Unknown species") %>%
    count(species_display, sort = TRUE, name = "tree_count") %>%
    slice_head(n = top_n)

  species_summary
}

estimate_default_zoom <- function(xmin, xmax, ymin, ymax) {
  span <- max(xmax - xmin, ymax - ymin, na.rm = TRUE)
  if (!is.finite(span)) {
    return(9)
  }
  if (span > 12) {
    5
  } else if (span > 6) {
    6
  } else if (span > 3) {
    7
  } else if (span > 1.5) {
    8
  } else if (span > 0.75) {
    9
  } else if (span > 0.35) {
    10
  } else {
    11
  }
}

build_single_resolution_aggregate <- function(tbl, resolution_name, cell_size_deg) {
  valid_tbl <- tbl %>%
    filter(has_valid_coordinates)

  if (nrow(valid_tbl) == 0) {
    return(tibble::tibble(
      city_key = character(),
      city = character(),
      state = character(),
      resolution_name = character(),
      cell_size_deg = numeric(),
      cell_id = character(),
      lon_center = numeric(),
      lat_center = numeric(),
      xmin = numeric(),
      xmax = numeric(),
      ymin = numeric(),
      ymax = numeric(),
      count_trees = integer(),
      count_species = integer(),
      dominant_species = character(),
      dominant_species_count = integer()
    ))
  }

  valid_tbl <- valid_tbl %>%
    mutate(
      grid_x = floor(longitude / cell_size_deg),
      grid_y = floor(latitude / cell_size_deg),
      cell_id = paste(city_key, resolution_name, grid_x, grid_y, sep = ":")
    )

  dominant_tbl <- valid_tbl %>%
    filter(!is.na(species_display), species_display != "Unknown species") %>%
    count(cell_id, species_display, name = "species_tree_count", sort = TRUE) %>%
    group_by(cell_id) %>%
    slice_max(order_by = species_tree_count, n = 1, with_ties = FALSE) %>%
    ungroup() %>%
    transmute(
      cell_id = cell_id,
      dominant_species = species_display,
      dominant_species_count = species_tree_count
    )

  valid_tbl %>%
    group_by(city_key, city, state, grid_x, grid_y, cell_id) %>%
    summarise(
      count_trees = dplyr::n(),
      count_species = dplyr::n_distinct(species_key[!is.na(species_key) & species_key != "unknown_species"]),
      .groups = "drop"
    ) %>%
    mutate(
      resolution_name = resolution_name,
      cell_size_deg = cell_size_deg,
      xmin = grid_x * cell_size_deg,
      xmax = (grid_x + 1) * cell_size_deg,
      ymin = grid_y * cell_size_deg,
      ymax = (grid_y + 1) * cell_size_deg,
      lon_center = xmin + (cell_size_deg / 2),
      lat_center = ymin + (cell_size_deg / 2)
    ) %>%
    left_join(dominant_tbl, by = "cell_id") %>%
    select(
      city_key, city, state, resolution_name, cell_size_deg, cell_id,
      lon_center, lat_center, xmin, xmax, ymin, ymax,
      count_trees, count_species, dominant_species, dominant_species_count
    )
}

collect_optional_field_completeness <- function(tbl) {
  tibble::tibble(
    field_name = optional_field_columns,
    non_missing_count = vapply(optional_field_columns, function(col_name) sum(!is.na(tbl[[col_name]])), numeric(1)),
    completeness_ratio = vapply(optional_field_columns, function(col_name) mean(!is.na(tbl[[col_name]])), numeric(1))
  )
}
