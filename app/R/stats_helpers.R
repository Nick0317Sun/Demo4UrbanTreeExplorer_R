build_city_stats <- function(city_key, species = "") {
  city_row <- get_city_summary_row(city_key)
  if (is.null(city_row)) {
    return(list(
      city_label = "National view",
      total_trees = sum(load_city_summary_data()$n_trees),
      species_count = nrow(load_city_summary_data()),
      species_label = "Cities",
      top_species = "Select a city to view local stats.",
      selected_species = NULL,
      selected_species_trees = NULL
    ))
  }

  filtered_data <- filtered_city_tree_data(city_key, species = species)
  top_species <- top_species_for_city(city_key)

  stats <- list(
    city_label = paste0(city_row$city[[1]], ", ", city_row$state[[1]]),
    total_trees = if (nzchar(species)) nrow(filtered_data) else city_row$n_trees[[1]],
    species_count = if (nzchar(species)) 1 else city_row$n_species[[1]],
    species_label = if (nzchar(species)) "Filtered" else "Species",
    top_species = city_row$top_species_1[[1]] %||% "Unavailable",
    selected_species = if (nzchar(species)) species else NULL,
    selected_species_trees = if (nzchar(species)) nrow(filtered_data) else NULL
  )

  stats
}

species_chart_data <- function(city_key) {
  top_species_for_city(city_key)
}

build_species_chart <- function(city_key, species = "") {
  top_species <- species_chart_data(city_key)
  if (nrow(top_species) == 0) {
    return(NULL)
  }

  chart_data <- top_species
  chart_data$species_display <- factor(
    chart_data$species_display,
    levels = rev(chart_data$species_display)
  )

  chart_data$fill_group <- if (nzchar(species) && species %in% as.character(chart_data$species_display)) {
    ifelse(as.character(chart_data$species_display) == species, "selected", "default")
  } else {
    "default"
  }

  subtitle <- if (nzchar(species) && !species %in% as.character(top_species$species_display)) {
    paste0(species, " is outside the current top 10.")
  } else {
    NULL
  }

  ggplot2::ggplot(chart_data, ggplot2::aes(x = species_display, y = tree_count, fill = fill_group)) +
    ggplot2::geom_col(width = 0.72, color = NA) +
    ggplot2::scale_fill_manual(values = c(default = "#88b78f", selected = "#205f3c"), guide = "none") +
    ggplot2::scale_y_continuous(labels = scales::label_number(big.mark = ",")) +
    ggplot2::labs(
      title = "Top 10 species",
      subtitle = subtitle,
      x = NULL,
      y = NULL
    ) +
    ggplot2::theme_minimal(base_family = "sans") +
    ggplot2::theme(
      plot.background = ggplot2::element_rect(fill = "transparent", color = NA),
      panel.background = ggplot2::element_rect(fill = "transparent", color = NA),
      panel.grid.major.y = ggplot2::element_line(color = "#dfe8dd"),
      panel.grid.major.x = ggplot2::element_blank(),
      axis.text.y = ggplot2::element_text(size = 9, color = "#27402f"),
      axis.text.x = ggplot2::element_blank(),
      axis.ticks = ggplot2::element_blank(),
      plot.title = ggplot2::element_text(size = 12, face = "bold", color = "#203126"),
      plot.subtitle = ggplot2::element_text(size = 9, color = "#587060"),
      plot.margin = ggplot2::margin(6, 6, 6, 6)
    ) +
    ggplot2::coord_flip()
}
