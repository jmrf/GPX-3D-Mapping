# Libraries and helpers ----
library(elevatr)
library(rayshader)
library(imager)
library(rgl)
library(raster)
library(plotKML)
library(dplyr)
library(magick)

source("helpers/arcgis_map_api.R")
source("helpers/image_size.R")

# Setup and functions ----
options(rgl.printRglwidget = FALSE)

# Convert lat and long to rayshader grid coordinates
xvec <- function(lon) {
  xmin <- elev_img@extent@xmin
  xmin_vec <- rep(xmin, length(gpx$lon))
  (lon - xmin_vec[length(lon)]) / res(elev_img)[1]
}
yvec <- function(lat) {
  ymin <- elev_img@extent@ymin
  ymin_vec <- rep(ymin, length(gpx$lat))
  (lat - ymin_vec[length(lat)]) / res(elev_img)[2]
}

# Convert lat and on to image pixel coordinates
lon2x <- function(lon) {
  xmax <- dim(elev_matrix)[1]
  lon_min <- elev_img@extent@xmin
  lon_max <- elev_img@extent@xmax
  r <- xmax / (lon_max - lon_min)
  round((lon - lon_min) * r)
}

lat2y <- function(lat) {
  ymax <- dim(elev_matrix)[2]
  lat_min <- elev_img@extent@ymin
  lat_max <- elev_img@extent@ymax
  r <- ymax / (lat_max - lat_min)
  round(ymax - (lat - lat_min) * r) # in an image (0, 0) is at the top!
}

add_label <- function(lon, lat, text, color) {
  render_label(
    elev_matrix,
    x = lon2x(lon),
    y = lat2y(lat),
    z = 200,
    zscale = zscale, textsize = 20, linewidth = 4,
    text = text,
    linecolor = color,
    textcolor = color,
    freetype = FALSE
  )
}


# Read gpx file path from input ----
# Alternatively, read from input:
# > input_gpx_file <- readline("Introduce GPX input path.\t")
args <- commandArgs(TRUE)
input_gpx_file <- args[1]
print(sprintf("Reading GPX file: %s", input_gpx_file))

# Retrieve route and elevation data ----
gpx.df <- readGPX(input_gpx_file)
gpx <- gpx.df$tracks |>
  unlist(recursive = FALSE) |>
  as.data.frame()


# Convert column classes
gpx_ncols <- length(colnames(gpx))
if (gpx_ncols == 5) {
  colnames(gpx) <- c("lon", "lat", "ele", "time", "temp")
} else if (gpx_ncols == 4) {
  colnames(gpx) <- c("lon", "lat", "ele", "time")
} else {
  print(sprintf("Incompatible number of columns detected (%d).", gpx_ncols))
  quit(status = 1)
}
print("Done reading GPX file!")
gpx[1:3] <- as.numeric(unlist(gpx[1:3]))

# Find Bounding Box
max_bbox_diff <- max(
  max(gpx$lat) - min(gpx$lat),
  max(gpx$lon) - min(gpx$lon)
)

lat_min <- min(gpx$lat) * 0.9999
lat_max <- max(gpx$lat) * 1.0001
long_min <- min(gpx$lon) * 0.999
long_max <- max(gpx$lon) * 1.001

# Get elevation data of bounding box, borrowed from
# https://github.com/edeaster/Routes3D/blob/master/3D-map_gps_route.R
location.df <- data.frame(
  x = c(long_min, long_max),
  y = c(lat_min, lat_max)
)

prj_dd <- "+proj=longlat +ellps=WGS84 +datum=WGS84 +no_defs"
elev_img <- get_elev_raster(
  location.df,
  prj = prj_dd,
  z = 12,
  clip = "bbox",
  src = "aws"
)
elev_tif <- raster::writeRaster(elev_img, "Track/elevation.tif", overwrite = TRUE)
elev_dim <- dim(elev_tif)

# elevation matrix from the Raster
elev_matrix <- matrix(
  raster::extract(elev_img, raster::extent(elev_img), buffer = 1000),
  nrow = ncol(elev_img),
  ncol = nrow(elev_img)
)

# # Create overlay from satellite image ----
img_bbox <- list(
  p1 = list(long = long_max, lat = lat_min),
  p2 = list(long = long_min, lat = lat_max)
)

image_size <- define_image_size(img_bbox, 1200)
overlay_img <- get_arcgis_map_image(
  img_bbox,
  map_type = "World_Imagery", # "World_Topo_Map" OR "World_Imagery"
  width = image_size$width,
  height = image_size$height
) |> png::readPNG()

# Create the 3D Map ----

# # Calculate rayshader layers using elevation data
# ambmat <- ambient_shade(elev_matrix, zscale = 8)
# raymat <- ray_shade(elev_matrix, zscale = 8, lambert = TRUE)

# Create RGL object and plot
zscale <- 10
rgl::clear3d()

elev_matrix |>
  sphere_shade(texture = "imhof4") |>
  add_overlay(overlay = overlay_img, alphalayer = 0.9) |>
  # add_shadow(raymat, max_darken = 0.5, rescale_original = TRUE) |>
  # add_shadow(ambmat, max_darken = 0.5, rescale_original = TRUE) |>
  plot_3d(
    elev_matrix,
    zscale = zscale,
    zoom = 0.5,
    fov = 70,
    theta = 80,
    phi = 25,
    windowsize = c(1850, 1040)
  )

# Plot labels on the 3D Map ----
n_points <- length(gpx$lat)

# Start Label
add_label(gpx$lon[1], gpx$lat[1], "START", "green")
# End Label
add_label(gpx$lon[n_points - 1], gpx$lat[n_points - 1], "END", "blue")
# Top Label
top_point <- gpx[gpx$ele == max(gpx$ele),][1,]
add_label(top_point$lon, top_point$lat, "TOP", "yellow")
# Bottom Label
low_point <- gpx[gpx$ele == min(gpx$ele),][1,]
add_label(low_point$lon, low_point$lat, "LOW", "yellow")


# Progressive track rendering  ------
dir.create("Track")
prev_wd <- getwd()
setwd("Track")

# Initializes the progress bar
n_iter <- 120
chunk_size <- ceiling(n_points / n_iter)

pb <- txtProgressBar(
  min = 0, # Minimum value of the progress bar
  max = n_iter, # Maximum value of the progress bar
  style = 3, # Progress bar style (also available style = 1 and style = 2)
  width = 50, # Progress bar width. Defaults to getOption("width")
  char = "=" # Character used to create the bar
)

# Camera movements, borrowed from
# https://www.rdocumentation.org/packages/rayshader/versions/0.11.5/topics/render_movie

# Azimuth (anticlockwise) angle:
phivec <- rep_len(60, length.out = n_iter)
# Alternatively:
# phivechalf <- 60 / (1 + exp(seq(-7, 0, length.out = ceiling(n_iter / 2))) / 2)
# phivec <- c(phivechalf, rev(phivechalf))

# Scene rotation angle:
# thetavec <- -90 + 60 * sin(seq(0, 359, length.out = n_iter) * pi / 180)
thetavec <- seq(0, 359, length.out = n_iter) # One entire circle around the scene

# Zoom:
# Here we use a constant zoom, alternatively:
# > zoomvechalf <- 0.35 + 0.2 * 1 / (1 + exp(seq(-5, 20, length.out = ceiling(n_iter / 2))))
# > zoomvec <- c(zoomvechalf, rev(zoomvechalf))
zoomvec <- rep_len(0.55, length.out = n_iter)

# Get the route 3D points
x <- xvec(gpx$lon) - dim(elev_matrix)[1] / 2
y <- yvec(gpx$lat) - dim(elev_matrix)[2] / 2
z <- gpx$ele / (0.97 * zscale)

for (i in 1:n_iter) {
  p_range <- 1:(chunk_size * i) # get a chunk of track points
  rgl::lines3d(
    x[p_range],
    z[p_range],
    -y[p_range],
    color = "orange",
    lwd = 4,
    smooth = TRUE,
    add = TRUE
  )
  render_camera(
    theta = thetavec[i],
    phi = phivec[i],
    zoom = zoomvec[i],
    fov = 50
  )
  rgl::snapshot3d(paste0(sprintf("%02d.png", i)))
  rgl.pop(id = rgl.ids()$id |> max())

  # Sets the progress bar to the current state
  setTxtProgressBar(pb, i)
}

# To plot the entire track:
rgl::lines3d(x, z, -y, color = "orange", add = TRUE, lwd = 4)

setwd(prev_wd)
