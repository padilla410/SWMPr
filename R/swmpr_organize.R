######
#' QAQC filtering for data obtained from retrieval functions, local and remote
#'
#' @param swmpr_in input swmpr object
#' @param qaqc_keep numeric vector of qaqc flags to keep, default \code{0}
#' @param trace logical for progress output on console, default \code{F}
#' 
#' @return Returns a swmpr object with \code{NA} values for records that did not match \code{qaqc_keep}.  QAQC columns are also removed.
qaqc <- function(x, ...) UseMethod('qaqc')
qaqc.swmpr <- function(swmpr_in, 
  qaqc_keep = 0,
  trace = F){
  
  ##
  # sanity checks
  if(!class(qaqc_keep) %in% c('numeric', 'NULL'))
    stop('qaqc_in argument must be numeric or NULL')
  
  ##
  # swmpr data and attributes
  dat <- swmpr_in$station_data
  qaqc_cols <- attr(swmpr_in, 'qaqc_cols')
  station <- attr(swmpr_in, 'station')
  
  # exit function if no qaqc columns
  if(!qaqc_cols){
    warning('No qaqc columns in input data')
    return(swmpr_in)
    }
  
  ##
  #remove values flagged by QA/QC, see cdmo website for flag numbers

  if(trace) cat('Processing QAQC columns...')
  
  #names of qaqc columns
  qaqc_sel <- grep('f_', names(dat), value = T)
  
  qaqc_rm <- as.numeric(seq(-5,  5))
  qaqc_rm <- qaqc_rm[!qaqc_rm %in% qaqc_keep]
  
  # keep all if qaqc_in is NULL, otherwise process qaqc
  if(is.null(qaqc_keep)){ 
    
    rm_col <- c('datetimestamp', 'statparam', qaqc_sel)
    qaqc <- dat[, !names(dat) %in% rm_col]

  } else {
      
    #matrix of TF values for those that don't pass qaqc
    qaqc_vec <- dat[, names(dat) %in% qaqc_sel, drop = F]
    qaqc_vec <- apply(qaqc_vec, 2, 
      function(x) grepl(paste(qaqc_rm, collapse = '|'), x)
      )
    #replace T values with NA
    #qaqc is corrected
    qaqc_sel <- gsub('f_', '', qaqc_sel)
    qaqc <- dat[, names(dat) %in% qaqc_sel, drop = F]
    qaqc <- data.frame(sapply(
      names(qaqc),
      function(x){
        out <- qaqc[, x]
        out[qaqc_vec[, paste0('f_',x)]] <- NA
        out
        },
      USE.NAMES = T
      ), stringsAsFactors = F)
    
    }
   
  ##
  # addl misc processing
  
  #combine with datetimestamp and append to output list
  out <- data.frame(datetimestamp = dat[,1], qaqc)
  
  #remove duplicate time stamps (some minutely), do not use aggregate
  out<-out[!duplicated(out$datetimestamp),]  
    
	#convert columns to numeric, missing converted to NA
	#NA values from qaqc still included as NA
	out <- data.frame(
    datetimestamp = out[,1],
    apply(out[, -1, drop = F], 2 , as.numeric)
    )

  # create swmpr class
  out <- swmpr(out, station)
  
  # return output
  if(trace) cat('\n\nQAQC processed...')
  return(out)

}

######
#' Subset a swmpr object by a date range, parameters, or non-empty values
#' 
#' @param subset is chr string of form 'YYYY-mm-dd HH:MM'
#' @param select chr string of parameters to keep
#' @param operator chr string specifiying binary operator (e.g., \code{'>'}, \code{'<='}) if subset is one date value
#' @param rem_rows logical indicating if rows with no data are removed, default \code{F}
#' @param rem_cols is logical indicating if cols with no data are removed, default \code{F}
#' 
#' @return Returns a swmpr object as a subset of the input.  The original object will be returned if no arguments are specified.
subset.swmpr <- function(swmpr_in, subset = NULL, select = NULL, 
  operator = NULL, rem_rows = F, rem_cols = F){
  
  ##
  # swmpr data and attributes
  dat <- swmpr_in$station_data
  station <- attr(swmpr_in, 'station')
  timezone <- attr(swmpr_in, 'timezone')
  parameters <- attr(swmpr_in, 'parameters')
  qaqc_cols <- attr(swmpr_in, 'qaqc_cols')
  stamp_class <- attr(swmpr_in, 'stamp_class')
  
  ##
  # subset
  
  # create posix object from subset input
  date_sel <- rep(T, nrow(dat)) # created based on subset arg
  if(!is.null(subset)){

    subset <- as.POSIXct(subset, format = '%Y-%m-%d %H:%M', tz = timezone)
    
    # convert subset to date if input datetimestamp is date
    if('Date' %in% stamp_class)
      subset <- as.Date(subset, tz = timezone)
    
    # exit function of subset input is incorrect format
    if(any(is.na(subset))) 
      stop('subset must be of format %Y-%m-%d %H:%M')
    
    # exit function if operator not provided for one subset value
    if(length(subset) == 1){
      
      if(is.null(operator))
        stop('Binary operator must be included if only one subset value is provided')
      
      date_sel <- outer(dat$datetimestamp, subset, operator)[, 1]
     
    # for two datetime values...
    } else {
      
      date_sel <- with(dat, datetimestamp >= subset[1] & datetimestamp <= subset[2])
      
      }

    }
  
  # exit function if date_sel has no matches
  if(sum(date_sel) == 0)
    stop('No records matching subset criteria')
  
  # columns to select, includes qaqc cols if present
  # all if null
  if(is.null(select)) select <- names(dat)
  else select <- names(dat)[names(dat) %in% c('datetimestamp', select, paste0('f_', select))]
  
  # subset data
  out <- subset(dat, date_sel, select)
  out <- data.frame(out, row.names = 1:nrow(out))
  
  ##
  # remove empty rows
  if(rem_rows){
    
    # get vector of rows that are empty
    col_sel <- grepl(paste(parameters, collapse = '|'), names(out))
    check_empty <- t(apply(as.matrix(out[, col_sel, drop = F]), 1, is.na))
    if(nrow(check_empty) == 1) check_empty <- matrix(check_empty)
    check_empty <- rowSums(check_empty) == ncol(check_empty)
    
    # remove empty rows
    out <- out[!check_empty, , drop = F]
    
    if(nrow(out) == 0) stop('All data removed, select different parameters')
    
    out <- data.frame(out, row.names = 1:nrow(out))
    
    }
  
  ##
  # remove empty columns
  if(rem_cols){

    # get vector of empty columns
    check_empty <- colSums(apply(out, 2, is.na)) == nrow(out)

    # make sure qaqc columns match parameter columns if present
    if(qaqc_cols){
      
      rem_vals <- check_empty[names(check_empty) %in% parameters]
      check_empty[names(check_empty) %in% paste0('f_', parameters)] <- rem_vals
      
      }
    
    # subset output
    out <- out[, !check_empty, drop = F]
    
    if(ncol(out) == 1) stop('All data removed, select different parameters')
    
    }
  
  # create swmpr class
  out <- swmpr(out, station)
  
  # return output
  return(out)
  
}

######
#' Create a continuous time vector at set time step for a swmpr object
#' 
#' @param swmpr_in input swmpr object
#' @param timestep numeric value of time step to use in minutes
#' @param differ numeric value defining buffer for merging time stamps to standardized time series
#' 
#' @return Returns a swmpr object for the specified time step
setstep <- function(x, ...) UseMethod('setstep')
setstep.swmpr <- function(swmpr_in, timestep = 30, differ= timestep/2){ 
  
  # swmpr data and attributes
  dat <- swmpr_in$station_data
  attrs <- attributes(swmpr_in)
  
  # sanity check
  if(timestep/2 < differ) 
    stop('Value for differ must be less than one half of timestep')
  if('Date' %in% attrs$stamp_class) 
    stop('Cannot use setstep with date class')
  
  # round to nearest timestep
  dts_std <- as.POSIXct(
    round(as.double(attrs$date_rng)/(timestep * 60)) * (timestep * 60),
    origin = '1970-01-01',
    tz = attrs$timezone
    )
    
  # create continuous vector
  dts_std <- seq(dts_std[1], dts_std[2], by = timestep * 60)
  dts_std <- data.frame(datetimestamp = dts_std)
  
  # convert swmpr data and standardized vector to data.table for merge
  # time_dum is vector of original times for removing outside of differ
  mrg_dat <- dat
  mrg_dat$time_dum <- mrg_dat$datetimestamp
  mrg_dat <- data.table(mrg_dat, key = 'datetimestamp')
  mrg_std <- data.table(dts_std, key = 'datetimestamp')
  
  # merge all the data  using  mrg_std as master
  mrg <- mrg_dat[mrg_std, roll = 'nearest']
  mrg <- data.frame(mrg)
  
  # set values outside of differ to NA
  time_diff <- abs(difftime(mrg$datetimestamp, mrg$time_dum, units='secs'))
  time_diff <- time_diff >= 60 * differ
  mrg[time_diff, !names(mrg) %in% c('datetimestamp', 'time_dum')] <- NA
  
  # output, back to swmpr object from data.table
  out <- data.frame(mrg)
  out <- out[, !names(out) %in% 'time_dum']
  out <- swmpr(out, attrs$station)
  
  return(out)

} 

######
#' Combine swmpr data types for a station by common time series
#' 
#' @param timestep numeric value of time step to use in minutes, passed to \code{setstep}
#' @param differ numeric value defining buffer for merging time stamps to standardized time series, passed to \code{setstep}
#' @param method chr string indicating method of combining (\code{'union'} for all dates as continuous time series, \code{'intersect'} for areas of overlap, or \code{'station'} for a given station)
#' 
#' @return Returns a combined swmpr object
comb <- function(...) UseMethod('comb')
comb.swmpr <- function(..., timestep = 30, differ= 5, method = 'union'){
  
  # swmp objects list and attributes
  all_dat <- list(...)
  attrs <- llply(all_dat, attributes)
  
  ##
  # sanity checks
  if(length(all_dat) == 1)
    stop('Input data must include more than one swmpr object')
  
  # stop if from more than one timezone
  timezone <- unique(unlist(llply(attrs, function(x) x$timezone)))
    
  if(length(timezone) > 1)
    stop('Input data are from multiple timezones')
  
  # stop of method is invalid
  stations <- unlist(llply(attrs, function(x) x$station))
  
  if(!method %in% c('intersect', 'union', stations))
    stop('Method must be intersect, union, or station name')

  # stop if more than one data type
  types <- unlist(llply(attrs, function(x) substring(x$station, 6)))
  
  if(any(duplicated(types))) 
    stop('Unable to combine duplicated data types')
  
  ##
  # setstep applied to data before combining
  all_dat <- llply(all_dat, setstep, timestep, differ)
  
  ##
  # dates
  date_vecs <- llply(all_dat, function(x) x[[1]]$datetimestamp)
  
  ## 
  # date vector for combining
  # for union, intersect
  if(method %in% c('union', 'intersect')){
    
    date_vec <- Reduce(method, date_vecs)
    date_vec <- as.POSIXct(date_vec, origin = '1970-01-01', tz = timezone)
    
  # for a station
  } else {
    
    sel <- unlist(llply(attrs, function(x) x$station == method))
    
    date_vec <- date_vecs[sel][[1]]
    
  }
    
  ##
  # merge stations by date_vec
  out <- data.table(datetimestamp = date_vec, key = 'datetimestamp')
  
  for(dat in all_dat){
    
    dat <- data.table(dat$station_data, key = 'datetimestamp')
    
    # merge
    out <- dat[out, roll = 'nearest']
 
    }

  # format as swmpr object, return
  out <- data.frame(out)
  out <- swmpr(out, stations)
  
  return(out)
  
}