source("tuneGMDH.R")

data     <- read.csv("data/twonorm.csv")
class    <- "class"
positive <- "1"
seed     <- 123

data <- data[!is.na(data[[class]]), ]
y <- factor(data[[class]])
x <- data.matrix(data[names(data) != class])

# Split: 60% train, 20% valid, 20% test
set.seed(seed)
split <- sample(c("train", "valid", "test"), nrow(x), replace = TRUE, prob = c(0.6, 0.2, 0.2))

# Fill NA with train + valid medians
x <- fillNA(x, ref = split != "test")

x.train <- x[split == "train", ]; y.train <- y[split == "train"]
x.valid <- x[split == "valid", ]; y.valid <- y[split == "valid"]
x.test  <- x[split == "test", ];  y.test  <- y[split == "test"]

tune <- tuneGMDH(x.train, y.train, x.valid, y.valid, method = "dceGMDH", verbose = FALSE)
best <- tune$best

# Default and best models (seed set: dceGMDH is random)
set.seed(seed)
model.default <- dceGMDH(x.train, y.train, x.valid, y.valid, verbose = FALSE)
set.seed(seed)
model.best    <- dceGMDH(x.train, y.train, x.valid, y.valid, alpha = best$alpha,
                         maxlayers = best$maxlayers, maxneurons = best$maxneurons,
                         exCriterion = best$exCriterion, verbose = FALSE)

cm.default <- confMat(factor(predict(model.default, x.test), levels = levels(y)), y.test,
                      positive = positive, verbose = FALSE)
cm.best    <- confMat(factor(predict(model.best, x.test), levels = levels(y)), y.test,
                      positive = positive, verbose = FALSE)

cat("\nBest settings:\n")
print(best, row.names = FALSE)

cat("\nTest comparison (positive =", positive, "):\n")
print(round(rbind(Accuracy = c(Default = cm.default$accuracy, Tuned = cm.best$accuracy),
                  F1       = c(Default = cm.default$F1,       Tuned = cm.best$F1)), 4))
