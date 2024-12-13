# Machine Learning ------------------------------------------------------
pacman::p_load( tidyverse, tidymodels, caret, ISLR2, glmnet, boot, leaps,
               viridis, pls, car)

dataset <- read_rds("data/dataset.rds")

x <- model.matrix(antal_afhentede ~ . - 1, dataset)
y <- dataset$antal_afhentede

# Udtræk kun de numeriske kolonner
numeriske_variabler <- samlet_data_flot[, sapply(samlet_data_flot, is.numeric)]  

# Opret en korrelationsmatrix
cor_matrix <- cor(numeriske_variabler)

cor_matrix[is.na(cor_matrix)] <- 0

library(corrplot)
# Opret et varmekortgraf
corrplot(cor_matrix, method = "color", type = "upper", order = "hclust", tl.col = "black", tl.srt = 100)

pairs(numeriske_variabler)

model <- lm(antal_afhentede ~ . , data = dataset)

vif(model)

summary(model)

cor_matrix <- cor(x)
cor_long <- as.data.frame(as.table(cor_matrix)) |> 
  rename(Korrelation = Freq) |> 
  filter(Var1 != Var2) |> 
  filter(abs(Korrelation) > 0.75) |> 
  arrange(desc(Korrelation))

# Ridge og Lasso --------------------------------------------
model <- lm(y ~ x)
grid <- 10^seq(10, -2, length = 100)

set.seed(123)
train <- sample(1:nrow(x), nrow(x)*2/3)
test <- (-train)
y.test <- y[test]

# Ridge
ridge.mod <- glmnet(
  x[train, ], 
  y[train], 
  alpha = 0,
  lambda = grid,
  thresh = 1e-12
)
set.seed(123)
cv.out <- cv.glmnet(
  x[train, ], 
  y[train], 
  alpha = 0,
  lambda = grid,
  nfolds = 5                    )

bestlam <- cv.out$lambda.min
rmse_ridge_cv <- sqrt(cv.out$cvm[cv.out$lambda == bestlam])

ridge.pred <- predict(ridge.mod, s = bestlam, newx = x[test, ]) 
rmse_ridge_test <- sqrt(mean((ridge.pred - y.test)^2))


# Lasso
lasso.mod <- glmnet(
  x[train, ], 
  y[train], 
  alpha = 1,
  lambda = grid,
  thresh = 1e-12
)
set.seed(123)
cv.out <- cv.glmnet(
  x[train, ], 
  y[train], 
  alpha = 1,
  lambda = grid,
  nfolds = 5                    )

bestlam <- cv.out$lambda.min
rmse_lasso_cv <- sqrt(cv.out$cvm[cv.out$lambda == bestlam])

lasso.pred <- predict(lasso.mod, s = bestlam, newx = x[test, ]) 
rmse_lasso_test <- sqrt(mean((lasso.pred - y.test)^2))


# 0 features
set.seed(123)
glm.fit <- glm(antal_afhentede ~ 1, data = dataset[train, ])
rmse_0_cv <- sqrt(cv.glm(dataset[train, ], glm.fit , K = 10)$delta[1])
rmse_0_test <- sqrt(mean((dataset[test, ]$antal_afhentede - predict(glm.fit, dataset[test, ]))^2))


# Best subset selection

predict.regsubsets <- function(object, newdata, id, ...) {
  form <- as.formula(object$call[[2]])
  mat <- model.matrix(form, newdata)
  coefi <- coef(object, id = id)
  xvars <- names(coefi)
  mat[, xvars] %*% coefi
}

samlet_train <- dataset[train,]
samlet_test <- dataset[test,]

k <- 10 # Vi danner 10 folds
n <- nrow(samlet_train) # registrerer hvor mange observationer, vi har.
set.seed(1) 
folds <- sample(rep(1:k, length = n)) #Vi tildeler en værdi mellem 1 og
dim(samlet_train)[2]  # Der er 14 variabler og dermed 13 prædiktorer

cv.errors <- matrix(NA, k, 14,
                    dimnames = list(NULL, paste(1:19)))
cv.errors


for (j in 1:k) { # her gennemløbes alle folds
  best.fit <- regsubsets(antal_afhentede ~ .,
                         data = samlet_train[folds != j, ],
                         nvmax = 13)
  for (i in 1:19) { # her gennemløbes alle kandidatmodeller
    pred <- predict(best.fit, samlet_train[folds == j, ], id = i)
    # predict-funktionen ovenfor kalder den funktion, vi har lavet tidligere. 
    cv.errors[j, i] <-
      mean((samlet_train$antal_afhentede[folds == j] - pred)^2) # Her udregnes MSE for hver 
    # fold for hver kandidatmodel 
  }
}

mean.cv.errors <- apply(cv.errors, 2, mean) # apply er en smart funktion, der 
# gennemløber alle rækker og tager gennemsnittet henover hver søjle, som svarer 
# til hver kandidatmodel.
mean.cv.errors # Vi får altså en gennemsnitlig MSE for hver kandidatmodel.
par(mfrow = c(1, 1))
plot(mean.cv.errors, type = "b") # Her plottes disse gennemsnit for hver størrelse,
which.min(mean.cv.errors)


# Her fittes modellen til ALLE træningsdata
reg.best <- regsubsets(antal_afhentede ~ ., data = samlet_train,
                       nvmax = 13)
coef(reg.best, 7)

pred_best_subset <- predict(reg.best, samlet_test, id = 7)


mse_best_subset <- mean((dataset[test,]$antal_afhentede - pred_best_subset)^2)
rmse_bestsubset_test <- sqrt(mse_best_subset)
rmse_bestsubset_cv <- sqrt(min(mean.cv.errors))

