# evaluate time-dependent slp-sst relationships affecting Bering Sea ecosystem

library(tidyverse)
library(sde)
library(rstan)
library(ggpubr)
library(pracma)
library(nlme)

# plot settings
theme_set(theme_bw())

cb <- c("#999999", "#E69F00", "#56B4E9", "#009E73", "#F0E442", "#0072B2", "#D55E00", "#CC79A7")

# load slp & sst data
slp <- read.csv("./Data/monthlySLPanomalies.csv", row.names = 1) %>%
  group_by(Month) %>%
  mutate(scaled_slp = scale(month.anom)[,1]) %>%
  ungroup()

goa.sst <- read.csv("./Data/goa.monthlySSTanomalies.csv", row.names = 1) %>%
  filter(Year >= 1948) %>%
  mutate(dec.yr = Year + (Month - 0.5)/12) %>%
  group_by(Month) %>%
  mutate(scaled_sst = scale(month.anom)[,1]) %>%
  ungroup() %>%
  mutate(detr_scaled_sst = resid(lm(scaled_sst ~ dec.yr)))

ebs.sst <- read.csv("./Data/ebs.monthlySSTanomalies.csv", row.names = 1) %>%
  filter(Year >= 1948) %>%
  mutate(dec.yr = Year + (Month - 0.5)/12) %>%
  group_by(Month) %>%
  mutate(scaled_sst = scale(month.anom)[,1]) %>%
  ungroup() %>%
  mutate(detr_scaled_sst = resid(lm(scaled_sst ~ dec.yr)))

# plot
plot_slp <- slp %>%
  mutate(dec.yr = Year + (Month - 0.5)/12,
         variable = "SLP") %>%
  rename(anomaly = scaled_slp) %>%
  dplyr::select(dec.yr, anomaly, variable)

plot_goa <- goa.sst %>%
  mutate(variable = "GOA SST") %>%
  rename(anomaly = scaled_sst) %>%
  dplyr::select(dec.yr, anomaly, variable)

plot_ebs <- ebs.sst %>%
  mutate(variable = "EBS SST") %>%
  rename(anomaly = scaled_sst) %>%
  dplyr::select(dec.yr, anomaly, variable)

plot_dat <- rbind(plot_slp, plot_goa, plot_ebs)

ggplot(plot_dat, aes(dec.yr, anomaly)) +
  geom_line() +
  facet_wrap(~variable, ncol = 1) +
  geom_hline(yintercept = 0, lty = 2, col = "red") # looks like SST needs to be detrended - will do that in t




# define functions
# ar_ls calculates the process deviations after
# accounting for forcing variables and autocorrelation,
# (1-gamma)
ar_ls = function(time,forcing,gamma) {
  #S(t+1) = (1-GAMMA*DT)*S(t) + F(t)*DT
  forcing = c(forcing - mean(forcing))
  T=length(forcing)
  sig = 0
  
  for(t in 1:(T-1)) {
    #sig[t+1] = -theta*sig[t] + forcing[t]
    sig[t+1] = (1-gamma)*sig[t] + forcing[t]
  }
  
  # next estimates are linearly de-trended
  #s.sig = sig
  sig = sig - lm(sig ~ time)$fitted.values
  # interpolate output on the original time grid
  s.sig=(sig[-1]+sig[-T])/2 # midpoint
  # final step is normalize
  s.sig=s.sig/sd(s.sig)
  return(s.sig)
}

# vector of decorrelation scales
decor <- 1:12

# object to catch results
cor.out <- p.out <-  data.frame()

# create sst df
sst <- plot_dat %>%
  filter(variable != "SLP") %>%
  rename(date = dec.yr,
         sst = anomaly,
         region = variable)

regions <- unique(sst$region)

for(r in 1:length(regions)){ # loop through regions
# r <- 1  
# set up data   
  
temp.sst <- sst %>%
  filter(region == regions[r])

  dat <- data.frame(date = temp.sst$date,
                    sst = temp.sst[,2],
                    slp.0 = slp$month.anom,
                    slp.1 = c(NA, slp$month.anom[1:919]),
                    slp.2 = c(NA, NA, slp$month.anom[1:918]),
                    slp.3 = c(NA, NA, NA, slp$month.anom[1:917]),
                    slp.4 = c(NA, NA, NA, NA, slp$month.anom[1:916]),
                    slp.5 = c(NA, NA, NA, NA, NA, slp$month.anom[1:915]),
                    slp.6 = c(NA, NA, NA, NA, NA, NA, slp$month.anom[1:914]))
  
  
  # and drop NAs
  dat <- na.omit(dat)

for(l in 3:ncol(dat)){ # loop through lags
# l <- 1
for(i in 1:length(decor)){ # loop through decorrelation scale
  # i <- 1
pred_ts = ar_ls(1:nrow(dat), forcing=dat[,l],
                gamma = 1/decor[i])


pred.sst = data.frame(t = dat$date,
                      sst = dat$sst,
                      integrated.slp = c(0,-as.numeric(pred_ts))) ## NB - reversing the sign of integrated SLP


cor.out <- rbind(cor.out, 
                 data.frame(region = regions[r],
                            lag = l - 3,
                            decor = decor[i],
                            cor = cor(pred.sst$sst, pred.sst$integrated.slp)))

# and p-values
mod <- nlme::gls(sst ~ integrated.slp, correlation = corAR1(), data = pred.sst)

p.out <- rbind(p.out, 
                 data.frame(region = regions[r],
                            lag = l - 3,
                            decor = decor[i],
                            p_value = summary(mod)$tTable[2,4]))

}

}

}

cor.out



ggplot(cor.out, aes(decor, cor, color = as.factor(lag))) + 
  geom_line() +
  geom_point() +
  facet_wrap(~region) # very different decorrelation scales!

ggsave("./Figures/sst-slp_lag_decorrelation_by_region.png", width = 9, height = 6, units = 'in')

# plot EBS and GOA for report

# 
# ggplot(filter(cor.out, region %in% c("Eastern_Bering_Sea", "Gulf_of_Alaska")), aes(decor, cor, color = as.factor(lag))) + 
#   geom_line() +
#   geom_point() +
#   facet_wrap(~region) + # very different decorrelation scales!
#   labs(x = "Decorrelation scale (months)",
#        y = "Correlation coefficient",
#        color = "Lag (months)") +
#   scale_x_continuous(breaks = 1:12)
#   
# ggsave("./Figures/sst-slp_lag_decorrelation_by_region_EBS_GOA.png", width = 9, height = 6, units = 'in')

decor.use <- cor.out %>%
  group_by(region) %>%
  summarise(decor = decor[which.max(cor)])

# check SST decor scale for GOA and EBS
# report.sst <- sst


# decor.EBS <- acf(report.sst$monthly.anom[report.sst$region == "EBS SST"])

# decor.GOA <- acf(report.sst$monthly.anom[report.sst$region == "GOA SST"])


# now loop through and fit at the best decorrelation scale for each region
predicted.sst <- data.frame()

for(i in 1:nrow(decor.use)){

  # i <- 1
  
  temp.sst <- sst %>%
    filter(region == decor.use$region[i])
  
  dat <- data.frame(date = temp.sst$date,
                    sst = temp.sst[,2],
                    slp.0 = slp$month.anom)
  
  pred_ts = ar_ls(1:nrow(dat), forcing=dat$slp.0,
                  gamma = 1/decor.use$decor[i])
  
  
  predicted.sst = rbind(predicted.sst,
                        data.frame(region = decor.use$region[i],
                        t = temp.sst$date,
                        sst = temp.sst$sst,
                        integrated.slp = c(0,-as.numeric(pred_ts))))

}
  
predicted.sst <- predicted.sst %>%
  pivot_longer(cols = c(-region, -t))

ggplot(predicted.sst, aes(t, value, color = name)) +
  geom_line() +
  scale_color_manual(values = cb[c(2,6)], labels = c("Integrated SLP", "SST")) +
  facet_wrap(~region)
  # could add correlations for each!
  
# # plot EBS and GOA for report
# ggplot(filter(predicted.sst, region %in% c("Eastern_Bering_Sea", "Gulf_of_Alaska")), aes(t, value, color = name)) +
#   geom_hline(yintercept = 0) +
#   geom_line() +
#   scale_color_manual(values = cb[c(2,6)], labels = c("Integrated SLP", "SST")) +
#   facet_wrap(~region, scales = "free_y", ncol = 1) +
#   theme(legend.title = element_blank(),
#         axis.title.x = element_blank()) +
#   ylab("Anomaly")
# 
# ggsave("./figs/EBS_GOA_SST_integrated_SLP_time_series.png", width = 7, height = 5)



# get statistics to report
## first ebs
temp.ebs <- predicted.sst %>%
  filter(region == "EBS SST") %>%
  dplyr::select(t, name, value) %>%
  pivot_wider(names_from = name)

cor(temp.ebs$sst, temp.ebs$integrated.slp) # r = 0.18

mod <- nlme::gls(sst ~ integrated.slp, corAR1(), data = temp.ebs)
summary(mod)$tTable[2,4] # p = 0.08

## now goa
temp.goa <- predicted.sst %>%
  filter(region == "GOA SST") %>%
  dplyr::select(t, name, value) %>%
  pivot_wider(names_from = name)

cor(temp.goa$sst, temp.goa$integrated.slp) # r = 0.365

mod <- nlme::gls(sst ~ integrated.slp, corAR1(), data = temp.goa)
summary(mod)$tTable[2,4] # p = 2.31748e-07

# set window length
# calculate AR(1) and SD
out_ar <- data.frame(region = c(rep("GOA", 461*2), rep("EBS", 461*2)),
                     time_series = c(rep("SST", 461), rep("int_SLP", 461), rep("SST", 461), rep("int_SLP", 461)),
                  AR1 = c(sapply(rollapply(temp.goa$sst, width = 460, FUN = acf, lag.max = 1, plot = FALSE)[,1], "[[",2),
                          sapply(rollapply(temp.goa$integrated.slp, width = 460, FUN = acf, lag.max = 1, plot = FALSE)[,1], "[[",2),
                          sapply(rollapply(temp.ebs$sst, width = 460, FUN = acf, lag.max = 1, plot = FALSE)[,1], "[[",2),
                          sapply(rollapply(temp.ebs$integrated.slp, width = 460, FUN = acf, lag.max = 1, plot = FALSE)[,1], "[[",2)))
                  
                  
 out_sd <- data.frame(t = rep(temp.goa$t, 4), 
                      region = c(rep("GOA", 920*2), rep("EBS", 920*2)),
                      time_series = c(rep("SST", 920), rep("int_SLP", 920), rep("SST", 920), rep("int_SLP", 920)),
                      SD = c(rollapply(temp.goa$sst, width = 460, FUN = sd, fill = NA),
                             rollapply(temp.goa$integrated.slp, width = 460, FUN = sd, fill = NA),
                             rollapply(temp.ebs$sst, width = 460, FUN = sd, fill = NA),
                             rollapply(temp.ebs$integrated.slp, width = 460, FUN = sd, fill = NA)))


 
 # Calculate windows
 t <- na.omit(out_sd) %>% pull(t)
 
 # Make data frame of ar1
 cbind(t, out_ar) -> ar.dat
 
 # Join
 left_join(out_sd, ar.dat, relationship = "many-to-many") -> ar.sd.dat
   
   
ggplot(ar.sd.dat, aes(t, AR1, color = time_series)) +
  facet_wrap(~region, scales = "free_y", nrow= 2)+
  geom_line()

ggplot(ar.sd.dat, aes(t, SD, color = time_series)) +
  facet_wrap(~region, scales = "free_y", nrow = 2)+
  geom_line()

ggplot() +
  geom_line(ar.sd.dat %>% filter(time_series == "int_SLP"), mapping = aes(t, SD, color = time_series))+
  geom_line(ar.sd.dat %>% filter(time_series == "SST"), mapping = aes(t, AR1, color = time_series))+
  facet_wrap(~region, scales = "free_y", nrow = 2)+
  ylab("Value")+
  scale_color_manual(values = c("salmon", "steelblue"), labels = c("int_SLP SD", "SST AR1"))


## integrate slp to recreate PDO

# load PDO

pdo <- read.csv("./Data/pdo.timeseries.ersstv5.csv") 

names(pdo) <- c("date", "pdo")

pdo <- pdo %>%
  mutate(year = str_sub(date, 1, 4),
         month = str_sub(date, 6, 7)) %>%
  dplyr::select(year, month, pdo) %>%
  filter(year >= 1900, 
         pdo > -999)

pdo$time_step <- 1:nrow(pdo)

# look at AR(1) patterns depending on window length

nrow(pdo) / 2 # 750 ~ 1/2 time series

windows <- seq(150, 750, by = 50)

out <- data.frame()

for(i in 1:length(windows)){
  
  ar.temp <- sapply(rollapply(pdo$pdo, width = windows[i], FUN = acf, lag.max = 1, plot = FALSE)[,1], "[[",2)
  mean.year <- rollapply(as.numeric(pdo$year), width = windows[i], FUN = mean)
  
  out <- rbind(out, 
               data.frame(year = mean.year, 
                          ar1 = ar.temp,
                          window = as.character(windows[i])))
  
}

ggplot(out, aes(year, ar1, color = window)) +
  geom_line() +
  scale_color_viridis_d()

ggplot(out, aes(year, ar1)) +
  geom_line() +
  facet_wrap(~window, scales = "free_y") +
  geom_vline(xintercept = 1988.5, lty = 2)

#### integrate slp to predict PDO --------------

pdo <- pdo %>%
  mutate(dec.yr = as.numeric(year) + (as.numeric(month) - 0.5)/12)

# reload slp
slp <- read.csv("./Data/monthlySLPanomalies.csv", row.names = 1) %>%
  mutate(scaled_slp = scale(month.anom)[,1]) %>%
  mutate(dec.yr = Year + (Month - 0.5)/12)


dat <- left_join(slp, pdo) %>%
  dplyr::select(dec.yr,
                scaled_slp,
                pdo)

decor.use <- 6 # from Di Lorenzo and Ohman



  pred_ts = ar_ls(1:nrow(dat), forcing=dat$scaled_slp,
                  gamma = 1/decor.use)
  
  
  predicted.pdo = data.frame(date = dat$dec.yr,
                          pdo = dat$pdo,
                          integrated.slp = c(0,-as.numeric(pred_ts)))
  
predicted.pdo <- predicted.pdo %>%
  pivot_longer(cols = -date)

ggplot(predicted.pdo, aes(date, value, color = name)) +
  geom_line() +
  scale_color_manual(values = cb[c(2,6)], labels = c("Integrated SLP", "PDO")) 

predicted.pdo <- predicted.pdo %>%
  pivot_wider(names_from = name,
              values_from = value)

cor(predicted.pdo$pdo, predicted.pdo$integrated.slp) # r = 0.521

mod <- nlme::gls(pdo ~ integrated.slp, corAR1(), data = predicted.pdo)
summary(mod)$tTable[2,4] # p = 0.023

## evaluate AR(1) patterns of PDO & integrated slp ----------------

# look at AR(1) patterns depending on window length

nrow(predicted.pdo) / 2 # 460 = 1/2 time series

windows <- seq(150, 450, by = 50)

out_predicted_pdo <- data.frame()

for(i in 1:length(windows)){
  
  ar.temp_pdo <- sapply(rollapply(predicted.pdo$pdo, width = windows[i], FUN = acf, lag.max = 1, plot = FALSE)[,1], "[[",2)
  ar.temp_integrated.slp <- sapply(rollapply(predicted.pdo$integrated.slp, width = windows[i], FUN = acf, lag.max = 1, plot = FALSE)[,1], "[[",2)  
  mean.year <- rollapply(predicted.pdo$date, width = windows[i], FUN = mean)
  
  out_predicted_pdo <- rbind(out_predicted_pdo, 
               data.frame(year = mean.year, 
                          ar1_pdo = ar.temp_pdo,
                          ar1_integrated.slp = ar.temp_integrated.slp,
                          window = as.character(windows[i])))
  
}

out_predicted_pdo <- out_predicted_pdo %>%
  pivot_longer(cols = c(-year, -window))

ggplot(out_predicted_pdo, aes(year, value, color = name)) +
  geom_line() +
  scale_color_manual(values = cb[c(2,6)]) +
  facet_wrap(~window, scales = "free_y")

ggplot(out, aes(year, ar1)) +
  geom_line() +
  facet_wrap(~window, scales = "free_y")

## look at AR1 and SD of winter SLP time series --------------

# reload slp
slp <- read.csv("./Data/monthlySLPanomalies.csv", row.names = 1) 

# limit to winter months and assign year corresponding to January and remove incomplete 1948 

slp <- slp %>%
  filter(Month %in% c(11,12,1:3)) %>%
  mutate(winter.year = if_else(Month %in% c(11,12), Year+1, Year)) %>%
  filter(winter.year > 1948) %>%
  group_by(winter.year) %>%
  summarise(slp = mean(month.anom))

slp$slp <- as.vector(scale(slp$slp))

ggplot(slp, aes(winter.year, slp)) +
  geom_point() +
  geom_line()

acf(slp$slp) # white noise!

# plot 15-yr windows
ar.15 <- sapply(rollapply(slp$slp, width = 15, FUN = acf, lag.max = 1, plot = FALSE)[,1], "[[",2)
mean.year <- rollapply(as.numeric(slp$winter.year), width = 15, FUN = mean)
sd.15 <- rollapply(as.numeric(slp$slp), width = 15, FUN = sd)

plot_dat <- data.frame(year = mean.year,
                       ar.15 = ar.15,
                       sd.15 = sd.15)

ggplot(plot_dat, aes(year, ar.15)) +
  geom_point() +
  geom_line()
# around 0, which we expect

ggplot(plot_dat, aes(year, sd.15)) +
  geom_point() +
  geom_line()

# matches past papers

# how does sd in slp link to ar1 in sst?

sd <- seq(0.65, 1.25, by = 0.01)

out <- data.frame() 

for(i in 1:length(sd)){

  temp.slp <- rnorm(n = 10000, mean = 0, sd = sd[i])
  
  pred_ts = ar_ls(1:10000, forcing=temp.slp,
                  gamma = 1/4)
  
  out <- rbind(out,
               data.frame(sd = sd[i],
                          ar = ar(pred_ts, order.max = 1, AIC = F)$ar))
  
}

ggplot(out, aes(sd, ar)) +
  geom_point() +
  geom_line()

# no relationship with this model!