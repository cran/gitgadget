% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/git.R
\name{projID}
\alias{projID}
\title{Find project ID}
\usage{
projID(path_with_namespace, token, server, owned = TRUE, search = "")
}
\arguments{
\item{path_with_namespace}{Repo name together with the group or user namespace}

\item{token}{GitLab token}

\item{server}{The GitLab API server}

\item{owned}{Restrict listing to only repos owned by the user? TRUE or FALSE}

\item{search}{Search term to use to narrow down the set of projects}
}
\description{
Find project ID
}
\details{
See \url{https://github.com/vnijs/gitgadget} for additional documentation
}
