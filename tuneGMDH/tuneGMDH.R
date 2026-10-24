library(GMDH2)
library(parallel)

# Fill NA with column medians of the ref rows
fillNA <- function(x, ref = rep(TRUE, nrow(x))) {
  x <- data.matrix(x)
  for (j in 1:ncol(x)) {
    med <- median(x[ref, j], na.rm = TRUE)
    if (is.na(med)) med <- 0
    x[is.na(x[, j]), j] <- med
  }
  x
}

# Fit GMDH or dceGMDH
fitModel <- function(method, xt, yt, xv, yv, alpha, maxlayers, maxneurons, exCriterion) {
  if (method == "GMDH") {
    model <- GMDH(xt, yt, xv, yv, alpha = alpha, maxlayers = maxlayers,
                  maxneurons = maxneurons, exCriterion = exCriterion, verbose = FALSE)
  } else {
    p <- ncol(xt)
    model <- dceGMDH(xt, yt, xv, yv, alpha = alpha, maxlayers = maxlayers,
                     maxneurons = maxneurons, exCriterion = exCriterion, verbose = FALSE,
                     nnet_options = list(MaxNWts = max(1000, (p + 1) * (p + 2))))
  }
  model
}

# Tune GMDH settings by cross-validation
tuneGMDH <- function(x.train, y.train, x.valid, y.valid, method = "GMDH",
                     alpha = c(0.2, 0.4, 0.6, 0.8), maxlayers = c(3, 5, 10),
                     maxneurons = c(10, 15, 20, 25, 30), exCriterion = c("MSE", "MAE"),
                     nfolds = 5, ncores = max(1, detectCores() - 1, na.rm = TRUE),
                     verbose = TRUE) {

  if (!is.matrix(x.train) | !is.matrix(x.valid)) stop("x.train and x.valid must be matrices.")
  if (!is.factor(y.train) | !is.factor(y.valid)) stop("y.train and y.valid must be factors.")
  if (nlevels(y.train) != 2) stop("y.train must have exactly two classes.")
  if (!method %in% c("GMDH", "dceGMDH")) stop("method must be \"GMDH\" or \"dceGMDH\".")

  # Combine train and valid
  x <- rbind(x.train, x.valid)
  y <- factor(c(as.character(y.train), as.character(y.valid)), levels = levels(y.train))
  obs <- y == levels(y)[2]

  # Stratified folds
  folds <- rep(NA, length(y))
  for (lev in levels(y)) {
    id <- which(y == lev)
    folds[id] <- sample(rep(1:nfolds, length.out = length(id)))
  }

  # Per fold: 3/4 train, 1/4 valid, fold = test
  sets <- list()
  for (k in 1:nfolds) {
    rest <- which(folds != k)
    valid <- c()
    for (lev in levels(y)) {
      id <- rest[y[rest] == lev]
      valid <- c(valid, id[sample(length(id), round(length(id) / 4))])
    }
    sets[[k]] <- list(train = setdiff(rest, valid), valid = valid, test = which(folds == k))
  }

  # Settings grid (default included)
  grid <- expand.grid(alpha = alpha, maxlayers = maxlayers, maxneurons = maxneurons,
                      exCriterion = exCriterion, stringsAsFactors = FALSE)
  grid <- unique(rbind(grid, data.frame(alpha = 0.6, maxlayers = 10, maxneurons = 15,
                                        exCriterion = "MSE")))
  default <- which(grid$alpha == 0.6 & grid$maxlayers == 10 & grid$maxneurons == 15 &
                   grid$exCriterion == "MSE")

  # Fit every setting on every fold in parallel
  seed <- sample(1:10000, 1)
  jobs <- expand.grid(i = 1:nrow(grid), k = 1:nfolds)
  runJob <- function(j) {
    i <- jobs$i[j]
    s <- sets[[jobs$k[j]]]
    set.seed(seed + jobs$k[j])
    model <- tryCatch(fitModel(method, x[s$train, ], y[s$train], x[s$valid, ], y[s$valid],
                               grid$alpha[i], grid$maxlayers[i], grid$maxneurons[i],
                               grid$exCriterion[i]), error = function(e) NULL)
    if (is.null(model)) return(rep(NA, length(s$test)))
    predict(model, x[s$test, ], type = "probability")[, 2]
  }
  cl <- makeCluster(ncores)
  on.exit(stopCluster(cl))
  clusterEvalQ(cl, library(GMDH2))
  clusterExport(cl, "fitModel", envir = environment())
  res <- parLapply(cl, 1:nrow(jobs), runJob)

  # Out-of-fold probabilities
  prob <- matrix(NA, nrow(grid), length(y))
  for (j in 1:nrow(jobs)) {
    prob[jobs$i[j], sets[[jobs$k[j]]]$test] <- res[[j]]
  }

  # CV Brier score and accuracy
  for (i in 1:nrow(grid)) {
    grid$brier[i] <- mean((prob[i, ] - obs)^2, na.rm = TRUE)
    grid$accuracy[i] <- mean((prob[i, ] >= 0.5) == obs, na.rm = TRUE)
  }

  # Best: highest accuracy among the 10 lowest Brier (and default)
  ord <- order(grid$brier, -grid$accuracy)
  ord <- ord[!duplicated(round(grid[ord, c("brier", "accuracy")], 4))]
  top <- unique(c(ord[1:min(10, length(ord))], default))
  best <- top[which.max(grid$accuracy[top])]

  # Refit best and default models
  set.seed(seed)
  model <- fitModel(method, x.train, y.train, x.valid, y.valid, grid$alpha[best],
                    grid$maxlayers[best], grid$maxneurons[best], grid$exCriterion[best])
  set.seed(seed)
  defaultModel <- fitModel(method, x.train, y.train, x.valid, y.valid, 0.6, 10, 15, "MSE")

  bestSettings <- data.frame(alpha = grid$alpha[best], maxlayers = grid$maxlayers[best],
                             maxneurons = grid$maxneurons[best],
                             exCriterion = grid$exCriterion[best])
  if (verbose) print(bestSettings, row.names = FALSE)

  list(best = bestSettings, model = model, defaultModel = defaultModel, grid = grid)
}

# Test accuracy and F1 of default and tuned models
compareGMDH <- function(tune, x.test, y.test, positive = levels(y.test)[2], verbose = TRUE) {
  result <- data.frame(Model = c("Default", "Tuned"), Accuracy = NA, F1 = NA)
  models <- list(tune$defaultModel, tune$model)
  for (m in 1:2) {
    prob <- predict(models[[m]], x.test, type = "probability")[, 2]
    pred <- ifelse(prob >= 0.5, levels(y.test)[2], levels(y.test)[1])
    pred <- factor(pred, levels = levels(y.test))
    cm <- confMat(pred, y.test, positive = positive, verbose = FALSE)
    result$Accuracy[m] <- cm$accuracy
    result$F1[m] <- cm$F1
  }
  if (verbose) print(result, row.names = FALSE)
  result
}
