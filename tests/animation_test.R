library("rgl")


# SETUP -----
# Temporary dir setup
# tmpdir <- tempdir()
tmpdir <- './Track'
print(sprintf("Saving results in: %s", tmpdir))


# Initializes the progress bar
n_iter <- 45
pb <- txtProgressBar(
  min = 0, # Minimum value of the progress bar
  max = n_iter, # Maximum value of the progress bar
  style = 3, # Progress bar style (also available style = 1 and style = 2)
  width = 50, # Progress bar width. Defaults to getOption("width")
  char = "="
) # Character used to create the bar


# 3D Drawing ----
shade3d(oh3d(), color = "red")
rgl.bringtotop()

view3d(0, 20)

# Generation -----
olddir <- getwd()
setwd(tmpdir)

for (i in 1:n_iter) {
  view3d(i, 20)
  filename <- paste("pic", formatC(i, digits = 1, flag = "0"), ".png", sep = "")
  
  # print(sprintf("Saving file to: %s", filename))
  snapshot3d(filename, webshot = as.logical(Sys.getenv("RGL_USE_WEBSHOT", "FALSE")))

  # Sets the progress bar to the current state
  setTxtProgressBar(pb, i)
}

setwd(olddir)
