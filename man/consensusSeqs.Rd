% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/accessors.R
\name{consensusSeqs}
\alias{consensusSeqs}
\alias{consensusSeqs,CrisprSet-method}
\title{Get consensus sequences for variant alleles}
\usage{
consensusSeqs(obj, ...)

\S4method{consensusSeqs}{CrisprSet}(obj, ..., top.n = NULL, min.freq = 0, min.count = 1)
}
\arguments{
\item{obj}{An object containing aligned sequences}

\item{...}{additional arguments}

\item{top.n}{(Integer n) If specified, return variants ranked at least n according
to frequency across all samples (Default: 0, i.e. no cutoff)}

\item{min.freq}{(Float n%) Return variants with frequency at least n% in at
least one sample (Default: 0)}

\item{min.count}{(Integer n) Return variants with count greater than n
in at least one sample (Default: 0)}
}
\value{
A DNAStringSet of consensus sequences on the positive strand.
}
\description{
Return consensus sequences of variant alleles.  At
present, chimeric alignments are not included.
}
\examples{
data("gol_clutch1")
seqs <- consensusSeqs(gol, sample = 2)
}
\author{
Helen Lindsay
}
