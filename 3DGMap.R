library(elevatr)
library(rayshader)
library(imager)
library(ggmap)
library(XML)
library(sp)
library(rgl)
library(raster)
library(plyr)
library(magick)


# ---------------------- SETUP -----------------
options(rgl.printRglwidget = TRUE)

# Google Maps API
gmaps_key <-Sys.getenv(x="GMAPS_KEY")

if (gmaps_key == "") {
  stop("Missing Google Maps API key. Please set the 'GMAPS_KEY' env.var")
  
}
register_google(key=gmaps_key, day_limit = 2)
dir.create('Images')


# Get Elevation, Latitude, and Longitude in a dataframe from gpx file
input_gpx_file <- readline("Introduce GPX input path.\t")
print(sprintf("Reading GPX file: %s", input_gpx_file))

gpx.raw <- xmlTreeParse(input_gpx_file, useInternalNodes = TRUE)
rootNode <- xmlRoot(gpx.raw)
gpx.rawlist <- xmlToList(rootNode)$trk
gpx.list <- unlist(gpx.rawlist[names(gpx.rawlist) == "trkseg"], recursive = FALSE)
gpx <- do.call(rbind.fill, lapply(gpx.list, 
                                  function(x) as.data.frame(t(unlist(x)), 
                                                            stringsAsFactors=F)))

# names(gpx) <- c("time","ele", "hr", "temp", "lat", "lon")
names(gpx) <- c("ele", "time", "temp", "lat", "lon")

# Convert strings to numbers
gpx$ele <- as.numeric(gpx$ele)
gpx$temp <- as.numeric(gpx$temp)
gpx$lat <- as.numeric(gpx$lat)
gpx$lon <- as.numeric(gpx$lon)

gpx$time <- sub("T", " ", gpx$time)
gpx$time <- sub("\\+00:00","", gpx$time)
gpx$time  <- as.POSIXlt(gpx$time)


gpx <- gpx[,c("time","temp","lon","lat","ele")]

lat_min <- min(gpx$lat)
lat_max <- max(gpx$lat)
long_min <- min(gpx$lon)
long_max <- max(gpx$lon)

print(sprintf("Lat (min:%f, max:%f) | Long (min:%f, max:%f)", 
              lat_min, lat_max, 
              long_min, long_max))

# Get elevation data
elevation_tif_file <- "Images/elevation.tif"

ex.df <- data.frame(x=c(long_min, long_max), y=c(lat_min,lat_max))
prj_dd <- "+proj=longlat +ellps=WGS84 +datum=WGS84 +no_defs"
elev_img <- get_elev_raster(ex.df, prj = prj_dd, z = 12, clip = "bbox")
elev_tif <- raster::writeRaster(elev_img, elevation_tif_file, overwrite=TRUE)
dim <- dim(elev_tif)
elev_matrix <- matrix(
      raster::extract(elev_img, raster::extent(elev_img), buffer = 1000),
      nrow = ncol(elev_img), ncol = nrow(elev_img)
)

# Get overlay image from Google maps.
# To know more: https://developers.google.com/maps/documentation
long_cen <- (((long_max - long_min)/2) + long_min)
lat_cen <- ((lat_max - lat_min)/2)+ lat_min
mt_mit_map <- get_googlemap(center = c(lon= long_cen , lat = lat_cen), 
                            zoom = 12,
                            maptype = "satellite", 
                            color = "color")

# Plot overlay image and crop to the correct dimensions
overlay_file <- "Images/overlay_image.png"
png(overlay_file, 
    width=dim[2], height=dim[1], 
    units= "px",type = "cairo-png")

ggmap(mt_mit_map)+
      scale_x_continuous(limits = c(long_min, long_max), expand = c(0, 0)) +
      scale_y_continuous(limits = c(lat_min, lat_max), expand = c(0, 0)) +
      theme(axis.line = element_blank(),
            axis.text = element_blank(),
            axis.ticks = element_blank(),
            plot.margin = unit(c(0, 0, -1, -1), 'lines')) +
      xlab('') +
      ylab('')

dev.off()

# Edit Image
image <- image_read(overlay_file)
green<- image_colorize(image=image,"#08c72e", opacity = 2 )
yellow <- image_colorize(image=green,"#eaf518", opacity = 6 )
contrast<- image_contrast(yellow, sharpen = 10)
final <- image_modulate(contrast, brightness = 120)
image_write(final, path = overlay_file)

overlay_img <- png::readPNG(overlay_file)

# Calculate rayshader layers
ambmat <- ambient_shade(elev_matrix, zscale = 8)
raymat <- ray_shade(elev_matrix, zscale = 8, lambert = TRUE)
watermap <- detect_water(elev_matrix, zscale = 8)

# Create the 3D Map
zscale <- 7
rgl::clear3d()
elev_matrix |>
      sphere_shade(texture = "imhof4") |>
      add_water(watermap, color = "imhof4") |>
      add_overlay(overlay_img, alphalayer = .9) |>
      add_shadow(raymat, max_darken = 0.5, rescale_original = TRUE) |>
      # add_shadow(t(ambmat), max_darken = 0.5, rescale_original = TRUE) |>
      plot_3d(elev_matrix, zscale=7, xlab='x', ylab='y', zlab='z', decorate=TRUE)

# render_snapshot("Images/3D_map_overlay.png")

# Convert lat and long to rayshader grid
xmin <- elev_img@extent@xmin
ymin <- elev_img@extent@ymin

adj_x <- dim(elev_matrix)[1] / 2
adj_y = dim(elev_matrix)[2] / 2
xmin_vec <- rep(xmin, length(gpx$lon))
ymin_vec <- rep(ymin, length(gpx$lat))
x <- (gpx$lon-xmin_vec) / res(elev_img)[1] - adj_x
y <- (gpx$lat-ymin_vec) / res(elev_img)[2] - adj_y
z <- extract(elev_img, gpx[,c(3, 4)]) / (zscale-.08)


max_z_idx <- which.max(z)
max_px <- x[max_z_idx]
max_py <- y[max_z_idx]
render_label(elev_matrix, 
             x=max_px, 
             y=-max_py, 
             z=max(z), 
             zscale = 7, 
             textsize = 20, 
             linewidth = 4, 
             text = "UP!", 
             freetype = FALSE)

# Plot the route in 3D
rgl::lines3d(x, z, -y, color = "red", add=TRUE)
rglwidget()
