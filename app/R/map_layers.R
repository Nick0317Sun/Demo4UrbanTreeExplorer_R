default_map_widget <- function(style_url) {
  city_sf <- city_points_sf()
  city_marker_source <- "city-points"
  selected_city_source <- "selected-city"
  aggregate_source <- "selected-aggregates"
  point_source <- "selected-points"
  nation <- national_view()
  zoom_rules <- map_zoom_rules()

  mapgl::maplibre(
    style = style_url,
    center = nation$center,
    zoom = nation$zoom,
    projection = "mercator",
    pitch = 0,
    bearing = 0
  ) |>
    mapgl::add_navigation_control() |>
    mapgl::add_source(city_marker_source, city_sf) |>
    mapgl::add_circle_layer(
      id = "city-circles",
      source = city_marker_source,
      circle_color = "#2c8b53",
      circle_opacity = 0.72,
      circle_radius = city_marker_radius_expr(),
      circle_stroke_color = "#f7fbf4",
      circle_stroke_width = 1.1
    ) |>
    mapgl::add_symbol_layer(
      id = "city-labels",
      source = city_marker_source,
      text_field = mapgl::get_column("city"),
      text_size = 12,
      text_color = "#203126",
      text_halo_color = "#f7fbf4",
      text_halo_width = 1.2,
      text_allow_overlap = FALSE,
      min_zoom = zoom_rules$city_label_min
    ) |>
    mapgl::add_source(
      selected_city_source,
      empty_point_sf(list(city_key = character(), city = character(), n_trees = numeric()))
    ) |>
    mapgl::add_circle_layer(
      id = "selected-city-ring",
      source = selected_city_source,
      circle_color = "#ffffff",
      circle_opacity = 0.15,
      circle_radius = 12,
      circle_stroke_color = "#0e5a35",
      circle_stroke_width = 2.2,
      visibility = "none"
    ) |>
    mapgl::add_source(
      aggregate_source,
      empty_point_sf(list(
        city_key = character(),
        city = character(),
        count_trees = numeric(),
        count_species = numeric(),
        dominant_species = character()
      ))
    ) |>
    mapgl::add_circle_layer(
      id = "selected-aggregate-glow",
      source = aggregate_source,
      circle_color = "#6cab71",
      circle_opacity = zoom_interpolate_expr(
        stops = c(8.6, 10.2, 12.0, 12.7, 13.4),
        values = c(0.16, 0.12, 0.08, 0.04, 0.0)
      ),
      circle_blur = zoom_interpolate_expr(
        stops = c(8.6, 10.2, 12.0, 13.0),
        values = c(0.9, 0.7, 0.48, 0.28)
      ),
      circle_radius = zoom_interpolate_expr(
        stops = c(8.6, 10.2, 12.0, 13.0),
        values = c(18, 13, 8, 5)
      ),
      min_zoom = zoom_rules$aggregate_min,
      visibility = "none"
    ) |>
    mapgl::add_circle_layer(
      id = "selected-aggregate-circles",
      source = aggregate_source,
      circle_color = "#3a7f4d",
      circle_opacity = zoom_interpolate_expr(
        stops = c(8.6, 10.2, 12.0, 12.7, 13.4),
        values = c(0.22, 0.18, 0.12, 0.06, 0.0)
      ),
      circle_blur = zoom_interpolate_expr(
        stops = c(8.6, 10.2, 12.0, 13.0),
        values = c(0.4, 0.28, 0.16, 0.08)
      ),
      circle_radius = zoom_interpolate_expr(
        stops = c(8.6, 10.2, 12.0, 13.0),
        values = c(9, 7, 4.8, 3.3)
      ),
      min_zoom = zoom_rules$aggregate_min,
      visibility = "none"
    ) |>
    mapgl::add_source(
      point_source,
      empty_point_sf(list(
        city_key = character(),
        city = character(),
        species_display = character()
      ))
    ) |>
    mapgl::add_circle_layer(
      id = "selected-tree-points",
      source = point_source,
      circle_color = "#1f6b42",
      circle_opacity = zoom_interpolate_expr(
        stops = c(12.5, 12.8, 13.4, 15.0),
        values = c(0.0, 0.24, 0.55, 0.82)
      ),
      circle_radius = zoom_interpolate_expr(
        stops = c(12.7, 13.4, 15.0),
        values = c(1.2, 1.7, 2.4)
      ),
      circle_stroke_color = "#eaf4e9",
      circle_stroke_width = zoom_interpolate_expr(
        stops = c(12.7, 14.0, 15.0),
        values = c(0.2, 0.35, 0.5)
      ),
      min_zoom = zoom_rules$point_min,
      visibility = "none"
    )
}

update_selected_city_map <- function(city_key, species = "", zoom_value = NULL, bbox = NULL) {
  proxy <- mapgl::maplibre_proxy("main_map")
  has_city <- !is.null(city_key) && nzchar(city_key)
  zoom_rules <- map_zoom_rules()
  aggregate_visibility <- if (has_city) "visible" else "none"
  city_ring_visibility <- if (has_city) "visible" else "none"
  point_visibility <- if (has_city && !is.null(zoom_value) && zoom_value >= zoom_rules$point_min) "visible" else "none"
  aggregate_resolution <- aggregate_resolution_for_zoom(zoom_value)
  aggregate_sf <- aggregate_points_sf(city_key, species = species, resolution_name = aggregate_resolution)
  point_sf <- if (point_visibility == "visible") {
    tree_points_sf(city_key, species = species, bbox = bbox, zoom_value = zoom_value)
  } else {
    empty_point_sf(list(
      city_key = character(),
      city = character(),
      species_display = character()
    ))
  }

  proxy |>
    mapgl::set_source("selected-city-ring", selected_city_sf(city_key)) |>
    mapgl::set_source("selected-aggregate-glow", aggregate_sf) |>
    mapgl::set_source("selected-aggregate-circles", aggregate_sf) |>
    mapgl::set_source("selected-tree-points", point_sf) |>
    mapgl::set_layout_property("selected-city-ring", "visibility", city_ring_visibility) |>
    mapgl::set_layout_property("selected-aggregate-glow", "visibility", aggregate_visibility) |>
    mapgl::set_layout_property("selected-aggregate-circles", "visibility", aggregate_visibility) |>
    mapgl::set_layout_property("selected-tree-points", "visibility", point_visibility)

  invisible(proxy)
}

focus_map_for_city_selection <- function(city_key) {
  proxy <- mapgl::maplibre_proxy("main_map")
  city_row <- get_city_summary_row(city_key)

  if (is.null(city_row)) {
    nation <- national_view()
    proxy |>
      mapgl::fly_to(center = nation$center, zoom = nation$zoom)
  } else {
    proxy |>
      mapgl::fly_to(
        center = c(city_row$lon_center[[1]], city_row$lat_center[[1]]),
        zoom = city_row$default_zoom[[1]]
      )
  }

  invisible(proxy)
}
