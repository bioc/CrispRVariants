# readsToTarget generic -----
#'@title Trims reads to a target region.
#'@description Trims aligned reads to one or several target regions,
#'optionally reverse complementing the alignments.
#'@param reads A GAlignments object, or a character vector of the filenames
#'@param target A GRanges object specifying the range to narrow alignments to
#'@author Helen Lindsay
#'@rdname readsToTarget
#'
#'@import methods
#'@import BiocParallel
#'@import Biostrings
#'@import ggplot2
#'@import GenomicAlignments
#'@import GenomicRanges
#'@import IRanges
#'@import Rsamtools
#'@import S4Vectors
#'@importFrom grDevices colorRampPalette
#'@importFrom grid gpar grid.rect
#'@importFrom gridExtra grid.arrange arrangeGrob
#'@importFrom reshape2 melt
#'@importFrom AnnotationDbi select
#'@importFrom GenomeInfoDb seqlengths
#'@importFrom utils modifyList
#'@export
setGeneric("readsToTarget", function(reads, target, ...) {
  standardGeneric("readsToTarget")})
# -----

# readsToTarget GAlignments, GRanges -----
#'@param name An experiment name for the reads.  (Default: NULL)
#'@param reverse.complement (Default: TRUE)  Should the alignments be
#' oriented to match the strand of the target? If TRUE, targets located 
#  on the postive strand are displayed with respect to the postive 
#' strand and targets on the negative strand with respect to the 
#' negative strand. If FALSE, the parameter 'orientation' must be set
#' to determine the orientation.  
#' 'reverse.complement' will be replaced by 'orientation' in a later release. 
#'@param collapse.pairs  If reads are paired, should pairs be collapsed? 
#' (Default: FALSE) Note: only collapses primary alignments, 
#' and assumes that there is only one primary alignment per read.
# May fail with blat alignments converted to bam.
#'@param use.consensus Take the consensus sequence for non-matching pairs? If FALSE,
#'the sequence of the first read is used.  Can be very slow. (Default: FALSE)
#'@param store.chimeras Should chimeric reads be stored?  (Default: FALSE)
#'@param orientation One of "target" (reads are displayed on the same
#' strand as the target) "opposite" (reads are displayed on the opposite)
#' strand from the target or "positive" (reads are displayed on the forward
#' strand regardless of the strand of the target)   (Default:"target") 
#'@param verbose Print progress and statistics (Default: TRUE)
#'@param minoverlap Minimum number of bases the aligned read must 
#' share with the target site.  If not specified, the aligned
#' read must completely span the target region.  (Default: NULL)
#'@return (signature("GAlignments", "GRanges")) A \code{\link{CrisprRun}} object
#'@examples
#'# Load the metadata table
#'md_fname <- system.file("extdata", "gol_F1_metadata_small.txt", package = "CrispRVariants")
#'md <- read.table(md_fname, sep = "\t", stringsAsFactors = FALSE)
#'
#'# Get bam filenames and their full paths
#'bam_fnames <- sapply(md$bam.filename, function(fn){
#'  system.file("extdata", fn, package = "CrispRVariants")})
#'
#'reference <- Biostrings::DNAString("GGTCTCTCGCAGGATGTTGCTGG")
#'gd <- GenomicRanges::GRanges("18", IRanges::IRanges(4647377, 4647399),
#'        strand = "+")
#'
#'crispr_set <- readsToTarget(bam_fnames, target = gd, reference = reference,
#'                            names = md$experiment.name, target.loc = 17)
#'
#'@rdname readsToTarget
setMethod("readsToTarget", signature("GAlignments", "GRanges"),
          function(reads, target, ..., reverse.complement = TRUE,
                   chimeras = NULL, collapse.pairs = FALSE,
                   use.consensus = FALSE, store.chimeras = FALSE, 
                   verbose = TRUE, name = NULL, minoverlap = NULL,
                   orientation = c("target","opposite","positive")){

    orientation <- match.arg(orientation)
    dots <- list(...)
    
    # If calling directly rather than internally, run checks
    if (! "checked" %in% names(dots) & isTRUE(dots$checked)){
      .checkReadsToTarget(target, reference = NULL, target.loc = NULL,
                          reverse.complement, orientation,
                          chimeras)
      .checkForPaired(reads)
    }

    keep.unpaired <- TRUE
    if ("keep.unpaired" %in% names(dots)){
        keep.unpaired <- dots["keep.unpaired"]
    }
    
    # Choose which strand to orient reads to
    if (isTRUE(reverse.complement) & as.character(strand(target)) == "*"){
      message(paste0("Target does not have a strand, ",
                     "but reverse.complement is TRUE.\n",
                     "Orienting reads to reference strand."))
      rc = FALSE
    } else {
      rc <- rcAlns(as.character(strand(target)), orientation)
    }
    
    # If there are no non-chimeric reads, chimeras can still be stored
    if (length(reads) == 0){
      if (length(chimeras) == 0) {return(NULL)}
      crun <- CrisprRun(reads, target, rc = rc,
                        name = name, chimeras = chimeras, 
                        verbose = verbose)
      return(crun)
    }

    # Check if alignments are paired and should be collapsed
    if (isTRUE(collapse.pairs)){
      if (is.null(names(reads)) | ! ("flag" %in% names(mcols(reads))) ){
        stop("Reads must include names and bam flags for collapsing pairs")
      }
    }

    if (is.null(chimeras)) {
      chimeras <- GenomicAlignments::GAlignments()
      if (isTRUE(store.chimeras)) {
        # There is no way to specify tolerance here, or to use target.loc
        temp <- separateChimeras(reads, target, by.flag = collapse.pairs,
                                 verbose = verbose)
        reads <- temp$bam
        chimeras <- temp$chimeras[[1]]
      }
    }

    # To do: check whether this is redundant with narrowAlignments
    # Filter out reads that don't span the target region
    # Not using findOverlaps because reads may be paired, i.e. names nonunique
    if (is.null(minoverlap)){
      bam <- reads[start(reads) <= start(target) & end(reads) >= end(target) &
                   seqnames(reads) == as.character(seqnames(target))]
    } else { bam <- reads }

    if (isTRUE(verbose)){
      message(sprintf("%s of %s nonchimeric reads span the target range\n",
                  length(bam), length(reads)))
    }

    # If bam and chimeras are empty, no further calculation needed
    if (length(bam) == 0 & length(chimeras) == 0) return(NULL)

    if (length(bam) == 0){
      crun <- CrisprRun(bam, target, rc = rc,
                  name = name, chimeras = chimeras, verbose = verbose)
      return(crun)
    }

    # If bam is non-empty, orient and narrow the reads to the target

    # narrow aligned reads
    result <- narrowAlignments(bam, target, reverse.complement = rc,
                            verbose = verbose, minoverlap = minoverlap)
    
    # Collapse pairs of narrowed reads

    if (isTRUE(collapse.pairs)){
      gen_ranges <- GenomicAlignments::cigarRangesAlongReferenceSpace(
                       cigar(result), pos = start(result))
      
      result <- collapsePairs(result, genome.ranges = gen_ranges,
                              use.consensus = use.consensus,
                              keep.unpaired = keep.unpaired, verbose = verbose)

      result <- result$alignments
    }

    if (length(result) == 0){
      if (length(chimeras) == 0){
        return(NULL)
      }
      crun <- CrisprRun(result, target, rc = rc, name = name,
                        chimeras = chimeras, verbose = verbose)
      return(crun)
    }

    crun <- CrisprRun(result, target, rc = rc, name = name,
                      chimeras = chimeras, verbose = verbose)
    crun
}) # -----


# readsToTarget GAlignmentsList, GRanges -----
#'@rdname readsToTarget
setMethod("readsToTarget", signature("GAlignmentsList", "GRanges"),
          function(reads, target, ..., reference = reference,
                   names = NULL, reverse.complement = TRUE, target.loc = 17,
                   chimeras = NULL, collapse.pairs = FALSE, use.consensus = FALSE,
                   orientation = c("target","opposite","positive"),
                   minoverlap = NULL, verbose = TRUE){

    # To do: Deal with potentially empty chimeras

    orientation <- match.arg(orientation)
    
    # Always run checks as this function is not called by others
    .checkReadsToTarget(target, reference = NULL, target.loc = NULL,
                        reverse.complement, orientation,
                        chimeras)
    
    # Check: if chimeras and reads are supplied, they should have equal length
    nch <- length(chimeras)
    nreads <- length(reads)
    
    if (nreads > 0 & nch > 0 & ! nreads == nch){
      stop("Chimeras must be either NULL or a GAlignmentsList ",
           "of length equal to reads")
    }

    # Collapse pairs if required and initialise CrisprSet object
    cset <- alnsToCrisprSet(reads, reference, target, reverse.complement,
                            collapse.pairs, names, use.consensus, target.loc,
                            verbose, chimeras = chimeras, minoverlap = minoverlap,
                            orientation = orientation, checked = TRUE, ...)
    
    cset
}) # -----


# readsToTarget character, GRanges -----
#'@param names Experiment names for each bam file.  If not supplied, filenames are used.
#'@param chimeras Flag to determine how chimeric reads are treated.  One of
#'"ignore", "exclude", and "merge".  Default "count", "merge" not implemented yet
#'@param reference The reference sequence
#'@param exclude.ranges Ranges to exclude from consideration, e.g. homologous to a pcr primer.
#'@param exclude.names Alignment names to exclude
#'@param ... Extra arguments for initialising CrisprSet
#'@return (signature("character", "GRanges")) A \code{\link{CrisprSet}} object
#'@rdname readsToTarget
setMethod("readsToTarget", signature("character", "GRanges"),
          function(reads, target, ..., reference, reverse.complement = TRUE,
                   target.loc = 17, exclude.ranges = GRanges(), exclude.names = NA,
                   chimeras = c("count","exclude","ignore", "merge"),
                   collapse.pairs = FALSE, use.consensus = FALSE,
                   orientation = c("target","opposite","positive"),
                   names = NULL, minoverlap = NULL, verbose = TRUE){

    # Prepare input parameters
    args <- list(...)
    chimeras <- match.arg(chimeras)
    orientation <- match.arg(orientation)
    
    # If reading in alignments, always run checks
    .checkFnamesExist(reads)
    .checkReadsToTarget(target, reference, target.loc,
                        reverse.complement, orientation, chimeras)
            
    if (! is(reference, "DNAString")){
      reference <- Biostrings::DNAString(reference[[1]])
    }
    
    c_to_t <- 5
    if ("chimera.to.target" %in% names(args)){
       c_to_t <- args[["chimera.to.target"]]
    }
       
    # Read in the bam files, separate chimeric and non-chimeric reads
    temp <- lapply(reads, readTargetBam, target = target,
                   exclude.ranges = exclude.ranges,
                   exclude.names = exclude.names,
                   chimeras = chimeras, by.flag = collapse.pairs,
                   chimera.to.target = c_to_t,
                   verbose = verbose)

    alns <- lapply(temp, "[[", "bam")
    chimeras <- lapply(temp, "[[", "chimeras")

    # If names are not specified, set them to the filenames
    if (is.null(names)){
       names <- basename(reads)
    }
    names <- as.character(names)

    # Collapse pairs, count insertions, create CrisprSet objects
    cset <- alnsToCrisprSet(alns, reference, target, reverse.complement,
                            collapse.pairs, names = names,
                            use.consensus = use.consensus,
                            target.loc = target.loc, verbose = verbose,
                            chimeras = chimeras, minoverlap = minoverlap,
                            orientation = orientation, checked = TRUE, ...)
     cset
}) # -----

#__________________________________________________________________
# readsToTargets (for alignments to multiple guides)
#__________________________________________________________________
# readsToTargets -----
#'@export
#'@rdname readsToTarget
setGeneric("readsToTargets", function(reads, targets, ...) {
  standardGeneric("readsToTargets")})

#'@param targets A set of targets to narrow reads to
#'@param references A set of reference sequences matching the targets.
#'References for negative strand targets should be on the negative strand.
#'@param primer.ranges A set of GRanges, corresponding to the targets.
#'Read lengths are typically greater than target regions, and it can
#'be that reads span multiple targets.  If primer.ranges are available,
#'they can be used to assign such reads to the correct target.
#'@param target.loc The zero point for renumbering (Default: 17)
#'@param ignore.strand Should strand be considered when finding overlaps?
#'(See \code{\link[GenomicAlignments]{findOverlaps}} )
#'@param bpparam A BiocParallel parameter for parallelising across reads.
#'Default: no parallelisation.  (See \code{\link[BiocParallel]{bpparam}})
#'@param chimera.to.target Number of bases that may separate a chimeric read
#'set from the target.loc for it to be assigned to the target. (Default: 5)
#'@rdname readsToTarget
setMethod("readsToTargets", signature("character", "GRanges"),
          function(reads, targets, ..., references, primer.ranges = NULL,
                   target.loc = 17, reverse.complement = TRUE,
                   collapse.pairs = FALSE, use.consensus = FALSE,
                   ignore.strand = TRUE, names = NULL,
                   bpparam = BiocParallel::SerialParam(),
                   orientation = c("target","opposite","positive"),
                   chimera.to.target = 5, verbose = TRUE){

            dummy <- .checkReadsToTargets(targets, primer.ranges, references)
            .checkFnamesExist(reads)
            
            if (is.null(names)){
              names <- reads
            }

            param <- Rsamtools::ScanBamParam(what = c("seq", "flag"))
            args <- list(...)
            ntargets <- length(targets)

            bams <- BiocParallel::bplapply(seq_along(reads), function(i){
              if (verbose) message(sprintf("Loading alignments for %s\n\n",
                                       names[i]))
              bam <- GenomicAlignments::readGAlignments(reads[i],
                                              param = param, use.names = TRUE)
              if (length(bam) == 0){
                if (verbose) message("No reads in alignment\n")
                return(NULL)
              }
              return(bam)
           }, BPPARAM = bpparam)

           bams <- GAlignmentsList(bams)
           if (collapse.pairs == FALSE) dummy <- .checkForPaired(bams)

           orientation <- match.arg(orientation)
           result <- readsToTargets(bams, targets, references = references,
                       target.loc = target.loc, verbose = verbose,
                       reverse.complement = reverse.complement,
                       ignore.strand = ignore.strand,
                       collapse.pairs = collapse.pairs, names = names,
                       bpparam = bpparam, use.consensus = use.consensus,
                       chimera.to.target = chimera.to.target,
                       orientation = orientation)
          result

          })


#'@rdname readsToTarget
setMethod("readsToTargets", signature("GAlignmentsList", "GRanges"),
          function(reads, targets, ..., references, primer.ranges = NULL,
                   target.loc = 17, reverse.complement = TRUE, 
                   collapse.pairs = FALSE, use.consensus = FALSE,
                   ignore.strand = TRUE, names = NULL, 
                   bpparam = BiocParallel::SerialParam(),
                   chimera.to.target = 5, 
                   orientation = c("target", "opposite", "positive"),
                   verbose = TRUE){

    # To do:
    # Currently this returns a list with the non-empty CrisprSets
    # consider making the list the length of the supplied targets

    dummy <- .checkReadsToTargets(targets, primer.ranges, references)
    if (collapse.pairs == FALSE) dummy <- .checkForPaired(reads)

    if (is.null(names)){
      if (! is.null(names(reads))){
        names <- names(reads)
      }else{
        names <- sprintf("Sample %s",seq_along(reads))
      }
    }

    orientation <- match.arg(orientation)

    byPCR <- BiocParallel::bplapply(reads, function(bam){

      if (verbose) message(sprintf("Assigning chimeric reads to targets \n"))

      # Change to default: just supply the cut site (target.loc)
      ch_tgts <- resize(resize(targets, target.loc + 1, fix="start"), 2, fix = "end")

      temp <- separateChimeras(bam, ch_tgts, chimera.to.target,
                              by.flag = collapse.pairs, verbose = verbose)
      bam <- temp$bam
      chimerasByPCR <- temp$chimeras

      # If primer.ranges are provided, match reads to primers
      # If not, match reads to targets
      if (! is.null(primer.ranges)){
        hits <- readsByPCRPrimer(bam, primer.ranges, verbose = verbose)
        splits <- split(queryHits(hits), subjectHits(hits))
      } else{
        hits <- findOverlaps(targets, bam, type = "within", ignore.strand = TRUE)
        duplicates <- (duplicated(subjectHits(hits)) |
                       duplicated(subjectHits(hits), fromLast = TRUE))
        if (verbose){
          msg <- paste0("%s (%.2f%%) reads of %s overlap a target\n",
                        "  %s (%.2f%%) of these overlapping multiple targets removed\n",
                        "  %s (%.2f%%) reads mapped to a single target\n\n")
          rhits <- length(unique(subjectHits(hits)))
          bl <- length(bam)
          ndups <- sum(duplicated(subjectHits(hits)))
          nndups <- sum(!duplicates)
          message(sprintf(msg, rhits, rhits/bl*100, bl, ndups, ndups/rhits*100,
                      nndups, nndups/bl*100))
        }
        hits <- hits[!duplicates]
        splits <- split(subjectHits(hits), queryHits(hits))
      }
      bamByPCR <- as.list(rep(NA, length(targets)))
      names(bamByPCR) <- seq_along(targets)
      for (nm in names(splits)){
        bamByPCR[[nm]] <- bam[splits[[nm]]]
      }
      byPCR <- list(bamByPCR = bamByPCR, chimerasByPCR = chimerasByPCR)
      byPCR
    }, BPPARAM = bpparam)

    # Remove any empty alignments
    to_keep <- which(lapply(byPCR, length) > 0)
    byPCR <- byPCR[to_keep]
    names <- names[to_keep]
    
    if (length(names) == 0){
      stop("No files contain on target reads")
    }

    # Reformat to list by guides instead of samples
    tlist <- function(i) {
      lapply(temp, "[[", i)
    }
    temp <- lapply(byPCR, "[[", "chimerasByPCR")
    chimerasByPCR <- lapply(seq_along(temp[[1]]), tlist)
    temp <- lapply(byPCR, "[[", "bamByPCR")
    bamByPCR <- lapply(seq_along(temp[[1]]), tlist)
    tg_gr <- as(targets, "GRangesList")
    

    result <- BiocParallel::bplapply(seq_along(bamByPCR), function(i){
      bams <- bamByPCR[[i]]
      tgt <- tg_gr[[i]]
      mcols(tgt) <- mcols(targets[i])
      chs <- chimerasByPCR[[i]]
      ref <- references[[i]]
      if (isTRUE(verbose)){
        message(sprintf("\n\nWorking on target %s\n", names(tgt)))
      }
      
      cset <- alnsToCrisprSet(bams, ref, tgt, reverse.complement,
                              collapse.pairs, names, use.consensus, target.loc,
                              verbose, chimeras = chs,
                              orientation = orientation, ...)
    }, BPPARAM = bpparam)

    if (length(result) == 0){
      warning("No reads span a target")
      return(result)
    }

    if (!is.null(names(targets))) {
      names(result) <- names(targets)
    }

    result <- result[!sapply(result, is.null)]
    result
  }) # -----


#__________________________________________________________________
# Data import and processing
#__________________________________________________________________

# separateChimeras -----
separateChimeras <- function(bam, targets, tolerance = 5,
                             by.flag = TRUE, verbose = FALSE){

  # The supplementary alignment flag must be set to distinguish paired from
  # chimeric reads. Tolerance is added on both sides
  # A better approach might be to explicitly consider where chimeras
  # join w.r.t read
  # Worth warning if there are chimeras independent of the guide?

  # Find chimeras
  ch_idxs <- findChimeras(bam, by.flag)
  chimeras <- bam[ch_idxs]
  original_ln <- length(chimeras)

  # Setup return data
  chimerasByPCR <- vector("list", length(targets))
  names(chimerasByPCR) <- as.character(seq_along(targets))

  # If the target is completely contained within one member of the
  # chimeric set (two members if paired), do not count it as a chimera
  guide_within <- subjectHits(findOverlaps(targets, chimeras,
                              ignore.strand = TRUE, type = "within"))
  ordered <- unique(guide_within[order(guide_within)])

  # If any targets contained within a chimeric read, remove all members of set
  if (length(ordered) > 0){
    lns_rle <- rle(names(chimeras)[ordered])$lengths
    grps <- rep(1:length(lns_rle), lns_rle)
    is_first <- paste(grps, bitwAnd(mcols(chimeras)$flag[ordered], 64),
                      sep = ".")
    not_dup <- !(duplicated(is_first) | duplicated(is_first, fromLast = TRUE))

    # Remove all chimeras with guides included from the chimeric sets
    non_ch <- names(chimeras) %in% names(chimeras)[ordered][not_dup]
    ch_idxs <- ch_idxs[!non_ch]
    chimeras <- bam[ch_idxs]
  }

  # Assign chimeras to targets
  tgt_plus_tol <- targets + tolerance
  hits <- findOverlaps(chimeras, tgt_plus_tol, ignore.strand = TRUE)

  # Exclude members that match multiple targets
  is_dup <- duplicated(queryHits(hits)) | duplicated(queryHits(hits), fromLast = TRUE)
  hits <- hits[!is_dup]
  splits <- split(queryHits(hits), subjectHits(hits))

  #For each hit, collect all alignments with the same name
  idx_by_primer <- lapply(splits, function(idxs){
    ch_idxs[names(chimeras) %in% names(chimeras)[idxs]]
  })

  ibp <- unlist(idx_by_primer)

  alnsByPCR <- lapply(idx_by_primer, function(ids){ bam[ids]})
  chimerasByPCR[names(splits)] <- alnsByPCR

  if (isTRUE(verbose)){
    # How many chimeric sets were not assigned?
    n_inc <- length(unique(ibp))
    n_total <- length(ch_idxs)
    n_dup <- sum(duplicated(ibp) | duplicated(ibp, fromLast = TRUE))
    pct_inc <- n_inc/n_total * 100
    pct_multi <- n_dup/n_total * 100
    removed <- original_ln - length(chimeras)

    rm_pct <- removed/original_ln * 100
    message(sprintf(paste0("%s from %s (%.2f%%) chimeras did not involve guide\n",
                    "%s from %s (%.2f%%) remaining chimeric reads included\n",
                    "%s (%.2f%%) assigned to more than one target\n"),
                removed, original_ln, rm_pct, n_inc, n_total,
                pct_inc, n_dup, pct_multi))
  }

  # Remove chimeras from the bam
  if (length(ch_idxs) >= 2){
    bam <- bam[-ch_idxs]
  }
  # Return list of chimerasByPCR and bam
  result <- list(bam = bam, chimerasByPCR = chimerasByPCR)
  result
} # -----


# alnsToCrisprSet -----
#@param label.alleles  (logical(1)) Calculate allele labels using the
#default counting method.  If FALSE, allele labels are not set at 
#initialisation (Default: TRUE).
alnsToCrisprSet <- function(alns, reference, target, reverse.complement,
                            collapse.pairs, names, use.consensus, target.loc,
                            verbose, orientation, chimeras = NULL,
                            store.chimeras = FALSE, minoverlap = NULL,
                            allele.labels = TRUE, ...){

    # Flag for whether variants should be counted w.r.t the negative strand
    rc <- rcAlns(as.character(strand(target)), orientation)
  
    # The reference is with respect to the guide.  If the opposite
    # strand is being displayed, reverse the reference.
    # For display wrt target, rc is TRUE for -ve, FALSE for +v
    is_neg <- as.character(strand(target)) == "-"
  
    #if (! (is_neg == rc)){
    #  reference <- Biostrings::reverseComplement(reference)
    #}
  
    # Narrow alignments for each sample
    crispr.runs <- lapply(seq_along(alns), function(i){
      aln <- alns[[i]]

      if (! is(aln, "GAlignments")) {
        aln <- GenomicAlignments::GAlignments()
      }

      chim <- chimeras[[i]]
      if (is.null(chim)) {chim <- GenomicAlignments::GAlignments()}
      checked <- "checked" %in% names(list(...))
      crun <- readsToTarget(aln, target = target,
                reverse.complement = reverse.complement, chimeras = chim,
                collapse.pairs = collapse.pairs, use.consensus = use.consensus,
                verbose = verbose, name = names[i], orientation = orientation,
                minoverlap = minoverlap, target.loc = target.loc,
                checked = checked)
      crun
    })

    # Remove empty samples
    to_rm <- sapply(crispr.runs, is.null)
    if (any(to_rm)){
      if (verbose){
        rm_nms <- paste0(names[to_rm], collapse = ",", sep = "\n")
        message(sprintf("Excluding samples that have no on target reads:\n%s",
                    rm_nms))
      }
      crispr.runs <- crispr.runs[!to_rm]
      names <- names[!to_rm]
      if (length(crispr.runs) == 0) {
        warning("Could not narrow reads to target, ",
                "no samples have on-target alignments")
        return()
      }
    }
    
    # Combine samples into a single object
    cset <- CrisprSet(crispr.runs, reference, target, rc = rc,
                      target.loc = target.loc, 
                      verbose = verbose, names = names, ...)
    
    # Set the allele labels
    if (isTRUE(allele.labels) & ! all(lengths(alns(cset)) == 0)){
        cig_labs_defaults = list(renumbered = TRUE,
                                 match_label = "no variant",
                                 mismatch_label = "SNV",
                                 split.snv = TRUE,
                                 upstream.snv = 8,
                                 downstream.snv = 6,
                                 bpparam = BiocParallel::SerialParam())
        dots <- list(...)
        cig_labs_defaults <- modifyList(cig_labs_defaults, 
                dots[names(dots) %in% names(cig_labs_defaults)])
        do.call(cset$setCigarLabels, cig_labs_defaults)
    }
    cset
} # -----


# readTargetBam -----
#'@title Internal CrispRVariants function for reading and filtering a bam file
#'@description Includes options for excluding reads either by name or range.
#'The latter is useful if chimeras are excluded.  Reads are excluded before
#'chimeras are detected, thus a chimeric read consisting of two sections, one of
#'which overlaps an excluded region, will not be considered chimeric.
#'Chimeric reads can be ignored, excluded, which means that all sections of a
#'chimeric read will be removed, or merged, which means that chimeras will be
#'collapsed into a single read where possible. (Not implemented yet)
#'If chimeras = "merge", chimeric reads are merged if all segments
# are from the same chromosome, do not overlap, and are aligned to the same strand.
# It is assumed that sequences with two alignments are chimeras, not alternate mappings
#'@param file The name of a bam file to read in
#'@param target A GRanges object containing a single target range
#'@param exclude.ranges A GRanges object of regions that should not be counted,
#'e.g. primer or cloning vector sequences that have a match in the genome
#'@param exclude.names A vector of read names to exclude.
#'@param chimera.to.target Maximum distance between endpoints of chimeras and
#'target.loc for assigning chimeras to targets (default: 5)
#'@param chimeras Flag to determine how chimeric reads are treated.  One of
#'"ignore", "exclude", "count" and "merge".  Default "ignore".
#'@param max.read.overlap Maximum number of bases mapped to two positions
#'for chimeras to be merged (Default: 10)
#'@param max.unmapped Maximum number of bases that are unmapped for chimeras
#'to be merged (Default: 4)
#'@param verbose Print stats about number of alignments read and filtered.  (Default: TRUE)
#'@param by.flag Is the supplementary alignment flag set?  Used for identifying chimeric
#'alignments, function is much faster if TRUE.  Not all aligners set this flag.  If FALSE,
#'chimeric alignments are identified using read names (Default: TRUE)
#'@return A GenomicAlignments::GAlignment obj
readTargetBam <- function(file, target, exclude.ranges = GRanges(),
                          exclude.names = NA, chimera.to.target = 5,
                          chimeras = c("count", "ignore","exclude","merge"),
                          max.read.overlap = 10, max.unmapped = 4,
                          by.flag = TRUE, verbose = TRUE){

    ch.action <- match.arg(chimeras)
    if (ch.action == "ignore"){
      # If chimeras are not to be excluded or merged,
      # we only need to read in reads overlapping the target region
      if (! file.exists(paste0(file, ".bam"))){
        Rsamtools::indexBam(file)
      }
      param <- Rsamtools::ScanBamParam(what = c("seq", "flag"), which = target)
    } else {
      # In this case, must read in the entire bam to be sure of finding chimeric reads
      param <- Rsamtools::ScanBamParam(what = c("seq", "flag"))
    }
    bam <- GenomicAlignments::readGAlignments(file, param = param, use.names = TRUE)
    if (length(bam) == 0){
      return(list(bam = GenomicAlignments::GAlignments(),
                  chimeras = GenomicAlignments::GAlignments()))
    }

    # Check that "seq" is not empty
    unq_wdths <- unique(width(mcols(bam)$seq))
    if (length(unq_wdths) == 0){
      if (unq_wdths == 0) stop("No sequence found in bam file")
    }

    #Exclude reads by name or range
    temp <- excludeFromBam(bam, exclude.ranges, exclude.names)

    if (isTRUE(verbose)){
      original <- length(bam)
      message(sprintf("Read %s alignments, excluded %s\n", original,
                      original - length(temp)))
    }
    bam <- temp

    if (length(bam) == 0 | ch.action == "ignore"){
      return(list(bam = bam, chimeras = GenomicAlignments::GAlignments()))
    }

    chimera_idxs <- findChimeras(bam, by.flag = by.flag)

    if (chimeras == "exclude"){
      if( length(chimera_idxs) >= 2){
        bam <- bam[-chimera_idxs]
      }
      if (isTRUE(verbose)){
        message(sprintf("%s reads after filtering chimeras\n", length(bam)))
      }
      return(list(bam = bam, chimeras = GenomicAlignments::GAlignments()))
    }
    if (chimeras == "count"){
      temp <- separateChimeras(bam, target, tolerance = chimera.to.target,
                               by.flag = by.flag, verbose = verbose)
      return(list(bam = temp$bam, chimeras = temp$chimeras[[1]]))
    }
    if (chimeras == "merge"){
      result <- mergeChimeras(bam, chimera_idxs, 
                              max_read_overlap = max.read.overlap,
                              max_unmapped = max.unmapped,
                              verbose = verbose)
      return(list(bam = c(bam[-chimera_idxs], result$merged),
                  chimeras = result$unmerged))
    }
} # -----


# rcAlns -----
#'@title Internal CrispRVariants function for determining read orientation
#'@description Function for determining whether reads should be oriented to the
#'target strand, always displayed on the positive strand, or oriented to 
# the strand opposite the target.
#'@param target.strand  The target strand (one of "+","-","*") 
#'@param orientation One of "target", "opposite" and "positive" (Default: "target")
#'@return A logical value indicating whether reads should be reverse complemented
#'@author Helen Lindsay
rcAlns <- function(target.strand, orientation){

    if (orientation %in% c("opposite","target") & target.strand == "*"){
        warning(paste0("Target does not have a strand\n",
                       "Orienting reads to reference strand."))
      return(FALSE)
    }
    if (orientation == "positive") return(FALSE)
    if (orientation == "target"){
      if (target.strand == "-") return(TRUE)
    } 
    if (orientation == "opposite"){
      if (target.strand == "+") return(TRUE)
    } 
    return(FALSE)
              
} # -----


# collapsePairs -----
#'@title Internal CrispRVariants function for collapsing pairs with concordant indels
#'@description Given a set of alignments to a target region, finds read pairs.
#'Compares insertion/deletion locations within pairs using the cigar string.
#'Pairs with non-identical indels are excluded.  Pairs with identical indels are
#'collapsed to a single read, taking the consensus sequence of the pairs.
#'@param alns A GAlignments object.  We do not use GAlignmentPairs because amplicon-seq
#'can result in pairs in non-standard pairing orientation.
#'Must include BAM flag, must not include unmapped reads.
#'@param use.consensus Should the consensus sequence be used if pairs have a mismatch?
#'Setting this to be TRUE makes this function much slower (Default: TRUE)
#'@param keep.unpaired Should unpaired and chimeric reads be included?  (Default: TRUE)
#'@param verbose Report statistics on reads kept and excluded
#'@param ... Additional items with the same length as alns,
#'that should be filtered to match alns.
#'@return The alignments, with non-concordant pairs removed and concordant pairs
#'represented by a single read.
#'@author Helen Lindsay
collapsePairs <- function(alns, use.consensus = TRUE, keep.unpaired = TRUE,
                          verbose = TRUE, ...){
    dots <- list(...)
 
    if (length(dots) > 0){
      if (! unique(sapply(dots, length)) == length(alns)){
        stop("Each ... argument supplied must have the ",
             "same length as the alignments")
      }
    }
  
    # 1 = 2^0 = paired flag
    # 2048 = 2^11 = supplementary alignment flag
    is_primary <- !(bitwAnd(mcols(alns)$flag, 2048) & bitwAnd(mcols(alns)$flag, 1))
    pairs <- findChimeras(alns[is_primary], by.flag = FALSE) 
    # Above just matches read names

    # If there are no pairs, no need to do anything further
    if (length(pairs) == 0){
      if (isTRUE(keep.unpaired)){
        return(c(list("alignments" = alns), dots))
      } else {
        return(NULL)
      }
    }
    # Pairs are primary alignments with the same name
    nms <- rle(names(alns)[is_primary][pairs])
    nms_codes <- rep(1:length(nms$lengths), nms$lengths)

    # If reads have the same insertions and deletions, they have identical cigar strings
    cig_runs <- rle(paste(cigar(alns)[is_primary][pairs], nms_codes, sep = "."))$lengths
    concordant <- rep(cig_runs, cig_runs) == rep(nms$lengths,nms$lengths)

    # Keep first alignment from all concordant pairs
    # Flag 64 = 2^6 = first alignment in pair
    is_pair <- which(is_primary)[pairs]
    is_first <- as.logical(bitwAnd(mcols(alns)$flag[is_pair], 64))
    keep <- is_pair[concordant & is_first]

    if (verbose){
      nunpaired <- length(alns) - length(is_pair)
      cc_true <- sum(concordant)/2
      cc_false <- sum(!concordant)/2
      stats <- paste0("\nCollapsing paired alignments:\n",
                "%s original alignments\n",
                "  %s are not part of a primary alignment pair\n",
                "     (singletons and chimeras)\n",
                "  %s reads are paired \n",
                "    %s pairs have the same insertions/deletions\n",
                "    %s pairs have different insertions/deletions\n",
                "Keeping the first member of %s concordant read pairs\n")
      message(sprintf(stats, length(alns), nunpaired, length(is_pair),
                  cc_true, cc_false, cc_true))
    }
    if (keep.unpaired){
      # Keep non-pairs, including non-primary and singletons
      keep <- c(keep, setdiff(c(1:length(alns)),is_pair))
      if (verbose) message(sprintf("Keeping %s unpaired reads\n", nunpaired))
    }
    keep_alns <- alns[keep]

    if (use.consensus){
      seq_runs <- rle(paste0(nms_codes, mcols(alns[is_primary][pairs])$seq))$lengths
      same_seq <- rep(seq_runs, seq_runs) == rep(nms$lengths, nms$lengths)
  
      ncc_seqs <- mcols(alns[is_primary][pairs][concordant & !same_seq])$seq
      if (verbose){
        message(sprintf("Finding consensus for %s pairs with mismatches\n",
                    length(ncc_seqs)/2))
      }
      if (length(ncc_seqs) >= 2){
        consensus <- sapply(seq(1,length(ncc_seqs), by = 2), function(i){
        Biostrings::consensusString(ncc_seqs[i:(i+1)])
        })
        # Overwrite the sequence of the non-concordant pairs.
        # The concordant alignments are at the start of keep
        ncc_idxs <- cumsum(concordant & is_first)[concordant & is_first & !same_seq]
        mcols(keep_alns[ncc_idxs])$seq <- Biostrings::DNAStringSet(consensus)
      }
    }
    if (length(keep) == 0) return(NULL)
    filtered.dots <- lapply(dots, function(x) x[keep])

    result <- c(list("alignments" = keep_alns), filtered.dots)
    result
} # -----
