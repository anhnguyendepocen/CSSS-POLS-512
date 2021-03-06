###########################################################################
#CSSS 512
#Lab Session 3 - Modeling Stationary Time Series
#4/20/18

###########################################################################

# ARIMA estimation, fitiing, and interpretation
# Chris Adolph 
rm(list=ls())

# Load libraries
library(forecast)     # For auto.arima and cross-validation
library(tseries)      # For unit root tests
library(lmtest)       # For Breusch-Godfrey LM test of serial correlation
library(RColorBrewer) # For nice colors
library(MASS)
library(simcf)

# ARIMA Cross-validation by rolling windows
# Adapted from Rob J Hyndman's code:
# http://robjhyndman.com/hyndsight/tscvexample/
#
# Could use further generalization, e.g. to seasonality
# Careful!  This can produce singularities using categorical covariates
arimaCV <- function(x, order, xreg, include.mean, forward=1, minper=50) {
    require(forecast)
    if (!any(class(x)=="ts")) x <- ts(x)
    n <- length(x)
    mae <- matrix(NA, nrow=n-minper, ncol=forward)
    st <- tsp(x)[1]+(minper-2)   
    for(i in 1:(n-minper)) {
        xshort <- window(x, start=st+(i-minper+1), end=st+i)
        xnext <- window(x, start=st+(i+1), end=min(n, st+(i+forward)))
        xregshort <- window(xreg, start=st+(i-minper+1), end=st+i)
        xregnext <- window(xreg, start=st+(i+1), end=min(n, st+(i+forward)))
        fit <- Arima(xshort, order=order, xreg=xregshort, include.mean=include.mean)
        fcast <- forecast(fit, h=length(xnext), xreg=xregnext)
        mae[i,1:length(xnext)] <- abs(fcast[['mean']]-xnext)
    }
    colMeans(mae, na.rm=TRUE)
}

###########################################################################

# Load data
# Number of deaths and serious injuries in UK road accidents each month.
# Jan 1969 - Dec 1984. Seatbelt law introduced in Feb 1983
# (indicator in second column). Source: Harvey, 1989, p.519ff.
# http://www.staff.city.ac.uk/~sc397/courses/3ts/datasets.html
#
# Variable names:  death law

ukdata <- read.csv("ukdeaths.csv",header=TRUE)
attach(ukdata)

colnames(ukdata)
ukdata

# Look at the time series
#pdf("tsdeath.pdf",width=6,height=3.25)
plot(death,type="l",ylab="deaths",xlab="Time",
     main = "Vehicular accident deaths, UK, 1969-1984")
lines(x=c(170,170),y=c(0,5000),col="red")
text("Seat \n belt \n law",x = 180, y = 2300, col="red",cex=0.7) 
#dev.off()

# Look at the ACF
#pdf("acfdeath.pdf",width=6,height=3.25)
acf(death)
#dev.off()

# Look at the PACF
#pdf("pacfdeath.pdf",width=6,height=3.25)
pacf(death)
#dev.off()

# Look at the decomposed time series
#pdf("decomposedeath.pdf",width=6,height=7.5)
plot(decompose(ts(death,freq=12)))
#dev.off()

## Look at the monthly cycle
#pdf("monthlydeath.pdf",width=6,height=3.25)
plot(decompose(ts(death,freq=12))$seasonal)

###########################################################################
#Look at the monthly cycle by plotting each year separately

# Make some colors
col <- brewer.pal(8, "Blues")

# Gather the data (sort the number of deaths by month and year in a matrix)
deathmat <- matrix(death,nrow=12,ncol=length(death)/12, byrow=FALSE)

# Repeat them as many times as needed
col <-  as.vector(t(matrix(col, nrow=length(col), ncol=ceiling(ncol(deathmat)/length(col)))))

# Plot each year over the months
matplot(deathmat, type="l", col=col, lty=1, xaxt="n", ylab="deaths", xlab="Month",
        main=expression(paste("Monthly view of accident deaths, UK, 1969-1984")))
axis(1, at=1:12, labels=c("J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"))
abline(a=0,b=0,lty="dashed")
#dev.off()

###########################################################################

# Check for a unit root
PP.test(death)
adf.test(death)

#Do we have evidence that the time series stationary?

###########################################################################

#It looks like there is seasonality in the time series, so let's try to control for each month or Q4

# Make some month variables (there are easier ways!)
jan <- as.numeric(month=="January")
feb <- as.numeric(month=="February")
mar <- as.numeric(month=="March")
apr <- as.numeric(month=="April")
may <- as.numeric(month=="May")
jun <- as.numeric(month=="June")
jul <- as.numeric(month=="July")
aug <- as.numeric(month=="August")
sep <- as.numeric(month=="September")
oct <- as.numeric(month=="October")
nov <- as.numeric(month=="November")
dec <- as.numeric(month=="December")

# Make a fourth quarter indicator
q4 <- as.numeric(oct|nov|dec)

# Store all these variables in the dataframe
ukdata$jan <- jan
ukdata$feb <- feb
ukdata$mar <- mar
ukdata$apr <- apr
ukdata$may <- may
ukdata$jun <- jun
ukdata$jul <- jul
ukdata$aug <- aug
ukdata$sep <- sep
ukdata$oct <- oct
ukdata$nov <- nov
ukdata$dec <- dec
ukdata$q4 <- q4

# Set rolling window length and look ahead period for cross-validation
minper <- 170		
forward <- 12

#################################################################
## Model 1a:  AR(1) model of death as function of law
##

## Estimate an AR(1) using arima
xcovariates <- law
arima.res1a <- arima(death, order = c(1,0,0),
                     xreg = xcovariates, include.mean = TRUE
                     )

print(arima.res1a)
#How do we interpret these parameter estimates?

# Extract estimation results from arima.res1a
pe.1a <- arima.res1a$coef                    # parameter estimates (betas)
se.1a <- sqrt(diag(arima.res1a$var.coef))    # standard errors
ll.1a <- arima.res1a$loglik                  # log likelihood at its maximum
sigma2hat.1a <- arima.res1a$sigma2           # standard error of the regression
aic.1a <- arima.res1a$aic                    # Akaike Information Criterion
resid.1a <- arima.res1a$resid                # residuals

#Recall that the AIC is equal to the deviance (-2*log likelihood at its maximum) of the model plus 2 * the dimension of the model (number of free parameters of the model)
-2*ll.1a + 2*length(pe.1a)

#And the standard error of the regression is just the expected value of the squared residuals
mean(resid.1a^2)

#With a fixed mean, where does y_t converge?

# Attempt at rolling window cross-validation (see caveats)
cv.1a <- arimaCV(death, order=c(1,0,0), forward=forward,
                 xreg=xcovariates, include.mean=TRUE, minper=minper)

#################################################################
## Model 1b:  AR(1) model of death as function of law & q4
##

## Estimate an AR(1) using arima
xcovariates <- cbind(law, q4)
arima.res1b <- arima(death, order = c(1,0,0),
                     xreg = xcovariates, include.mean = TRUE
                     )
print(arima.res1b)

# Extract estimation results from arima.res1b
pe.1b <- arima.res1b$coef                    # parameter estimates (betas)
se.1b <- sqrt(diag(arima.res1b$var.coef))    # standard errors
ll.1b <- arima.res1b$loglik                  # log likelihood at its maximum
sigma2hat.1b <- arima.res1b$sigma2           # standard error of the regression
aic.1b <- arima.res1b$aic                    # Akaike Information Criterion
resid.1b <- arima.res1b$resid                # residuals

# Attempt at rolling window cross-validation (see caveats)
cv.1b <- arimaCV(ts(death), order=c(1,0,0), forward=forward,
                 xreg=xcovariates, include.mean=TRUE, minper=minper)


#################################################################
## Model 1c:  AR(1) model of death as function of law & months
##

## Estimate an AR(1) using arima
xcovariates <- cbind(law, jan, feb, mar, apr, may, jun, aug, sep, oct, nov, dec)
arima.res1c <- arima(death, order = c(1,0,0),
                     xreg = xcovariates, include.mean = TRUE
                     )
print(arima.res1c)

# Extract estimation results from arima.res1c
pe.1c <- arima.res1c$coef                    # parameter estimates (betas)
se.1c <- sqrt(diag(arima.res1c$var.coef))    # standard errors
ll.1c <- arima.res1c$loglik                  # log likelihood at its maximum
sigma2hat.1c <- arima.res1c$sigma2           # standard error of the regression
aic.1c <- arima.res1c$aic                    # Akaike Information Criterion
resid.1c <- arima.res1c$resid                # residuals

# Attempt at rolling window cross-validation (see caveats)
cv.1c <- arimaCV(ts(death), order=c(1,0,0), forward=forward,
                 xreg=xcovariates, include.mean=TRUE, minper=minper)


#################################################################
## Model 1d:  AR(1) model of death as function of law & select months
##

## Estimate an AR(1) using arima
xcovariates <- cbind(law, jan, sep, oct, nov, dec)
arima.res1d <- arima(death, order = c(1,0,0),
                     xreg = xcovariates, include.mean = TRUE
                     )
print(arima.res1d)

# Extract estimation results from arima.res1d
pe.1d <- arima.res1d$coef                    # parameter estimates (betas)
se.1d <- sqrt(diag(arima.res1d$var.coef))    # standard errors
ll.1d <- arima.res1d$loglik                  # log likelihood at its maximum
sigma2hat.1d <- arima.res1d$sigma2           # standard error of the regression
aic.1d <- arima.res1d$aic                    # Akaike Information Criterion
resid.1d <- arima.res1d$resid                # residuals

# Attempt at rolling window cross-validation (see caveats)
cv.1d <- arimaCV(ts(death), order=c(1,0,0), forward=forward,
                 xreg=xcovariates, include.mean=TRUE, minper=minper)



#################################################################
## Model 1e:  AR(1)AR(1)_12 model of death as function of law 
##

## Estimate an AR(1)AR(1)_12 using arima
xcovariates <- cbind(law)
arima.res1e <- arima(death, order = c(1,0,0),
                     seasonal = list(order = c(1,0,0), period = 12),
                     xreg = xcovariates, include.mean = TRUE
                     )
print(arima.res1e)

# Extract estimation results from arima.res1e
pe.1e <- arima.res1e$coef                    # parameter estimates (betas)
se.1e <- sqrt(diag(arima.res1e$var.coef))    # standard errors
ll.1e <- arima.res1e$loglik                  # log likelihood at its maximum
sigma2hat.1e <- arima.res1e$sigma2           # standard error of the regression
aic.1e <- arima.res1e$aic                    # Akaike Information Criterion
resid.1e <- arima.res1e$resid                # residuals

# Attempt at rolling window cross-validation (see caveats)
cv.1e <- arimaCV(ts(death), order=c(1,0,0), forward=forward,
                 xreg=xcovariates, include.mean=TRUE, minper=minper)




# So far, an AR(1) with additive seasonality looks best according to AIC
# But maybe a different ARMA(p,q) would fit better?
# Let's keep the additive seasonality and try various ARMA models manually

#################################################################
## Model 2a:  AR(2) model of death as function of law & months
##

## Estimate an AR(2) using arima
xcovariates <- cbind(law, jan, feb, mar, apr, may, jun, aug, sep, oct, nov, dec)
arima.res2a <- arima(death, order = c(2,0,0),
                     xreg = xcovariates, include.mean = TRUE
                     )
print(arima.res2a)

# Extract estimation results from arima.res2a
pe.2a <- arima.res2a$coef                    # parameter estimates (betas)
se.2a <- sqrt(diag(arima.res2a$var.coef))    # standard errors
ll.2a <- arima.res2a$loglik                  # log likelihood at its maximum
sigma2hat.2a <- arima.res2a$sigma2           # standard error of the regression
aic.2a <- arima.res2a$aic                    # Akaike Information Criterion
resid.2a <- arima.res2a$resid                # residuals

# Attempt at rolling window cross-validation (see caveats)
cv.2a <- arimaCV(ts(death), order=c(2,0,0), forward=forward,
                 xreg=xcovariates, include.mean=TRUE, minper=minper)




#################################################################
## Model 2b:  MA(1) model of death as function of law & months
##

## Estimate an MA(1) using arima
xcovariates <- cbind(law, jan, feb, mar, apr, may, jun, aug, sep, oct, nov, dec)
arima.res2b <- arima(death, order = c(0,0,1),
                     xreg = xcovariates, include.mean = TRUE
                     )
print(arima.res2b)

# Extract estimation results from arima.res2b
pe.2b <- arima.res2b$coef                    # parameter estimates (betas)
se.2b <- sqrt(diag(arima.res2b$var.coef))    # standard errors
ll.2b <- arima.res2b$loglik                  # log likelihood at its maximum
sigma2hat.2b <- arima.res2b$sigma2           # standard error of the regression
aic.2b <- arima.res2b$aic                    # Akaike Information Criterion
resid.2b <- arima.res2b$resid                # residuals

# Attempt at rolling window cross-validation (see caveats)
cv.2b <- arimaCV(ts(death), order=c(0,0,1), forward=forward,
                 xreg=xcovariates, include.mean=TRUE, minper=minper)




#################################################################
## Model 2c:  ARMA(1,1) model of death as function of law & months
##

## Estimate an ARMA(1,1) using arima
xcovariates <- cbind(law, jan, feb, mar, apr, may, jun, aug, sep, oct, nov, dec)
arima.res2c <- arima(death, order = c(1,0,1),
                     xreg = xcovariates, include.mean = TRUE
                     )
print(arima.res2c)

# Extract estimation results from arima.res2c
pe.2c <- arima.res2c$coef                    # parameter estimates (betas)
se.2c <- sqrt(diag(arima.res2c$var.coef))    # standard errors
ll.2c <- arima.res2c$loglik                  # log likelihood at its maximum
sigma2hat.2c <- arima.res2c$sigma2           # standard error of the regression
aic.2c <- arima.res2c$aic                    # Akaike Information Criterion
resid.2c <- arima.res2c$resid                # residuals

# Attempt at rolling window cross-validation (see caveats)
cv.2c <- arimaCV(ts(death), order=c(1,0,1), forward=forward,
                 xreg=xcovariates, include.mean=TRUE, minper=minper)



#################################################################
## Model 2d:  ARMA(2,1) model of death as function of law & months
##

## Estimate an ARMA(2,1) using arima
xcovariates <- cbind(law, jan, feb, mar, apr, may, jun, aug, sep, oct, nov, dec)
arima.res2d <- arima(death, order = c(2,0,1),
                     xreg = xcovariates, include.mean = TRUE
                     )
print(arima.res2d)

# Extract estimation results from arima.res2d
pe.2d <- arima.res2d$coef                    # parameter estimates (betas)
se.2d <- sqrt(diag(arima.res2d$var.coef))    # standard errors
ll.2d <- arima.res2d$loglik                  # log likelihood at its maximum
sigma2hat.2d <- arima.res2d$sigma2           # standard error of the regression
aic.2d <- arima.res2d$aic                    # Akaike Information Criterion
resid.2d <- arima.res2d$resid                # residuals

# Attempt at rolling window cross-validation (see caveats)
cv.2d <- arimaCV(ts(death), order=c(2,0,1), forward=forward,
                 xreg=xcovariates, include.mean=TRUE, minper=minper)


#################################################################
## Model 2e:  ARMA(1,2) model of death as function of law & months
##

## Estimate an ARMA(1,2) using arima
xcovariates <- cbind(law, jan, feb, mar, apr, may, jun, aug, sep, oct, nov, dec)
arima.res2e <- arima(death, order = c(1,0,2),
                     xreg = xcovariates, include.mean = TRUE
                     )
print(arima.res2e)

# Extract estimation results from arima.res2e
pe.2e <- arima.res2e$coef                    # parameter estimates (betas)
se.2e <- sqrt(diag(arima.res2e$var.coef))    # standard errors
ll.2e <- arima.res2e$loglik                  # log likelihood at its maximum
sigma2hat.2e <- arima.res2e$sigma2           # standard error of the regression
aic.2e <- arima.res2e$aic                    # Akaike Information Criterion
resid.2e <- arima.res2e$resid                # residuals

# Attempt at rolling window cross-validation (see caveats)
cv.2e <- arimaCV(ts(death), order=c(1,0,2), forward=forward,
                 xreg=xcovariates, include.mean=TRUE, minper=minper)


#################################################################
## Model 2f:  ARMA(2,2) model of death as function of law & months
##

## Estimate an ARMA(2,2) using arima
xcovariates <- cbind(law, jan, feb, mar, apr, may, jun, aug, sep, oct, nov, dec)
arima.res2f <- arima(death, order = c(2,0,2),
                     xreg = xcovariates, include.mean = TRUE
                     )
print(arima.res2f)

# Extract estimation results from arima.res2f
pe.2f <- arima.res2f$coef                    # parameter estimates (betas)
se.2f <- sqrt(diag(arima.res2f$var.coef))    # standard errors
ll.2f <- arima.res2f$loglik                  # log likelihood at its maximum
sigma2hat.2f <- arima.res2f$sigma2           # standard error of the regression
aic.2f <- arima.res2f$aic                    # Akaike Information Criterion
resid.2f <- arima.res2f$resid                # residuals

# Attempt at rolling window cross-validation (see caveats)
cv.2f <- arimaCV(ts(death), order=c(2,0,2), forward=forward,
                 xreg=xcovariates, include.mean=TRUE, minper=minper)



###########################################################################

# Tired of manual search?  Auto.arima in the forecast package can automate the search,
# but be careful!
#
# auto.arima guessed that this time series was non-stationary,
# and without the additive seasonal effects manually added, tried to fit
# complex seasonal ARMA terms. Restricting to a stationary model and
# telling auto.arima to leave seasonality to the month dummies
# produced a simpler, better fitting model
#
# another warning:  if you seasonal = TRUE, set approximation and stepwise to TRUE
# or prepare to wait
xcovariates <- cbind(law, jan, feb, mar, apr, may, jun, aug, sep, oct, nov, dec)
arima.res3a <- auto.arima(death,
                          stationary=TRUE, seasonal=FALSE,
                          ic="aic", approximation=FALSE, stepwise=FALSE,
                          xreg = xcovariates)
print(arima.res3a)

# Extract estimation results from arima.res3a
pe.3a <- arima.res3a$coef                    # parameter estimates (betas)
se.3a <- sqrt(diag(arima.res3a$var.coef))    # standard errors
ll.3a <- arima.res3a$loglik                  # log likelihood at its maximum
sigma2hat.3a <- arima.res3a$sigma2           # standard error of the regression
aic.3a <- arima.res3a$aic                    # Akaike Information Criterion
resid.3a <- arima.res3a$resid                # residuals

# Attempt at rolling window cross-validation (see caveats)
cv.3a <- arimaCV(ts(death), order=c(2,0,1), forward=forward,
                 xreg=xcovariates, include.mean=TRUE, minper=minper)


###########################################################################

# Plot cross-validation results
allCV <- cbind(cv.1a, cv.1b, cv.1c, cv.1d, cv.1e, cv.2a, cv.2b, cv.2c, cv.2d, cv.2e, cv.2f)
labs <- c("1a", "1b", "1c", "1d", "1e", "2a", "2b", "2c", "2d", "2e", "2f")

#pdf("rollingCV.pdf",width=6,height=6.55)

col <- c(brewer.pal(7, "Reds")[3:7],
         brewer.pal(8, "Blues")[3:8])

matplot(allCV, type="l", col=col, lty=1, ylab="Mean Absolute Error", xlab="Periods Forward",
        main="Cross-validation of accident deaths models", xlim=c(0.75,12.75))
text(labs, x=rep(12.5,length(labs)), y=allCV[nrow(allCV),], col=col)
#dev.off()

# Average cross-validation results
avgCV12 <- sort(apply(allCV, 2, mean))
avgCV8 <- sort(apply(allCV[1:8,], 2, mean))

# Based on AIC & cross-validation,
# let's select Model 2f to be our final model;
# there are other plausible models
arima.resF <- arima.res2f


###########################################################################

## What would happen if we used linear regression on a single lag of death?
lagdeath <- c(NA,death[1:(length(death)-1)])
lm.res1f <- lm(death ~ lagdeath + jan + feb + mar + apr + may + jun +
               aug + sep + oct + nov + dec + law)
print(summary(lm.res1f))

# Check LS result for serial correlation in the first or second order
bgtest(lm.res1f,1)
bgtest(lm.res1f,2)

# Evidence of residual serial correlation is strong

# Rerun with two lags
lag2death <- c(NA,NA,death[1:(length(death)-2)])
lm.res1g <- lm(death ~ lagdeath + lag2death + jan + feb + mar + apr + may + jun +
               aug + sep + oct + nov + dec + law)
print(summary(lm.res1g))

# Check LS result for serial correlation in the first or second order
bgtest(lm.res1g,1)
bgtest(lm.res1g,2)

# Borderline evidence of serial correlation, but substantively different result.
# (Even small time series assumptions can have big implications for substance.)
# MA terms in ARMA(2,2) seems justified;
# we reject the LS model with lags of the DV


#########################################################
##
## Now that we've selected a model, let's interpret it
## using counterfactuals iterated over time
##

## Predict out five years (60 periods) assuming law is kept

# Make newdata dataframe for prediction
xcovariates <- cbind(law, jan, feb, mar, apr, may,
                     jun, aug, sep, oct, nov, dec)
n.ahead <- 60
lawhyp0 <- rep(1,n.ahead)
janhyp0 <- rep( c( 1,0,0, 0,0,0, 0,0,0, 0,0,0 ), 5)
febhyp0 <- rep( c( 0,1,0, 0,0,0, 0,0,0, 0,0,0 ), 5)
marhyp0 <- rep( c( 0,0,1, 0,0,0, 0,0,0, 0,0,0 ), 5)
aprhyp0 <- rep( c( 0,0,0, 1,0,0, 0,0,0, 0,0,0 ), 5)
mayhyp0 <- rep( c( 0,0,0, 0,1,0, 0,0,0, 0,0,0 ), 5)
junhyp0 <- rep( c( 0,0,0, 0,0,1, 0,0,0, 0,0,0 ), 5)
aughyp0 <- rep( c( 0,0,0, 0,0,0, 0,1,0, 0,0,0 ), 5)
sephyp0 <- rep( c( 0,0,0, 0,0,0, 0,0,1, 0,0,0 ), 5)
octhyp0 <- rep( c( 0,0,0, 0,0,0, 0,0,0, 1,0,0 ), 5)
novhyp0 <- rep( c( 0,0,0, 0,0,0, 0,0,0, 0,1,0 ), 5)
dechyp0 <- rep( c( 0,0,0, 0,0,0, 0,0,0, 0,0,1 ), 5)
newdata0 <- cbind(lawhyp0, janhyp0, febhyp0, marhyp0,
                  aprhyp0, mayhyp0, junhyp0, aughyp0,
                  sephyp0, octhyp0, novhyp0, dechyp0)
                    # Must be in same order as model!
newdata0 <- as.data.frame(newdata0)
names(newdata0) <- c("law", "jan", "feb", "mar", "apr",
                     "may", "jun", "aug", "sep", "oct",
                     "nov", "dec")

# Run predict
ypred0 <- predict(arima.resF,
                  n.ahead = n.ahead,
                  newxreg = newdata0)


# Simulate predicted values 

# Number of simulations - draws from the multivariate normal
sims <- 10000

# Draws from the multivariate normal based on point estimates and variance-covariance matrix
simparam <- mvrnorm(sims, pe.2f, arima.res2f$var.coef)

# The counterfactuals set my the researcher
xhyp <- newdata0

# The simulated phi parameters (if there is AR process)
simphi <- simparam[,1:2]

# The simulated rho parameters (if there is MA process)
simrho <- simparam[,3:4]

# The simulated covariate parameters 
simbetas <- simparam[,5:ncol(simparam)]

# The lag of Y or the last level of Y needed to start the forecast (if AR process)
lagY <- c(death[length(death)],death[length(death)-1])
lagY <- as.vector(lagY)

# The lag of the error or the last error needed to start the forecast (if MA process)
lagEps <- c(arima.res2f$resid[length(death)], arima.res2f$resid[length(death)-1])
lagEps <- as.vector(lagEps)

# The error variance to draw an error (if computing predicted values)
sigma <- sqrt(arima.res2f$sigma)

sim.ev2f <- ldvsimpv(xhyp,
					simbetas,
					ci=0.95,
					constant=1,
					phi=simphi,
					lagY=lagY,
					rho=simrho,
					lagEps=lagEps,
					sigma=sigma
)

sim.ev2f <- ldvsimev(xhyp,
                     simbetas,
                     ci=0.95,
                     constant=1,
                     phi=simphi,
                     lagY=lagY
)


## Predict out five years (60 periods) assuming law is repealed

# Make newdata dataframe for prediction
xcovariates <- cbind(law, jan, feb, mar, apr, may,
                     jun, aug, sep, oct, nov, dec)
n.ahead <- 60
lawhyp <- rep(0,n.ahead)
janhyp <- rep( c( 1,0,0, 0,0,0, 0,0,0, 0,0,0 ), 5)
febhyp <- rep( c( 0,1,0, 0,0,0, 0,0,0, 0,0,0 ), 5)
marhyp <- rep( c( 0,0,1, 0,0,0, 0,0,0, 0,0,0 ), 5)
aprhyp <- rep( c( 0,0,0, 1,0,0, 0,0,0, 0,0,0 ), 5)
mayhyp <- rep( c( 0,0,0, 0,1,0, 0,0,0, 0,0,0 ), 5)
junhyp <- rep( c( 0,0,0, 0,0,1, 0,0,0, 0,0,0 ), 5)
aughyp <- rep( c( 0,0,0, 0,0,0, 0,1,0, 0,0,0 ), 5)
sephyp <- rep( c( 0,0,0, 0,0,0, 0,0,1, 0,0,0 ), 5)
octhyp <- rep( c( 0,0,0, 0,0,0, 0,0,0, 1,0,0 ), 5)
novhyp <- rep( c( 0,0,0, 0,0,0, 0,0,0, 0,1,0 ), 5)
dechyp <- rep( c( 0,0,0, 0,0,0, 0,0,0, 0,0,1 ), 5)
newdata <- cbind(lawhyp, janhyp, febhyp, marhyp,
                 aprhyp, mayhyp, junhyp, aughyp,
                 sephyp, octhyp, novhyp, dechyp)
                  # Must be in same order as model!
newdata <- as.data.frame(newdata)
names(newdata) <- c("law", "jan", "feb", "mar", "apr",
                    "may", "jun", "aug", "sep", "oct",
                    "nov", "dec")

# Run predict
ypred <- predict(arima.resF,
                 n.ahead = n.ahead,
                 newxreg = newdata)

# Simulate predicted values
sims <- 10000
simparam <- mvrnorm(sims, pe.2f, arima.res2f$var.coef)
xhyp <- newdata
simphi <- simparam[,1:2]
simrho <- simparam[,3:4]
simbetas <- simparam[,5:ncol(simparam)]
lagY <- c(death[length(death)],death[length(death)-1])
lagY <- as.vector(lagY)
lagEps <- c(arima.res2f$resid[length(death)], arima.res2f$resid[length(death)-1])
lagEps <- as.vector(lagEps)
sigma <- sqrt(arima.res2f$sigma)

sim.ev2f <- ldvsimpv(xhyp,
					simbetas,
					ci=0.95,
					constant=1,
					phi=simphi,
					lagY=lagY,
					rho=simrho,
					lagEps=lagEps,
					sigma=sigma
)


# Make a plot
pdf("prediction1.pdf",width=6,height=3.25)
plot.new()
par(usr = c(0, length(death) + n.ahead, 1000, 3000) )
# make the x-axis
axis(1,
     at = seq(from = 10, to = 252, by = 12),
     labels = 1969:1989
     )
axis(2)

title(xlab = "Time",
      ylab = "Deaths",
      main="Predicted effect of reversing seat belt law")


# Polygon of predictive interval for no law (optional)
x0 <- (length(death)+1):(length(death) + n.ahead)
y0 <- c(ypred$pred - 2*ypred$se, rev(ypred$pred + 2*ypred$se), (ypred$pred - 2*ypred$se)[1] )
polygon(x = c(x0, rev(x0), x0[1]),
        y = y0,
        border=NA,
        col="#FFBFBFFF"
        )

# Plot the actual data
lines(x = 1:length(death),
      y = death
      )

# Add the predictions for no law
lines(x = length(death):(length(death)+n.ahead),
      y = c(death[length(death)],ypred$pred),  # link up the actual data to the prediction
      col = "red"
      )


# Add the lower predictive interval for no law
#lines(x = length(death):(length(death) + n.ahead),
#      y = c(death[length(death)], ypred$pred - 2*ypred$se),
#      col = "red",
#      lty="dashed"
#      )

# Add the upper predictive interval for no law
#lines(x = length(death):(length(death) + n.ahead),
#      y = c(death[length(death)], ypred$pred + 2*ypred$se),
#      col = "red",
#      lty = "dashed"
#      )


# Add the predictions for keeping law
lines(x = length(death):(length(death)+n.ahead),
      y = c(death[length(death)],ypred0$pred),  # link up the actual data to the prediction
      col = "blue"
      )

dev.off()

