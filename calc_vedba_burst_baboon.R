# This script processes acceleration data from Movebank. It retrieves data for a specified time range,
# merges it with metadata, cleans and processes the data, parses acceleration components, and calculates
# the average Vectorial Dynamic Body Acceleration (VEDBA) and its logarithm for further analysis.

library(move2)      # For accessing Movebank data
library(dplyr)      # For data manipulation
library(lubridate)  # For working with date and time
library(stringr)    # For string manipulation

# # Step 1: Define parameters for data retrieval
# date_start <- as.POSIXct("2024-11-01 00:00:00", tz = "UTC")  # Start time for data retrieval
# date_end <- as.POSIXct("2024-11-01 23:59:59", tz = "UTC")    # End time for data retrieval
# study_id <- 3445611111  # Movebank study ID
# 
# # Step 2: Download acceleration data from Movebank
# acc_data <- movebank_download_study(
#   study_id = study_id,               # Specifies the study to download
#   sensor_type_id = "acceleration",   # Retrieves acceleration data
#   timestamp_start = date_start,      # Start time for filtering data
#   timestamp_end = date_end           # End time for filtering data
# )

load("VTK_baboon_example_data.RData")

acc_data <- acc_v0

# Step 2a: Adding group_id from metadata 
metadata <- mt_track_data(gps_v0)
acc_v0 <- acc_v0 %>%
  left_join(metadata %>% 
              dplyr::select(individual_local_identifier, tag_local_identifier, group_id, sex), 
            by = c("individual_local_identifier" = "individual_local_identifier"))  # **Merging group_id with the original data**

# Step 3: Clean and process the data
acc_v0 <- acc_v0 %>%
  rename(tag = individual_local_identifier,         # Renaming columns for easier reference
         group = group_id,                          # **Added group column (group_id)**
         local_timestamp = timestamp,               # Timestamp of data
         eobs_accelerations_raw = eobs_accelerations_raw) %>% 
  select(tag, group, local_timestamp, eobs_accelerations_raw)  # **Include group column in the selected columns for visualization**

acc_v0$local_timestamp <- as.POSIXct(acc_v0$local_timestamp, tz = "UTC")  # Ensure proper datetime format

acc_v0 <- acc_v0 %>% filter(eobs_accelerations_raw != "")  # Remove rows with missing acceleration data

# Step 4: Parse accelerations into X, Y, Z components
d2 <- as.data.frame(str_split(acc_v0$eobs_accelerations_raw, " ", simplify = TRUE))  # Split raw data into components

for (i in 1:ncol(d2)) {
  d2[, i] <- as.numeric(as.character((d2[, i])))  # Convert columns to numeric format
}

names(d2) <- paste(
  rep(c("x", "y", "z"), ncol(d2) / 3),                # Name columns as X, Y, Z components
  rep(1:(ncol(d2) / 3), each = 3), sep = ""          # Add sample indices to names
)

d2$local_timestamp <- acc_v0$local_timestamp  # Add timestamp for alignment
d2$tag <- acc_v0$tag                          # Add tag for individual identification

# Remove incomplete bursts
inds <- complete.cases(d2)  # Identify rows with complete data
acc_v0 <- acc_v0[inds, ]  # Retain only complete rows in original data
d2 <- d2[inds, ]              # Retain only complete rows in parsed data

# Split parsed data into separate X, Y, Z data frames
x_d <- d2[, grepl('x', names(d2))]  # Extract X-axis data
y_d <- d2[, grepl('y', names(d2))]  # Extract Y-axis data
z_d <- d2[, grepl('z', names(d2))]  # Extract Z-axis data

# Step 5: Calculate average VEDBA and log VEDBA
dy_acc <- function(vect, win_size = 7) {
  pad_size <- win_size / 2 - 0.5  # Half-window size for padding
  padded <- c(rep(NA, pad_size), vect, rep(NA, pad_size))  # Add padding
  sapply(seq_along(vect), function(i) vect[i] - mean(padded[i:(i + 2 * pad_size)], na.rm = TRUE))  # Detrend data
}

acc_v0$ave_vedba <- apply(
  sqrt(
      apply(x_d, 1, FUN = function(x) abs(dy_acc(x)))^2 +  # Calculate VEDBA for X-axis
      apply(y_d, 1, FUN = function(x) abs(dy_acc(x)))^2 +  # Calculate VEDBA for Y-axis
      apply(z_d, 1, FUN = function(x) abs(dy_acc(x)))^2    # Calculate VEDBA for Z-axis
  ),
  2,
  FUN = mean  # Take the mean across all samples in a burst
)

acc_v0$log_vedba <- log(acc_v0$ave_vedba)  # Log-transform the average VEDBA for analysis

acc_v1 <- acc_v0
saveRDS(acc_v1,"acc_v1.RDS")
