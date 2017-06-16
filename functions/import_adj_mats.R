#use caching
import_adj_mats <- function(subj_info, allowCache=TRUE, rmShort=NULL) {
  #NB. several variables are (implicitly) pulled from the global environment here:
  #   nnodes, parcellation, conn_method, basedir
  #Whether this is optimal programming is open to debate

  stopifnot(file.exists(file.path(basedir, "cache")))
  expectFile <- file.path(basedir, "cache", paste0("adjmats_", parcellation, "_", preproc_pipeline, "_", conn_method, ".RData"))
  if (file.exists(expectFile) && allowCache==TRUE) {
    message("Loading raw adjacency matrices from file: ", expectFile)
    load(expectFile)
  } else {
    #either the cached file doesn't exist, or we've been asked not to accept it (allowCache=FALSE)

    ##preallocate empty array to read adjacency matrices into
    allmats <- array(NA, c(nrow(subj_info), nnodes, nnodes), 
                     dimnames=list(id = subj_info$SPECC_ID, roi1=paste0("V", 1:nnodes), roi2=paste0("V", 1:nnodes)))
    
    sep=ifelse(conn_method=="scotmi", ",", "") #for use in read.table command

    for (f in 1:nrow(subj_info)) {
      m <- as.matrix(read.table(as.character(subj_info[f,"file"]), sep=sep, header=FALSE))
      if (conn_method=="scotmi") {
        m <- rbind(array(NaN, ncol(m)), m) #append a NaN vector onto first row (omitted from SCoTMI output)
        m[upper.tri(m)] <- t(m)[upper.tri(m)] #populate upper triangle for symmetry
      }
      allmats[f,,] <- m
    }
    
    #remove short distance connections using 0/1 matrix passed in
    if (!is.null(rmShort)) {
      message("Zeroing ", sum(rmShort[lower.tri(rmShort)] == 0), " connections less than ", roi.dist, "mm from raw adjacency matrices. ")

      #apply the short-range removal by replicating the 2D rmShort to a 3D array of the same size as
      #allmats, then elementwise multiplication (since this is vectorized and fast)
      rmtest <- aperm(replicate(n=dim(allmats)[1], rmShort), c(3,1,2))
      allmats <- allmats * rmtest
      
      #slightly different tack using abind to create array (not faster)
      #system.time(rmtest2 <- do.call(abind, list(along=0, replicate(n=dim(allmats)[1], rmShort, simplify=FALSE))))
      
      #interesting approach using afill from the abind package, but not really faster than above
      #rmtest <- array(NA, dim=dim(allmats), dimnames=dimnames(allmats))
      #dimnames(rmShort) <- dimnames(allmats)[c(2,3)]
      #system.time(afill(rmtest,TRUE,,) <- rmShort)
      
      #plyr aaply keeps the dimensions intact, but is slow
      #allmats <- plyr::aaply(allmats, 1, function(m) { m <- m * rmShort; return(m) }))
      
      #basic apply over rows, apply(allmats, 1), throws away array dimensions and dimnames
    }
    
    save(allmats, file=expectFile) #cache results
  }
  
  #return 3d array to caller
  return(allmats)
}