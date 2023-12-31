% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/readsByPCRPrimer.R
\name{rmMultiPCRChimera}
\alias{rmMultiPCRChimera}
\alias{rmMultiPCRChimera,character,Hits,integer-method}
\title{Remove chimeric reads overlapping multiple primers}
\usage{
rmMultiPCRChimera(readnames, pcrhits, chimera_idxs, ...)

\S4method{rmMultiPCRChimera}{character,Hits,integer}(readnames, pcrhits, chimera_idxs, ..., verbose = TRUE)
}
\arguments{
\item{readnames}{A set of read names, used for identifying chimeric read sets}

\item{pcrhits}{A mapping between indices of reads and a set of pcr primers}

\item{chimera_idxs}{location of chimeric reads within the bam}

\item{...}{Additional arguments}

\item{verbose}{Display information about the chimeras (Default: TRUE)}
}
\value{
pcrhits, with chimeric reads mapping to different primers omitted.
}
\description{
Finds and removes sets of chimeric read alignments
that overlap more than one guide, i.e. that cannot be unambiguously
assigned to a single guide.
}
\author{
Helen Lindsay
}
