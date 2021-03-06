setup_graphs <- function(adjmats_all, aggfun = NULL, agg.rm.neg = TRUE, allowCache=TRUE, file_tag = file_tag, file_tag_nothresh = file_tag_nothresh, fc_out_rm = fc_outrm, ncpus=4) {
  #expects a subjects x ROIs x ROIs array OR list of density x ROIs x ROIs arrays (per subject) for dens.clime
  #creates igraph objects from adjacency matrix and label nodes V1, V2,...
  #looks up atlas from global environment
  suppressMessages(require(igraph))
  suppressMessages(require(foreach))
  suppressMessages(require(doSNOW))

  if(conn_method == "dens.clime_partial"){stopifnot(length(atlas$name) == length(adjmats_all[[1]][1,1,]))} else{
    stopifnot(length(atlas$name) == dim(adjmats_all)[2]) #number of nodes must match between atlas and adjmats
  }
  
  if(conn_method == "dens.clime_partial"){
    expectFile <- file.path(basedir, "cache", paste0("allg_", file_tag, ".RData"))
    if (file.exists(expectFile) && allowCache==TRUE) {
      message("Loading dens.clime weighted graph objects list from file: ", expectFile)
      load(expectFile)
    } else {
      
      allg <- lapply(adjmats_all, function(sub){
        sub_graphs <- apply(sub, 1, function(den){
          
          g <- graph.adjacency(den, mode = "undirected", weighted = TRUE, diag = FALSE)
          V(g)$name <- atlas$name
          
          #g <- tagGraph(g, atlas) #populate all attributes from atlas to vertices
          
          return(g)
        })
        return(sub_graphs)
      })
      
      #label allg graphs with subject IDs 
      for (sub in 1:length(allg)) { 
        for (den in 1:length(densities_desired))
          allg[[sub]][[den]]$id <- names(adjmats_all)[sub]
      }
      
      save(file = expectFile, allg)
    }
    
    expectFile <- file.path(basedir, "cache", paste0("weightedgraphsnoneg_", parcellation, "_", preproc_pipeline, "_", conn_method, ".RData"))
    if (file.exists(expectFile) && allowCache==TRUE) {
      message("Loading weighted non-negative graph objects from file: ", expectFile)
      load(expectFile)
    } else {
      
      ##remove negative correlations between nodes, if this is run on pearson, the number of edges remaining will be different across subjs 
      allg_noneg <- lapply(allg, function(sub) {
        sub_graphs <- lapply(sub, function(den){
          delete.edges(den, which(E(den)$weight < 0)) })
      })
      save(file=expectFile, allg_noneg) #save cache
    }
    
    #### Generate aggregate graph, defaults to mean of all adjmats with neg weights removed
    ridge.mean <- file.path(basedir, "cache", paste0("agg.g_", parcellation, "_", preproc_pipeline, "_ridge.net_partial.RData"))
    if (file.exists(ridge.mean)) {
      message("Loading aggregated ridge graph (DEFAULT MEAN + NO NEG) from file: ", ridge.mean)
      load(ridge.mean)
    } else {message("no agg.g to pull")}
        
  } else {
    
    ##create graph objects if inputted adjmats_all file is not a list of dens weighted graphs
    #### Setup basic weighted graphs if not dens.clime
    expectFile <- file.path(basedir, "cache", paste0("weightedgraphs_",file_tag_nothresh, ".RData"))
    if (file.exists(expectFile) && allowCache==TRUE) {
      message("Loading weighted graph objects from file: ", expectFile)
      load(expectFile)
    } else {
      
      allg <- apply(adjmats_all, 1, function(sub) {
        g <- graph.adjacency(sub, mode="undirected", weighted=TRUE, diag=FALSE)
        V(g)$name <- atlas$name
        browser()
        g <- tagGraph(g, atlas) #populate all attributes from atlas to vertices
        set_brainGraph_attr(g)
        return(g)
      })
      
      #add id to graphs
      for (i in 1:length(allg)) { allg[[i]]$id <- dimnames(adjmats_all)[["id"]][i] }
      save(file=expectFile, allg) #save cache
      
    }
    
    #### Setup weighted graphs, removing negative edges
    expectFile <- file.path(basedir, "cache", paste0("weightedgraphsnoneg_", file_tag_nothresh, ".RData"))
    if (file.exists(expectFile) && allowCache==TRUE) {
      message("Loading weighted non-negative graph objects from file: ", expectFile)
      load(expectFile)
    } else {
      ##remove negative correlations between nodes, if this is run on pearson, the number of edges remaining will be different across subjs 
      allg_noneg <- lapply(allg, function(g) { delete.edges(g, which(E(g)$weight < 0)) })
      save(file=expectFile, allg_noneg) #save cache
    }    
    
    #### Setup weighted graphs, removing negative edges
    expectFile <- file.path(basedir, "cache", paste0("weightedgraphsnopos_", file_tag_nothresh, ".RData"))
    if (file.exists(expectFile) && allowCache==TRUE) {
      message("Loading weighted negative edge graph objects from file: ", expectFile)
      load(expectFile)
    } else {
      ##remove positive correlations between nodes. Taking the absolute value of edges indicates for thresholding procedures that 
      allg_nopos <- lapply(allg, function(g) { delete.edges(g, which(E(g)$weight > 0)) })
      for(g in 1:length(allg_nopos)){
        E(allg_nopos[[g]])$weight <- abs(E(allg_nopos[[g]])$weight)
      }
      save(file=expectFile, allg_nopos) #save cache
    }
    
    # REMOVE FC OUTLIERS (2 of them in Ridge) ---------------------------------
    if(fc_out_rm == 1){

      subjs_outliers <- get_meanfc_outliers(allg_noneg)
      allg <- allg[-subjs_outliers]
      allg_noneg <- allg_noneg[-subjs_outliers]  
    }   
    
    # Mean Graph -----------------------------------------------
    
    #### Generate aggregate graph, defaults to mean of all adjmats with neg weights removed
    expectFile <- file.path(basedir, "cache", paste0("agg.g_", file_tag, ".RData"))
    expectFile_control <- file.path(basedir, "cache", paste0("agg.g_control_", file_tag, ".RData"))
    expectFile_bpd <- file.path(basedir, "cache", paste0("agg.g_bpd_", file_tag, ".RData"))
    if (file.exists(expectFile) && file.exists(expectFile_control) && file.exists(expectFile_bpd) && allowCache==TRUE) {
      message("Loading aggregated graphs (MEAN + NO NEG) from files: ", expectFile, " ", expectFile_bpd, " ", expectFile_control)
      load(expectFile); load(expectFile_bpd); load(expectFile_control)
    } else {
      agg.g <- generate_agg.g(allmats, rm.neg = agg.rm.neg)
      save(file=expectFile, agg.g) #save cache
      
      allmats_controls <- allmats[which(subj_info$BPD == 0),,]
      agg.g.controls <- generate_agg.g(allmats_controls, rm.neg = agg.rm.neg)
      save(file = expectFile_control, agg.g.controls)
      
      allmats_bpd <- allmats[which(subj_info$BPD == 1),,]
      agg.g.bpd <- generate_agg.g(allmats_bpd, rm.neg = agg.rm.neg)
      save(file = expectFile_bpd, agg.g.bpd)
    }
    
    # Proportional Thresholding -----------------------------------------------
    if(fc_out_rm == 1){
      expectFile <- file.path(basedir, "cache", paste0("dthreshgraphs_", file_tag, "_out_rm.RData"))
    } else {
      expectFile <- file.path(basedir, "cache", paste0("dthreshgraphs_", file_tag, ".RData"))
    }
    
    if (file.exists(expectFile) && allowCache==TRUE) {
      message("Loading proportional density-thresholded graph objects from file: ", expectFile)
      load(expectFile)
    } else {
      
      if(thresh_weighted == "binary") {
        allg_density <- threshold_glist(allg_noneg, densities_desired, method="density", ncores=1)
      } else {
        allg_density <- threshold_glist(allg_noneg, densities_desired, method="density", rmweights = FALSE, ncores=1)
      }
      
      #each element of allg_density is a list of 20 binary graphs for that subject at 1-20% density
      save(file=expectFile, allg_density)
    }
    
    # Threshold by FC value -------------------------------------------------
    if(fc_out_rm == 1){
      expectFile <- file.path(basedir, "cache", paste0("dthreshgraphs_", file_tag, "_out_rm_fc.RData"))
      expectFile_neg <-file.path(basedir, "cache", paste0("dthreshgraphs_", file_tag, "_neg_out_rm_fc.RData"))
    } else {
      expectFile <- file.path(basedir, "cache", paste0("dthreshgraphs_", file_tag, "_fc.RData"))
      expectFile_neg <- file.path(basedir, "cache", paste0("dthreshgraphs_", file_tag, "_neg_fc.RData"))
    }
    
    if (file.exists(expectFile) && allowCache==TRUE && file.exists(expectFile_neg)) {
      message("Loading FC thresholded graph objects from files: ", expectFile, " and ", expectFile_neg)
      load(expectFile)
      load(expectFile_neg)
    } else {      
      if(thresh_weighted == "binary"){
        allg_density_fc <- threshold_glist(allg_noneg, rs_desired_log, method="strength", ncores=1)
        allg_density_fc_neg <- threshold_glist(allg_nopos, rs_desired_log, method="strength", ncores=1)
      } else {
        allg_density_fc <- threshold_glist(allg_noneg, rs_desired_log, method="strength", rmweights = FALSE, ncores=1)
        allg_density_fc_neg <- threshold_glist(allg_nopos, rs_desired_log, method="strength", rmweights = FALSE, ncores=1) #don't you need different cutoffs for negative connections, which are weak?
      }
      
      save(allg_density_fc, file = expectFile)
      save(allg_density_fc_neg, file = expectFile_neg)
    } 
    
  }
  
  return(list(allg=allg, allg_noneg=allg_noneg, allg_density=allg_density, agg.g = agg.g, allg_density_fc = allg_density_fc, agg.g.bpd = agg.g.bpd, agg.g.controls = agg.g.controls, allg_nopos = allg_nopos, allg_density_fc_neg = allg_density_fc_neg))
}
