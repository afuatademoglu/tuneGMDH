# tuneGMDH

Hyperparameter tuning for the `GMDH()` and `dceGMDH()` binary classifiers of the
[GMDH2](https://CRAN.R-project.org/package=GMDH2) R package.

`tuneGMDH()` searches `alpha`, `maxlayers`, `maxneurons` and `exCriterion` with
stratified 5-fold cross-validation on the training + validation data only.
The test data is never used during tuning. Models are trained exactly as `GMDH()` /
`dceGMDH()` train them.

## Files

| File | Description |
|---|---|
| `tuneGMDH.R` | Functions: `tuneGMDH()`, `compareGMDH()`, `fillNA()` |
| `twonorm_GMDH.R` | Example: GMDH on the twonorm data |
| `twonorm_dceGMDH.R` | Example: dceGMDH on the twonorm data |
| `data/twonorm.csv` | twonorm data used in the examples |

## Requirements

- R (>= 3.6)
- The GMDH2 package:

```r
install.packages("GMDH2")
```

`parallel` comes with R. Works on Windows, macOS and Linux.

## Usage

1. Download the repository (*Code > Download ZIP*) and unzip it.
2. Set the unzipped folder as the working directory, e.g. `setwd("C:/path/to/tuneGMDH")`
   (in RStudio: *Session > Set Working Directory > To Source File Location*).
3. Run an example:

```r
source("twonorm_GMDH.R")
```

To use your own data, change only these lines in an example script:

```r
data     <- read.csv("your_data.csv")
class    <- "target_column"   # name of the outcome column (two classes)
positive <- "yes"             # positive class, used for F1
seed     <- 123
```

### Output of `twonorm_GMDH.R`

```
Best settings:
 alpha maxlayers maxneurons exCriterion
   0.2         5         30         MSE

Test comparison (positive = 1 ):
         Default  Tuned
Accuracy  0.8025 0.8889
F1        0.8000 0.8800
```

## How the tuning works

1. Training and validation sets are combined and split into 5 stratified folds.
2. In each fold, the remaining data is split 3/4 training and 1/4 validation
   (as `GMDH()` needs both), and the fold itself is used for evaluation.
3. Every combination of the settings (default combination always included) is fitted
   on every fold in parallel.
4. The 10 combinations with the lowest cross-validated Brier score are kept, and the one
   with the highest cross-validated accuracy is chosen.
5. The chosen and the default model are refitted on the original training and validation sets.

## Notes

- Default grid: 4 x 3 x 5 x 2 = 120 combinations, 600 model fits.
- `ncores` defaults to the number of CPU cores minus one.
- Results do not depend on the number of cores.
- `dceGMDH` is much slower than `GMDH` because each fit trains five classifiers.
  With a single core, `twonorm_GMDH.R` took about 2 minutes and `twonorm_dceGMDH.R`
  about 5 minutes; with more cores the time drops roughly in proportion.
- For very large data sets (several thousand rows or more) use fewer cores
  (e.g. `ncores = 2`), because every core keeps its own models in memory.
- Missing values are filled with the column medians of the training + validation rows (`fillNA()`).

## Data

`data/twonorm.csv` is simulated data (400 records, 20 features, 2 classes of 200 each),
described by Breiman (1996). Each class is drawn from a 20-dimensional normal distribution
with unit variance; class 1 has mean (a, ..., a) and class 2 has mean (-a, ..., -a),
with a = 2 / sqrt(20).

> Breiman, L. (1996). *Bias, variance, and arcing classifiers* (Technical Report 460).
> Statistics Department, University of California, Berkeley.

The file was generated with the [mlbench](https://CRAN.R-project.org/package=mlbench) package:

```r
library(mlbench)
set.seed(1)
tw <- mlbench.twonorm(400, d = 20)
write.csv(data.frame(tw$x, class = tw$classes), "data/twonorm.csv", row.names = FALSE)
```
