#'Zoon: A package for comparing multple SDM models, good model diagnostics
#'      and better reproducibility
#'@name zoon
#'@docType package

NULL



# ~~~~~~~~~~~~
# define the modules for each module type



# ~~~~~~~~~~~~
# occurrence modules



#'occurrence module to grab *Culex rajah* (a mosquito) occurrence (i.e.
#'       presence-only) data from GBIF, in the area bounded by extent.
#'       Perhaps this should have temporal interval too for future-proofing?
#'
#'@param extent A numeric vetor of length 4 giving the coordinates of the 
#'       rectangular region within which to carry out the analysis, in the 
#'       order: xmin, xmax, ymin, ymax.
#'
#'@return a dataframe with four columns:
#'       value - a numeric value which may give 1 for presences, 0 for absences 
#'       or a positive integer for count data
#'       type - a character value saying what is in the value column
#'       lon - the longitude of the record
#'       lat - the latitutude of the record
#'
#'@name occurrenceCp
#'@export


occurrenceCp <- function (extent) {
  require (dismo)
  
  raw <- gbif(genus = 'Anopheles',
              species = 'plumbeus',
              ext = extent)
  
  occurrence <- raw[, c('lon', 'lat')]
  
  occurrence$value <- 1
  
  occurrence$type <- 'presence'
  
  return(occurrence)
}

# ~~~~~~~~~~~~
# covariate modules


#'covariate module to grab a coarse resolution mean air temperature raster from
#'       January-February 2001-2002 for the given extent.
#'
#'@param extent A numeric vector of length 4 giving the coordinates of the 
#'      rectangular region within which to carry out the analysis, in the 
#'      order: xmin, xmax, ymin, ymax.
#'
#'@return a Raster* object (class from the raster package) with the gridded
#'      covariates used to train and predict from the SDM.
#'
#'@name covariateAir
#'@export


covariateAir <- function (extent) {
  require(RNCEP)
  
  c1 <- NCEP.gather(variable = 'air',
                    level = 850,
                    months.minmax = c(1:2),
                    years.minmax = c(2000,2001),
                    lat.southnorth = extent[3:4],
                    lon.westeast = extent[1:2],
                    reanalysis2 = FALSE,
                    return.units = TRUE)
  
  avg <- apply(c1, c(1, 2), mean)
  
  ras <- raster(avg)
  
  extent(ras) <- c(extent)
  
  return (ras)  
  
}

# ~~~~~~~~~~~~
# process modules


#'process module to generate up to 100 background records at random in
#'      cells of ras and return these along with the ppresence only data.
#'
#'@param occ Occurrence data, the output from an occurrence module
#'@param ras Covariate data, the output from a covariate module
#'
#'@return Dataframe with at least 5 columns
#'       value - a numeric value which may give 1 for presences, 0 for absences 
#'       or a positive integer for count data
#'       type - a character value saying what is in the value column
#'       lon - the longitude of the record
#'       lat - the latitutude of the record
#'       columns 5-n - the values of the covariates for each records (the names of
#'               these columns should correspond exactly to the names of the 
#'               layers in ras)
#'@name processA
#'@export


processA <- function (occ, ras) {
  
  require (dismo)
  
  if (!all(occ$type == 'presence')) {
    stop ('this function only works for presence-only data')
  }
  
  # generate pseudo-absence data
  pa <- randomPoints(ras,
                     100)
  
  
  npres <- nrow(occ)
  
  npabs <- nrow(pa)
  
  # extract covariates
  occ_covs <- as.matrix(extract(ras, occ[, c('lon', 'lat')]))
  
  pa_covs <- as.matrix(extract(ras, pa))
  
  covs <- rbind(occ_covs,
                pa_covs)
  
  # combine with the occurrence data
  df <- data.frame(value = rep(c(1, 0),
                               c(npres, npabs)),
                   type = rep(c('presence', 'background'),
                              c(npres, npabs)),
                   lon = c(occ$lon, pa[, 1]),
                   lat = c(occ$lat, pa[, 2]),
                   covs)
  
  names(df)[5:ncol(df)] <- names(ras)
  
  return(df)
  
}

# ~~~~~~~~~~~~
# model modules
#  note that the current set up only works for models with a predict method
#  which takes the argument: type = 'response'
#  obviously we'll have to work around that.

#' model module to fit a simple logistic regression model
#'
#'@param df A dataframe, the output from a process module
#'
#'@return A model object with a valid predict method
#'
#'@name modelLR
#'@export

modelLR <- function (df) {
  if (!all(df$type %in% c('presence', 'absence', 'background'))) {
    stop ('only for presence/absence or presence/background data')
  }
  
  covs <- as.data.frame(df[, 5:ncol(df)])
  names(covs) <- names(df)[5:ncol(df)]
  m <- glm(df$value ~ .,
           data = covs,
           family = binomial)
  
  return (m)
}

#' model module to fit a simple RandomForest classification model
#'
#'@param df A dataframe, the output from a process module
#'
#'@return A model object with a valid predict method
#'
#'@name modelRF
#'@export



modelRF <- function (df) {
  
  require ('randomForest')
  
  if (!all(df$type %in% c('presence', 'absence', 'background'))) {
    stop ('only for presence/absence or presence/background data')
  }
  
  covs <- as.data.frame(df[, 5:ncol(df)])
  names(covs) <- names(df)[5:ncol(df)]
  m <- randomForest(df$value ~ .,
                    data = covs,
                    weights = rep(1, nrow(covs)),
                    size = 1)
  
  return (m)
}

# ~~~~~~~~~~~~
# map modules


#' A function for outputing the raster of the predictions from an analysis
#'
#'@param model A model object, the output from a model module
#'@param ras A Raster* object, the output from a covariate module
#'
#'@return A Raster object giving the probabilistic model predictions for each
#'      cell of ras
#'
#'@name mapA
#'@export

mapA <- function (model, ras) {
  
  vals <- data.frame(getValues(ras))
  colnames(vals) <- names(ras)
  
  pred <- predict(model,
                  newdata = vals,
                  type = 'response')
  
  pred_ras <- ras[[1]]
  
  pred_ras <- setValues(pred_ras, pred)
  
  return(pred_ras)
  
}
