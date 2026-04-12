app_theme <- function() {
  bslib::bs_theme(
    version = 5,
    bg = "#edf2ea",
    fg = "#203126",
    primary = "#2e7d4f",
    secondary = "#7f917f",
    base_font = bslib::font_google("Public Sans"),
    heading_font = bslib::font_google("Manrope")
  )
}

project_root <- function() {
  candidates <- c(
    normalizePath(getwd(), winslash = "/", mustWork = FALSE),
    normalizePath(file.path(getwd(), ".."), winslash = "/", mustWork = FALSE),
    normalizePath(file.path(getwd(), "..", ".."), winslash = "/", mustWork = FALSE)
  )

  for (candidate in unique(candidates[file.exists(candidates)])) {
    if (dir.exists(file.path(candidate, "app")) && dir.exists(file.path(candidate, "data_processed"))) {
      return(candidate)
    }
  }

  stop("Unable to locate the project root from the current working directory.")
}

processed_root <- function() {
  file.path(project_root(), "data_processed")
}

runtime_paths <- function() {
  root <- processed_root()
  list(
    city_summary = file.path(root, "city_summary.parquet"),
    city_top_species = file.path(root, "metadata", "city_top_species.parquet"),
    trees_dir = file.path(root, "trees"),
    aggregates_dir = file.path(root, "aggregates")
  )
}

national_view <- function() {
  list(center = c(-98.5795, 39.8283), zoom = 3.35)
}

map_zoom_rules <- function() {
  list(
    city_label_min = 4.8,
    aggregate_min = 8.6,
    aggregate_medium = 10.2,
    aggregate_fine = 12.0,
    point_min = 12.7
  )
}

city_marker_radius_expr <- function() {
  mapgl::step_expr(
    column = "n_trees",
    base = 3.2,
    values = c(25000, 100000, 300000),
    stops = c(4.3, 5.6, 7.1)
  )
}

aggregate_radius_expr <- function() {
  mapgl::step_expr(
    column = "count_trees",
    base = 2.5,
    values = c(10, 25, 75, 200),
    stops = c(3.5, 5, 7.5, 10.5)
  )
}

zoom_interpolate_expr <- function(stops, values, type = "linear") {
  expr <- list("interpolate", list(type), list("zoom"))
  for (i in seq_along(stops)) {
    expr <- c(expr, list(stops[[i]], values[[i]]))
  }
  expr
}

aggregate_resolution_for_zoom <- function(zoom_value) {
  rules <- map_zoom_rules()
  zoom_value <- zoom_value %||% national_view()$zoom

  if (zoom_value >= rules$aggregate_fine) {
    "fine"
  } else if (zoom_value >= rules$aggregate_medium) {
    "medium"
  } else {
    "coarse"
  }
}

point_bbox_padding <- function(zoom_value) {
  if (is.null(zoom_value) || is.na(zoom_value)) {
    return(0.003)
  }

  if (zoom_value >= 14) {
    0.0015
  } else if (zoom_value >= 13.2) {
    0.0025
  } else {
    0.0035
  }
}

rounded_bbox_key <- function(bbox, zoom_value = NULL) {
  if (is.null(bbox)) {
    return("no_bbox")
  }

  digits <- if (is.null(zoom_value) || is.na(zoom_value)) {
    3L
  } else if (zoom_value >= 13.5) {
    4L
  } else if (zoom_value >= 11) {
    3L
  } else {
    2L
  }

  paste(
    round(bbox$xmin, digits),
    round(bbox$ymin, digits),
    round(bbox$xmax, digits),
    round(bbox$ymax, digits),
    sep = ":"
  )
}

rounded_center_key <- function(center, zoom_value = NULL) {
  if (is.null(center) || is.null(center$lng) || is.null(center$lat)) {
    return("no_center")
  }

  digits <- if (is.null(zoom_value) || is.na(zoom_value)) {
    3L
  } else if (zoom_value >= 13.5) {
    4L
  } else {
    3L
  }

  paste(round(center$lng, digits), round(center$lat, digits), sep = ":")
}

zoom_bucket <- function(zoom_value) {
  rules <- map_zoom_rules()
  zoom_value <- zoom_value %||% national_view()$zoom

  if (zoom_value >= rules$point_min) {
    "points"
  } else if (zoom_value >= rules$aggregate_fine) {
    "aggregate_fine"
  } else if (zoom_value >= rules$aggregate_medium) {
    "aggregate_medium"
  } else if (zoom_value >= rules$aggregate_min) {
    "aggregate_coarse"
  } else {
    "national"
  }
}

map_content_signature <- function(selected_city, species, zoom_value, bbox = NULL, center = NULL) {
  bucket <- zoom_bucket(zoom_value)
  paste(
    selected_city %||% "",
    species %||% "",
    bucket,
    if (identical(bucket, "national")) "national_bbox" else rounded_bbox_key(bbox, zoom_value),
    if (identical(bucket, "national")) "national_center" else rounded_center_key(center, zoom_value),
    sep = "|"
  )
}

basemap_options <- function() {
  c(
    "Light / Plain" = mapgl::carto_style("positron"),
    "Minimal Gray" = mapgl::openfreemap_style("positron"),
    "Detailed Streets" = mapgl::carto_style("voyager")
  )
}

format_count <- function(x) {
  formatC(x %||% 0, format = "d", big.mark = ",")
}

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || all(is.na(x))) {
    y
  } else {
    x
  }
}

empty_point_sf <- function(columns = list()) {
  data <- as.data.frame(columns, stringsAsFactors = FALSE)
  data$geometry <- sf::st_sfc(crs = 4326)
  sf::st_as_sf(data)
}
