# Libraries and functions -------------------------------------------------
library(elevatr)
library(rayshader)
library(imager)
library(rgl)
library(raster)
library(plotKML)
library(dplyr)
library(magick)

source("arcgis_map_api.R")
source("image_size.R")

# Setup and functions -------------------------------------------------------
options(rgl.printRglwidget = TRUE)

# Convert lat and long to rayshader grid coordinates
xvec <- function(x) {
  xmin <- elev_img@extent@xmin
  xmin_vec <- rep(xmin, length(gpx$lon))
  (x - xmin_vec[length(x)]) / res(elev_img)[1]
}
yvec <- function(x) {
  ymin <- elev_img@extent@ymin
  ymin_vec <- rep(ymin, length(gpx$lat))
  (x - ymin_vec[length(x)]) / res(elev_img)[2]
}

# Retrieve route and elevation data -----------------------------------------

input_gpx_file <- readline("Introduce GPX input path.\t")
print(sprintf("Reading GPX file: %s", input_gpx_file))

gpx.df <- readGPX(input_gpx_file)
gpx <- gpx.df$tracks |>
  unlist(recursive = FALSE) |>
  as.data.frame()


# Convert column classes
gpx[1:3] <- as.numeric(unlist(gpx[1:3]))
colnames(gpx) <- c("lon", "lat", "ele", "time", "temp")

# Find Bounding Box
lat_min <- min(gpx$lat) * 0.999
lat_max <- max(gpx$lat) * 1.001
long_min <- min(gpx$lon) * 0.999
long_max <- max(gpx$lon) * 1.001

# Get elevation data of bounding box, borrowed from
# https://github.com/edeaster/Routes3D/blob/master/3D-map_gps_route.R
ex.df <- data.frame(
  x = c(long_min, long_max),
  y = c(lat_min, lat_max)
)

prj_dd <- "+proj=longlat +ellps=WGS84 +datum=WGS84 +no_defs"
elev_img <-
  get_elev_raster(ex.df,
    prj = prj_dd,
    z = 12,
    clip = "bbox"
  )
elev_tif <- raster::writeRaster(elev_img, "elevation.tif", overwrite = TRUE)

elev_dim <- dim(elev_tif)
elev_matrix <- matrix(
  raster::extract(elev_img, raster::extent(elev_img), buffer = 1000),
  nrow = ncol(elev_img),
  ncol = nrow(elev_img)
)

# Create Overlay ----
bbox <- list(
  p1 = list(long = long_max, lat = lat_min),
  p2 = list(long = long_min, lat = lat_max)
)

# Create overlay from satellite image ------------------------------------
image_size <- define_image_size(bbox, 1200)
overlay_img <- get_arcgis_map_image(
  bbox,
  map_type = "World_Imagery",
  width = image_size$width,
  height = image_size$height
) |> png::readPNG()

# Create the 3D Map -------------------------------------------------------

# Calculate rayshader layers using elevation data
ambmat <- ambient_shade(elev_matrix, zscale = 8)
raymat <- ray_shade(elev_matrix, zscale = 8, lambert = TRUE)

# Create RGL object
rgl::clear3d()

elev_matrix |>
  sphere_shade(texture = "imhof4") |>
  add_overlay(overlay_img, alphalayer = 0.9) |>
  add_shadow(raymat, max_darken = 0.5, rescale_original = TRUE) |>
  add_shadow(t(ambmat),
    max_darken = 0.5,
    rescale_original = TRUE
  ) |>
  plot_3d(
    elev_matrix,
    zscale = 10,
    zoom = 0.5,
    fov = 70,
    theta = 80,
    phi = 25,
    windowsize = c(1850, 1040)
  )

# # Plot labels on the 3D Map
# render_label(elev_matrix, x = xvec(gpx$lon[1]), y = yvec(gpx$lat[1]), z = 1200, zscale = 10, textsize = 20, linewidth = 4, text = "Start", freetype = FALSE)
# render_label(elev_matrix, x = xvec(12.495658), y = yvec(47.157745), z = 1200, zscale = 10, textsize = 40, linewidth = 4, text = "St Poltner Hutte", freetype = FALSE)
# render_label(elev_matrix, x = xvec(12.392638), y = yvec(47.123220), z = 800, zscale = 10, textsize = 20, linewidth = 4, text = "Neue Prager Hutte", freetype = FALSE)
# render_label(elev_matrix, x = xvec(12.345676), y = yvec(47.109409), z = 600, zscale = 10, textsize = 20, linewidth = 4, text = "Grossvenediger", freetype = FALSE)

# Add track and animate ---------------------------------------------------

# Plot the route in 3D
x <- xvec(gpx$lon) - dim(elev_matrix)[1] / 2
y <- yvec(gpx$lat) - dim(elev_matrix)[2] / 2
z <- gpx$ele / (10 - .05)

# Camera movements, borrowed from
# https://www.rdocumentation.org/packages/rayshader/versions/0.11.5/topics/render_movie
phivechalf <- 60 * 1 / (1 + exp(seq(-7, 20, length.out = 180) / 2))  # original: 30 + 60 * 1 / (1 + exp(seq(-7, 20, length.out = 180) / 2))
phivecfull <- c(phivechalf, rev(phivechalf))
thetavec <- -90 + 60 * sin(seq(0, 359, length.out = 360) * pi / 180)
zoomvec <- 0.35 + 0.2 * 1 / (1 + exp(seq(-5, 20, length.out = 180)))
zoomvecfull <- c(zoomvec, rev(zoomvec))

# Progressive track rendering  ------
dir.create("Track")

prev_wd <- getwd()
setwd("Track")

# Initializes the progress bar
n_iter <- 36
pb <- txtProgressBar(
  min = 0, # Minimum value of the progress bar
  max = n_iter, # Maximum value of the progress bar
  style = 3, # Progress bar style (also available style = 1 and style = 2)
  width = 50, # Progress bar width. Defaults to getOption("width")
  char = "="
) # Character used to create the bar


n_points <- length(gpx$lat)
for (i in 1:n_iter) {
  p_range <- 1:ceiling((n_points / 360) * i * 10)  # why this? x[1:ceiling((1555 / 360) * i)]
  rgl::lines3d(
    x[p_range],
    z[p_range],
    -y[p_range],
    color = "red",
    lwd = 4,
    smooth = T,
    add = T
  )
  render_camera(
    theta = thetavec[i],
    phi = phivecfull[i],
    zoom = zoomvecfull[i],
    fov = 50
  )
  rgl::snapshot3d(paste0(sprintf("%02d.png", i)))
  rgl.pop(id = rgl.ids()$id |> max())
  
  # Sets the progress bar to the current state
  setTxtProgressBar(pb, i)
}

# To plot the entire track: 
rgl::lines3d(x, z, -y, color='red', add=TRUE)

setwd(prev_wd)
