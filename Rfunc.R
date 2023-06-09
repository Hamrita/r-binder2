library(keras)
library(tensorflow)
library(TSLSTM)
library(tseries)

##########################
lags <- function(x, k){
    
    lagged =  c(rep(NA, k), x[1:(length(x)-k)])
    DF = as.data.frame(cbind(lagged, x))
    colnames(DF) <- c( paste0('x-', k), 'x')
    DF[is.na(DF)] <- 0
    return(DF)
  }

  #############################
   ## scale data
  normalize <- function(train, test, feature_range = c(0, 1)) {
    x = train
    fr_min = feature_range[1]
    fr_max = feature_range[2]
    std_train = ((x - min(x) ) / (max(x) - min(x)  ))
    std_test  = ((test - min(x) ) / (max(x) - min(x)  ))
    
    scaled_train = std_train *(fr_max -fr_min) + fr_min
    scaled_test = std_test *(fr_max -fr_min) + fr_min
    
    return( list(scaled_train = as.vector(scaled_train), scaled_test = as.vector(scaled_test) ,scaler= c(min =min(x), max = max(x))) )
    
  }
  
  ##################################
  inverter = function(scaled, scaler, feature_range = c(0, 1)){
    min = scaler[1]
    max = scaler[2]
    n = length(scaled)
    mins = feature_range[1]
    maxs = feature_range[2]
    inverted_dfs = numeric(n)
    
    for( i in 1:n){
      X = (scaled[i]- mins)/(maxs - mins)
      rawValues = X *(max - min) + min
      inverted_dfs[i] <- rawValues
    }
    return(inverted_dfs)
  }

  #############################################

  lstmFit=function(series, k=1, Eposh=50, p=0.66){
  	# transform data to stationarity
  	diffed = diff(series, differences = 1)
  	# creat a lagged dataset (supervise learning)
  	supervised = lags(diffed, k)
  	# split data ( train and test data)
  	N = nrow(supervised)
    n = round(N *p, digits = 0)
    train = supervised[1:n, ]
    test  = supervised[(n+1):N,  ]
    # scale data
    Scaled = normalize(train, test, c(-1, 1))
  
    y_train = Scaled$scaled_train[, 2]
    x_train = Scaled$scaled_train[, 1]
  
    y_test = Scaled$scaled_test[, 2]
    x_test = Scaled$scaled_test[, 1]

     ## fit the model
  
    dim(x_train) <- c(length(x_train), 1, 1)
    dim(x_train)
    X_shape2 = dim(x_train)[2]
    X_shape3 = dim(x_train)[3]
    batch_size = 1
    units = 1
  
    model <- keras_model_sequential() 
    model%>%
    layer_lstm(units, batch_input_shape = c(batch_size, X_shape2, X_shape3), stateful= TRUE)%>%
    layer_dense(units = 1)

    model %>% compile(
    loss = 'mean_squared_error',
    optimizer = optimizer_adam( lr= 0.02 , decay = 1e-6 ),  
    metrics = c('accuracy')
  )
  nb_epoch = Epochs   
  for(i in 1:nb_epoch ){
    model %>% fit(x_train, y_train, epochs=1, batch_size=batch_size, verbose=1, shuffle=FALSE)
    model %>% reset_states()
  }
  L = length(x_test)
  dim(x_test) = c(L, 1, 1)
  
  scaler = Scaled$scaler
  fitted_tr=numeric(dim(x_train)[1])
  predictions = numeric(L)
  
  for(i in 1:L){
    X = x_test[i , , ]
    dim(X) = c(1,1,1)
    # forecast
    yhat = model %>% predict(X, batch_size=batch_size)
    
    # invert scaling
    yhat = inverter(yhat, scaler,  c(-1, 1))
    
    # invert differencing
    yhat  = yhat + Series[(n+i)] 
    
    # save prediction
    predictions[i] <- yhat
  }
  kk=dim(x_train)[1]
  for(i in 1:kk){
    X = x_train[i , , ]
    dim(X) = c(1,1,1)
    # fitt
    yhat = model %>% predict(X, batch_size=batch_size)
    
    # invert scaling
    yhat = inverter(yhat, scaler,  c(-1, 1))
    
    # invert differencing
    yhat  = yhat + Series[(n+i)] 
    
    # save prediction
    fitted_tr[i] <- yhat
  }
 res=list()
 res$fitted_tr=fitted_tr
 res$pred=predictions
 res$x_train=x_train[,1,1]
}

##################################
MRA=function(x,wf="la8",J=4){
	nn=length(x)
	dec=waveslim::mra(x,wf=wf,J=J)
	series=matrix(unlist(dec), nr=nn)
	return(series)
}

mraARIMA=function(x,wf="la8", J=4, p=3, q=3, h=10){
 all_pred=0; all_forecast=0
 series=MRA(x,wf=wf,J=J)
 for(ii in 1:ncol(series)){
 	ts=0
 	ts=series[,ii]
 	mra_fit=forecast::auto.arima(x=as.ts(ts), d=NA,D=NA,
 		   max.p=p, max.q=q, stationary=F,seasonal=F, ic=c("aic"),
 		   allowdrift=F, stepwise=T)
 	mraPredict=mra_fit$fitted
 	mraForecast=forecast::forecast(mra_fit,h=h)
 	all_pred=cbind(all_pred,mraPredict)
 	all_forecast=cbind(all_forecast, as.matrix(mraForecast$mean))
 }
 Forecast=rowSums(all_forecast, na.rm=T)
 Pred=rowSums(all_pred, na.rm=T)
 return(list(Forecast=Forecast, Fitted=Pred))
}

########
# MRA ann

mraANN=function(x,wf="la8", J=4, p=3, P=1, size=2, h=10){
	# p: nonseasonal lag
	# P: seasonal lag
	# size: hidden Size of the hidden layer

 all_pred=0; all_forecast=0
 series=MRA(x,wf=wf,J=J)
 for(ii in 1:ncol(series)){
 	ts=0
 	ts=series[,ii]
 	mra_fit=forecast::nnetar(y=as.ts(ts), p=p, P=P, size=size)
 	mraPredict=mra_fit$fitted
 	mraForecast=forecast::forecast(mra_fit,h=h)
 	all_pred=cbind(all_pred,mraPredict)
 	all_forecast=cbind(all_forecast, as.matrix(mraForecast$mean))
 }
 Forecast=rowSums(all_forecast, na.rm=T)
 Pred=rowSums(all_pred, na.rm=T)
 return(list(Forecast=Forecast, Fitted=Pred))
}
###################################
#   Wavelet LSTM
###################################

###################
# split function
####################

`%notin%` <- Negate(`%in%`)

split_ts <- function (y, test_size = 10) {
  if ("ts" %notin% class(y) | "mts" %in% class(y)) {
    stop("y must be a univariate time series class of 'ts'")
  }
  num_train <- length(y) - test_size
  train_start <- stats::start(y)
  freq <- stats::frequency(y)
  test_start <- min(time(y)) + num_train / freq
  train = stats::ts(y[1:num_train], start = train_start, frequency = freq)
  test = stats::ts(y[(num_train + 1):length(y)], start = test_start,
                   frequency = freq)
  output <- list("train" = train, "test" = test)
  return(output)
}


WaveletLSTM<-function(ts,MLag=12,split_ratio=0.8,wlevels=3,epochs=25,LSTM_unit=20, wf="haar"){
  SigLags<-NULL
  SigLags<-function(Data,MLag){
    ts<-as.ts(na.omit(Data))
    adf1<-adf.test(na.omit(ts))
    if (adf1$p.value>0.05){
      ts<-ts
    } else {
      ts<-diff(ts)
    }
    adf2<-adf.test(ts)
    if (adf2$p.value>0.05){
      ts<-ts
    } else {
      ts<-diff(ts)
    }

    CorrRes<-NULL
    for (i in 1:MLag) {
      # i=1
      ts_y<-dplyr::lag(as.vector(ts), i)
      t<-cor.test(ts,ts_y)
      corr_res<-cbind(Corr=t$statistic,p_value=t$p.value)
      CorrRes<-rbind(CorrRes,corr_res)
    }
    rownames(CorrRes)<-seq(1:MLag)
    Sig_lags<-rownames(subset(CorrRes,CorrRes[,2]<=0.05))
    maxlag<-max(as.numeric(Sig_lags))
    return(list(Result=as.data.frame(CorrRes),SigLags=as.numeric(Sig_lags),MaxSigLag=maxlag))
  }
  ntest<-round(length(ts)*(1-split_ratio), digits = 0)
  Split1 <- caretForecast::split_ts(as.ts(ts), test_size = ntest)
  train_data1 <- Split1$train
  test_data1 <- Split1$test
  Wvlevels<-wlevels
  WaveletSeries <- MRA(ts,wf,Wvlevels)
  # mraout <- wavelets::modwt(as.vector(ts), filter="haar", n.levels=Wvlevels)
  # WaveletSeries <- cbind(do.call(cbind,mraout@W),mraout@V[[Wvlevels]])
  ts_fitted<-NULL
  ts_foreast<-NULL

  for (j in 1:ncol(WaveletSeries)) {
    w<-as.ts(WaveletSeries[,j])
    maxl<-SigLags(Data=w,MLag = MLag)$MaxSigLag
    model<-TSLSTM::ts.lstm(ts=w,xreg = NULL,tsLag=maxl,xregLag = 0,LSTMUnits=LSTM_unit, Epochs=epochs,SplitRatio =split_ratio)
    model_par<-rbind(model_par,model$Param)
    ts_fitted<-model$TrainFittedValue
    ts_foreast<-model$TestPredictedValue
  }

  trainf <- apply(ts_fitted,1,sum)
  testf <- apply(ts_foreast,1,sum)
  return(list(Train_actual=train_data1,Test_actual=test_data1,Train_fitted=trainf))
}

#################################################################################################
#################################################################################################
## Recherche des meilleurs val de p et size au sens RMSE

bestMod=function(series,pMax=10,sizeMax=10){
	wwf=c("haar","d4","d6","d8","la8","d16","la16")
	tt=expand.grid(1:pMax,1:sizeMax,wwf)
	n=NROW(tt)
	rmse_ij=0
	for(i in 1:n){
		fit=mraANN(series,wf=tt[i,3],p=tt[i,1],size=tt[i,2])$Fitted
		rmse_ij=c(rmse_ij, Metrics::rmse(series,fit))
	}
	rmseij=rmse_ij[-1]
	idx=which.min(rmseij)
	bestPar=tt[idx,1:3]
	cat("\n")
	cat("======================================================================\n")
	cat(" Best model with RMSE :", "p = ", bestPar$Var1, "size = ", bestPar$Var2, "\n")
	cat(" Best wavelet filter: ", bestPar$Var3[idx],"\n")
    cat("======================================================================\n")
	return(invisible(list(RMSE=cbind(tt, RMSE=rmse_ij[-1]), bestPar=idx)))
}

#######################################################################################
#         select best wavelet filter and best level of decomposition
#######################################################################################

Wav_select <- function(x, wf=c("haar","d4","d6","d8","la8","d16","la16","la20"),
                       crit="rmse", type="mowdt"){
  n=length(x)
  jj=ceiling(log2(n))
  tt=expand.grid(wf,1:jj)
  p=NROW(tt)
  MV=matrix(0,nr=p,nc=8)
  for(i in 1:p){
   if(type=="modwt"){
     xt=matrix(unlist(waveslim::modwt(x,wf=tt[i,1],J=tt[i,2])), nr=n)
     xt_fit=rowSums(xt)
     all_Metrics=AllMetrics::all_metrics(x,xt_fit)
     MV[i,]=as.numeric(all_Metrics[,2])
   }else if(type=="mra"){
     xt=matrix(unlist(waveslim::mra(x,wf=tt[i,1],J=tt[i,2])))
     xt_fit=rowSums(xt)
     all_Metrics=AllMetrics::all_metrics(x,xt_fit)
     MV[i,]=as.numeric(all_Metrics[,2])
   }
     #xt=matrix(unlist(xt), nr=n)
     #xt_fit=rowSums(xt)
     #all_Metrics=AllMetrics::all_metrics(x,xt_fit)
    # "Metric"=all_Metrics[,1]
    # "Metric value"=all_Metrics[,2]
     #MV=rbind(MV,as.numeric(all_Metrics[,2]))
   } 
  colnames(MV)=c("RMSE", "RRMSE", "MAE",  "MAPE", "MASE" ,"NSE" ,"WI" ,"LME")
  res=cbind(tt,MV)
  idx=which.min(res[,toupper(crit)])
  cat("\n====================================================\n")
  cat(" Respect to RMSE criteria, the best wavelet filter is ", res[idx,1], " \n")
  cat("  and the best level of decomposition is ", res[idx,2]," \n")
  return(invisible(res))
}

 
