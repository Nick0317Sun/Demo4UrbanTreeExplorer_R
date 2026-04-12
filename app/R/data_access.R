runtime_cache <- new.env(parent = emptyenv())

load_city_summary_data <- function() {
  if (!exists("city_summary", envir = runtime_cache, inherits = FALSE)) {
    runtime_cache$city_summary <- arrow::read_parquet(
      runtime_paths()$city_summary,
      as_data_frame = TRUE
    ) |>
      dplyr::arrange(city)
  }

  runtime_cache$city_summary
}

load_city_top_species_data <- function() {
  if (!exists("city_top_species", envir = runtime_cache, inherits = FALSE)) {
    runtime_cache$city_top_species <- arrow::read_parquet(
      runtime_paths()$city_top_species,
      as_data_frame = TRUE
    )
  }

  runtime_cache$city_top_species
}

city_choices <- function() {
  city_summary <- load_city_summary_data()
  choices <- stats::setNames(city_summary$city_key, city_summary$city)
  c("National view" = "", choices)
}

get_city_summary_row <- function(city_key) {
  if (is.null(city_key) || identical(city_key, "")) {
    return(NULL)
  }

  city_summary <- load_city_summary_data()
  row <- city_summary[city_summary$city_key == city_key, , drop = FALSE]
  if (nrow(row) == 0) NULL else row[1, , drop = FALSE]
}

load_city_tree_data <- function(city_key) {
  cache_key <- paste0("tree_", city_key)
  if (!exists(cache_key, envir = runtime_cache, inherits = FALSE)) {
    path <- file.path(runtime_paths()$trees_dir, paste0("city=", city_key), "trees.parquet")
    runtime_cache[[cache_key]] <- arrow::read_parquet(path, as_data_frame = TRUE)
  }

  runtime_cache[[cache_key]]
}

load_city_aggregate_data <- function(city_key, resolution_name = "medium") {
  cache_key <- paste0("aggregate_", resolution_name, "_", city_key)
  if (!exists(cache_key, envir = runtime_cache, inherits = FALSE)) {
    path <- file.path(
      runtime_paths()$aggregates_dir,
      resolution_name,
      paste0("city=", city_key),
      "aggregates.parquet"
    )
    runtime_cache[[cache_key]] <- arrow::read_parquet(path, as_data_frame = TRUE)
  }

  runtime_cache[[cache_key]]
}

species_choices_for_city <- function(city_key) {
  if (is.null(city_key) || identical(city_key, "")) {
    return(c("Select a city first" = ""))
  }

  tree_data <- load_city_tree_data(city_key)
  species_values <- sort(unique(stats::na.omit(as.character(tree_data$species_display))))
  c("All species" = "", stats::setNames(species_values, species_values))
}

filtered_city_tree_data <- function(city_key, species = "") {
  if (is.null(city_key) || identical(city_key, "")) {
    return(NULL)
  }

  tree_data <- load_city_tree_data(city_key)
  if (!is.null(species) && nzchar(species)) {
    tree_data <- tree_data[tree_data$species_display == species, , drop = FALSE]
  }

  tree_data
}

top_species_for_city <- function(city_key) {
  top_species <- load_city_top_species_data()
  top_species[top_species$city_key == city_key, , drop = FALSE]
}

city_points_sf <- function() {
  if (!exists("city_points_sf", envir = runtime_cache, inherits = FALSE)) {
    city_summary <- load_city_summary_data()
    runtime_cache$city_points_sf <- sf::st_as_sf(
      city_summary,
      coords = c("lon_center", "lat_center"),
      crs = 4326,
      remove = FALSE
    )
  }

  runtime_cache$city_points_sf
}

selected_city_sf <- function(city_key) {
  row <- get_city_summary_row(city_key)
  if (is.null(row)) {
    return(empty_point_sf(list(
      city_key = character(),
      city = character(),
      n_trees = numeric()
    )))
  }

  sf::st_as_sf(
    row,
    coords = c("lon_center", "lat_center"),
    crs = 4326,
    remove = FALSE
  )
}

aggregate_points_sf <- function(city_key, species = "", resolution_name = "medium") {
  if (is.null(city_key) || identical(city_key, "")) {
    return(empty_point_sf(list(
      city_key = character(),
      city = character(),
      count_trees = numeric(),
      count_species = numeric(),
      dominant_species = character()
    )))
  }

  aggregate_data <- load_city_aggregate_data(city_key, resolution_name = resolution_name)
  if (!is.null(species) && nzchar(species)) {
    aggregate_data <- aggregate_data[aggregate_data$dominant_species == species, , drop = FALSE]
  }

  if (nrow(aggregate_data) == 0) {
    return(empty_point_sf(list(
      city_key = character(),
      city = character(),
      count_trees = numeric(),
      count_species = numeric(),
      dominant_species = character()
    )))
  }

  sf::st_as_sf(
    aggregate_data,
    coords = c("lon_center", "lat_center"),
    crs = 4326,
    remove = FALSE
  )
}

tree_points_sf <- function(city_key, species = "", bbox = NULL, zoom_value = NULL, max_points = 30000L) {
  if (is.null(city_key) || identical(city_key, "")) {
    return(empty_point_sf(list(
      city_key = character(),
      city = character(),
      species_display = character()
    )))
  }

  tree_data <- filtered_city_tree_data(city_key, species = species)
  tree_data <- tree_data[tree_data$has_valid_coordinates, , drop = FALSE]

  if (!is.null(bbox)) {
    pad <- point_bbox_padding(zoom_value)
    tree_data <- tree_data[
      tree_data$longitude >= (bbox$xmin - pad) &
        tree_data$longitude <= (bbox$xmax + pad) &
        tree_data$latitude >= (bbox$ymin - pad) &
        tree_data$latitude <= (bbox$ymax + pad),
      ,
      drop = FALSE
    ]
  }

  if (nrow(tree_data) == 0) {
    return(empty_point_sf(list(
      city_key = character(),
      city = character(),
      species_display = character()
    )))
  }

  if (nrow(tree_data) > max_points) {
    step_idx <- unique(round(seq(1, nrow(tree_data), length.out = max_points)))
    tree_data <- tree_data[step_idx, , drop = FALSE]
  }

  sf::st_as_sf(
    tree_data,
    coords = c("longitude", "latitude"),
    crs = 4326,
    remove = FALSE
  )
}
