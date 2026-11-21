#'@title Reverses the order of operations in a cigar string
#'@description For example, the string "20M5D15M" would become "15M5D20M"
#'@param cigars the cigar strings.
#'@return The reversed cigar string
reverseCigar <- function(cigars){
  wdths <- explode_cigar_oplens(cigars)
  ops <- explode_cigar_ops(cigars)
  temp <- rev(relist(rev(paste0(unlist(wdths), unlist(ops))), rev(wdths)))
  result <- as.character(Map(base::paste, temp, collapse = ""))
}
