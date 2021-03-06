#' @title gCoda: conditional dependence network inference for compositional data
#'
#' @description Implementation of the gCoda approach \cite{(Fang et al., 2017)},
#'   which is published on GitHub \cite{(Fang, 2016)}.
#'
#' @param x numeric matrix (\emph{n}x\emph{p}) with samples in rows and OTUs/taxa in
#'   columns.
#' @param counts logical indicating whether x constains counts or fractions.
#'   Defaults to \code{FALSE} meaning that x contains fractions so that rows
#'   sum up to 1.
#' @param pseudo numeric value giving a pseudo count, which is added to all
#'   counts if \code{counts = TRUE}. Default is 0.5.
#' @param lambda.min.ratio numeric value specifying lambda(max) / lambda(min).
#'   Defaults to 1e-4.
#' @param nlambda numberic value (integer) giving the of tuning parameters.
#'   Defaults to 15.
#' @param ebic.gamma numeric value specifying the gamma value of EBIC.
#'   Defaults to 0.5.
#'
#' @return A list containing the following elements:
#' \tabular{ll}{
#'   \code{lambda}\tab lambda sequence for compuation of EBIC score\cr
#'   \code{nloglik}\tab negative log likelihood for lambda sequence\cr
#'   \code{df}\tab number of edges for lambda sequence\cr
#'   \code{path}\tab sparse pattern for lambda sequence\cr
#'   \code{icov}\tab inverse covariance matrix for lambda sequence\cr
#'   \code{ebic.score}\tab EBIC score for lambda sequence\cr
#'   \code{refit}\tab sparse pattern with best EBIC score\cr
#'   \code{opt.icov}\tab inverse covariance matrix with best EBIC score\cr
#'   \code{opt.lambda}\tab lambda with best EBIC score}
#'
#' @author
#'   Fang Huaying, Peking University (R-Code and documentation)\cr
#'   Stefanie Peschel (Parts of the documentation)
#' @references
#'   \insertRef{fang2016gcodaGithub}{NetCoMi}\cr
#'   \insertRef{fang2017gcoda}{NetCoMi}
#'
#' @import huge
#' @export

gcoda <- function(x, counts = F, pseudo = 0.5, lambda.min.ratio = 1e-4,
                  nlambda = 15, ebic.gamma = 0.5) {
  # Counts or fractions?
  if(counts) {
    x <- x + pseudo;
    x <- x / rowSums(x);
  }
  n <- nrow(x);
  p <- ncol(x);
  # Log transformation for compositional data
  S <- var(log(x) - rowMeans(log(x)));
  # Generate lambda via lambda.min.ratio and nlambda
  lambda.max <- max(max(S - diag(p)), -min(S - diag(p)));
  lambda.min <- lambda.min.ratio * lambda.max;
  lambda <- exp(seq(log(lambda.max), log(lambda.min), length = nlambda));
  # Store fit result for gcoda via a series of lambda
  fit <- list();
  fit$lambda <- lambda;
  fit$nloglik <- rep(0, nlambda);
  fit$df <- rep(0, nlambda);
  fit$path <- list();
  fit$icov <- list();
  # Compute solution paths for gcoda
  icov <- diag(p);
  for(i in 1:nlambda) {
    out.gcoda <- gcoda_sub(A = S, iSig = icov, lambda = lambda[i]);
    icov <- out.gcoda$iSig;
    fit$nloglik[i] <- out.gcoda$nloglik;
    fit$icov[[i]] <- icov;
    fit$path[[i]] <- 0 + (abs(icov) > 1e-6);
    diag(fit$path[[i]]) <- 0;
    fit$df[i] <- sum(fit$path[[i]]) / 2;
  }
  # Continue if edge density is too small
  imax <- nlambda + 15;
  emin <- p * (p - 1) / 2 * 0.618;
  while(fit$df[i] <= emin && i <= imax && lambda[i] > 1e-6) {
    cat(i, "Going on!\n");
    lambda <- c(lambda, lambda[i]/2);
    i <- i + 1;
    fit$lambda[i] <- lambda[i];
    out.gcoda <- gcoda_sub(A = S, iSig = icov, lambda = lambda[i]);
    icov <- out.gcoda$iSig;
    fit$nloglik[i] <- out.gcoda$nloglik;
    fit$icov[[i]] <- icov;
    fit$path[[i]] <- 0 + (abs(icov) > 1e-6);
    diag(fit$path[[i]]) <- 0;
    fit$df[i] <- sum(fit$path[[i]]) / 2;
  }
  # Compute EBIC score for lambda selection
  fit$ebic.score <- n * fit$nloglik + log(n) * fit$df +
    4 * ebic.gamma * log(p) * fit$df;
  fit$opt.index <- which.min(fit$ebic.score);
  fit$refit <- fit$path[[fit$opt.index]];
  fit$opt.icov <- fit$icov[[fit$opt.index]];
  fit$opt.lambda <- fit$lambda[fit$opt.index];
  return(fit);
}
#-------------------------------------------------------------------------------
# Optimization for gcoda with given lambda
gcoda_sub <- function(A, iSig = NULL, lambda = 0.1, tol_err = 1e-4,
                      k_max = 100) {
  p <- ncol(A);
  if(is.null(iSig)) {
    iSig <- diag(p);
  }

  err <- 1;
  k <- 0;
  fval_cur <- Inf;

  while(err > tol_err && k < k_max) {
    iSig_O <- rowSums(iSig);
    iS_iSig <- 1 / sum(iSig_O);
    iSig_O2 <- iSig_O * iS_iSig;
    A_iSig_O2 <- rowSums(A * rep(iSig_O2, each = p));
    A2 <- A - A_iSig_O2 - rep(A_iSig_O2, each = p) +
      sum(iSig_O2 * A_iSig_O2) + iS_iSig;
    iSig2 <- huge::huge(x = A2, lambda = lambda, method = "glasso", verbose = FALSE)$icov[[1]];

    fval_new <- obj_gcoda(iSig = iSig2, A = A, lambda = lambda);
    xerr <- max(abs(iSig2 - iSig) / (abs(iSig2) + 1));
    err <- min(xerr, abs(fval_cur - fval_new)/(abs(fval_new) + 1));

    k <- k + 1;
    iSig <- iSig2;
    fval_cur <- fval_new;
  }
  nloglik <- fval_cur - lambda * sum(abs(iSig));

  if(k >= k_max) {
    cat("WARNING of gcoda_sub:\n", "\tMaximum Iteration:", k_max,
        "&& Relative error:", err, "!\n");
  }

  return(list(iSig = iSig, nloglik = nloglik));
}
#----------------------------------------
# Objective function value of gcoda (negative log likelihood + penalty)
obj_gcoda <- function(iSig, A, lambda) {
  p <- ncol(A);
  iSig_O <- rowSums(iSig);
  S_iSig <- sum(iSig_O);
  nloglik <- - log(det(iSig)) + sum(iSig * A) + log(S_iSig) -
    sum(iSig_O * rowSums(A * rep(iSig_O, each = p))) / S_iSig;
  pen <- lambda * sum(abs(iSig));
  return(nloglik + pen);
}

#-------------------------------------------------------------------------------
#-------------------------------------------------------------------------------
