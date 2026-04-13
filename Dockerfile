FROM rocker/r-ver:4.4.3

ENV DEBIAN_FRONTEND=noninteractive
ENV PORT=7860
ENV HOST=0.0.0.0

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    g++ \
    gcc \
    make \
    cmake \
    ninja-build \
    gdal-bin \
    libbz2-dev \
    libcurl4-openssl-dev \
    libfontconfig1-dev \
    libfreetype6-dev \
    libfribidi-dev \
    libgdal-dev \
    libgeos-dev \
    libharfbuzz-dev \
    libicu-dev \
    liblzma-dev \
    libproj-dev \
    libsnappy-dev \
    libssl-dev \
    libudunits2-dev \
    libxml2-dev \
    libzstd-dev \
    zlib1g-dev \
  && rm -rf /var/lib/apt/lists/*

RUN which R && R --version

RUN R -q -e "install.packages(c('arrow','bslib','dplyr','ellmer','ggplot2','httr2','jsonlite','mapgl','promises','scales','sf','shiny','tibble'), repos = 'https://cloud.r-project.org', Ncpus = max(1L, parallel::detectCores() - 1L))"

WORKDIR /app

COPY app ./app
COPY data_processed ./data_processed
COPY README.md ./README.md

EXPOSE 7860

CMD ["R", "-q", "-e", "shiny::runApp('app', host = Sys.getenv('HOST', '0.0.0.0'), port = as.integer(Sys.getenv('PORT', '7860')), launch.browser = FALSE)"]
