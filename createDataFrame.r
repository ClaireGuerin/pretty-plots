rm(list = ls())

library(tidyverse)
library(fs)
library(patchwork)
library(rlang)
# library(GGally)
# library(readr)
# library(stringr)
# library(glue)
# library(dplyr)
# library(purrr)
# library(ggplot2)

# Read output files except phenotypes ====
make_tibble_from_file <- function(filename){
  var_name <- str_match(filename, "(?<=_).*(?=\\.)")
  var_tibble <- read_csv(filename, col_names = c(paste(var_name,"_mean", sep = ""), paste(var_name, "_variance", sep = "")))
}

read_non_phenotype_data <- function(path2dir){
  setwd(path2dir)
  # list output files of interest
  all_output_files <- path_file(dir_ls(my_dir, glob = "*out*"))
  sub_output_files <- all_output_files[all_output_files != "out_phenotypes.txt"]
  
  # Make full tibble
  my_tibble <- make_tibble_from_file(sub_output_files[1])
  indexed_tibble <- 1:dim(my_tibble)[1] %>% 
    bind_cols(my_tibble) %>%
    rename(generation = ...1)
  
  for(variable_file in sub_output_files[-1]){
    indexed_tibble <- indexed_tibble %>% 
      bind_cols(make_tibble_from_file(variable_file))
  }
  
  return(indexed_tibble)
}


# Read phenotype data ====
read_phenotype_data <- function(path2file, method = 3){
  phenotypes <- read_csv(path2file, col_names = FALSE)
  phenotypes_range <- 1:(dim(phenotypes)[2]/2)
  phenotypes_as_strings <- lapply(phenotypes_range, toString)
  phenotypes_names <- "phenotype" %>% 
    paste(phenotypes_as_strings, sep = "")
  phenotypes_mean_colnames <- phenotypes_names %>% 
    paste("_mean", sep="")
  phenotypes_variance_colnames <- phenotypes_names %>% 
    paste("_variance", sep="")
  column_new_names <- c(phenotypes_mean_colnames, phenotypes_variance_colnames)
  
  if (method == 1) {
    ## My method with dplyr rename
    ## WARNING: Fails
    column_old_names <- colnames(phenotypes)
    command_renaming <- column_new_names %>% paste("=") %>% paste(column_old_names)
    phenotypes_renamed <- phenotypes %>% rename(!!!rlang:parse_exprs(command_renaming))
  } else if (method == 2) {
    ## Raph's method with base R
    ## WARNING: might lead to errors down the line
    colnames(phenotypes) <- column_new_names
    phenotypes_renamed <- phenotypes
  } else if (method == 3) {
    ## Raph's method with dplyr rename
    #1: create a vector of the current column names
    new_names <- colnames(phenotypes) 
    #2: name the vector elements with their soon-to-be new names
    names(new_names) <- column_new_names 
    #3: evaluate the named vector to assign column names to phenotypes
    phenotypes_renamed <- phenotypes %>% 
      rename(!!new_names) 
  }
  
  generations_range <- 0:(dim(phenotypes)[1]-1)
  final_df <- bind_cols(generations_range, phenotypes_renamed) %>% rename(generation = ...1)
  
  return(final_df)
  
}

# Single simulation Plots ====

plot_non_phen <- function(dat, var_name){
  var_average <- paste(var_name, "_mean", sep = "")
  var_variance <- paste(var_name, "_variance", sep = "")
  keep_data <- dat %>% 
    select(generation, var_average, var_variance) %>%
    mutate(var_deviation = sqrt(!!rlang::parse_expr(var_variance)))
  p <- ggplot(keep_data) +
    geom_ribbon(mapping = aes(x = generation,
                              ymin = !!rlang::parse_expr(var_average) - var_deviation,
                              ymax = !!rlang::parse_expr(var_average) + var_deviation),
                colour = "gray") +
    geom_point(mapping = aes(x = generation, y = !!rlang::parse_expr(var_average)),
               colour = "seagreen3") +
    xlab("Time (number of generations)") +
    ylab(str_to_sentence(var_name)) +
    theme_classic()
  return(p)
}

plot_phenotype <- function(phen_dat, phen_index){
  pheno_average <- paste("phenotype", phen_index, "_mean", sep = "")
  pheno_variance <- paste("phenotype", phen_index, "_variance", sep = "")
  
  p <- ggplot(data = phen_dat) +
    geom_ribbon(mapping = aes(x = generation, ymin = !!rlang::parse_expr(pheno_average) - !!rlang::parse_expr(pheno_variance), ymax = !!rlang::parse_expr(pheno_average) + !!rlang::parse_expr(pheno_variance)),
                colour = "gray"
    ) +
    geom_point(mapping = aes(x = generation, y = !!rlang::parse_expr(pheno_average)), 
               size = 0.1,
               colour = "indianred3"
    ) +
    xlab("Time (number of generations)") +
    ylab(paste("Phenotype", phen_index, sep = " ")) +
    theme_classic()
  
  return(p)
}

plot_phenotype_smooth <- function(phen_dat, phen_index){
  phen_average <- paste("phenotype", phen_index, "_mean", sep = "")
  
  p <- ggplot(data = phen_dat, 
              aes(x = generation, y = !!rlang::parse_expr(phen_average))) +
    geom_smooth(colour = "coral1") +
    theme_classic()
  
  return(p)
}

# Read data from multiple simulations ==== 
# ... and store some kind of summary in a tibble

reorganize_phenotype_summary <- function(phen_dat){
  summary <- phen_data %>%
    pivot_longer(cols = colnames(.)[-1], names_to = "var_name") %>% 
    # organize by column names (except generation number)
    mutate(
      var_type = str_remove(var_name, "^.*_"),
      var_name = str_remove(var_name, "_.*$")
    ) %>% 
    # create new column "var_type" that indicates mean or variance, and remove the _mean or _variance indication in "name" column
    mutate(value = ifelse(var_type == "variance", sqrt(value), value)) %>% 
    # apply square root to value if var_type is variance
    mutate(var_type = if_else(var_type == "variance", "std", var_type)) %>%
    group_by(var_name, var_type) %>% 
    # group by both variable name and type, thus creating 8 groups (if there are 4 phenotypes accounted for)
    summarize(mean = mean(value)) %>% 
    # for each group, calculate the mean value
    ungroup() %>%
    pivot_wider(names_from = "var_type", values_from = "mean") 
  # re-organize data frame so as to have one row by phenotype, and average value for phen mean and variance in 2 separate columns
  
  return(summary)
}

### example
setwd("/home/claire/Desktop/technofirstbatch/technology_alphaResources0.1betaTech0.1p0.1atech2.0btech1.0q0.1gamma0.01rb2.0")
phen_data <- read_phenotype_data("out_phenotypes.txt", 3)
phen_data %>% head
reorganize_phenotype_summary(phen_data)
###

# 1: loop over folders
extract_global_mean_and_variance <- function(file_path, is_phen = FALSE){
  variable_name <- str_match(file_path,"(?<=/out_).*(?=\\.)")
  
  # mean # name
  # function(x) mean(x) # lambda simple
  # function(x) { mean(sqrt(x)) } # lambda complex
  # ~ mean(.x) # formula
  
  if (is_phen) {
    phen_data <- read_phenotype_data(file_path, 3)
    data_summary <- reorganize_phenotype_summary(phen_data)
    
  } else {
    mean_column <- paste(variable_name, "_mean", sep = "")
    variance_column <- paste(variable_name, "_variance", sep = "")
    variable_tibble <- read_csv(file_path, col_names = c(mean_column, variance_column))
    m <- summarize(variable_tibble, mean = mean(!!rlang::parse_expr(mean_column)))
    v <- summarize(variable_tibble, std = mean(sqrt(!!rlang::parse_expr(variance_column))))
    data_summary <- bind_cols(var_name = variable_name[,1], m, v)
  }
  
  return(data_summary)
}

extract_global_mean_and_variance("out_phenotypes.txt", TRUE)
test_demography <- extract_global_mean_and_variance("out_demography.txt")
extract_global_mean_and_variance(output_files_list[1])


extract_meta_data <- function(dir_path = "."){
  files_list <- dir_ls(dir_path, type = "file")
  output_files_list <- files_list[str_detect(files_list,"(?<=/)out_(?!phenotypes)")]
  
  # Collect summaries of non-phenotypic data
  global_summary <- output_files_list %>%
    map_dfr(extract_global_mean_and_variance) %>%
    bind_rows(extract_global_mean_and_variance(files_list[str_detect(files_list,"(?<=/)out_phenotypes.txt")], TRUE))
  
  # Add phenotype summary
  #phenotype_output_file <- "out_phenotypes.txt"
  #phenotype_tibble <- extract_global_mean_and_variance(phenotype_output_file)
  
  # Join
  
  return(global_summary)
  
}

extract_meta_data(".") 
setwd("~")
my_dir = "/home/claire/Desktop/technofirstbatch/technology_alphaResources0.1betaTech0.1p0.1atech2.0btech1.0q0.1gamma0.01rb2.0"
extract_meta_data(my_dir)

# 2: extract important information:
## - mean value from generation x (user-defined) to end
## - fitness parameter values

gather_pars_and_output_in_single_row <- function(path_to_sim){
  output_data <- extract_meta_data(path_to_sim) %>%
    pivot_longer(cols = c(mean, std), names_to = "val_type") %>%
    mutate(var_name = paste(var_name, "_", val_type, sep = "")) %>%
    select(-val_type) %>% 
    pivot_wider(names_from = var_name, values_from = value)
  
  input_data <- read_csv(paste(path_to_sim,"fitness_parameters.txt", sep = "/"), col_names = c("par_name","par_val")) %>% 
    pivot_wider(names_from = par_name, values_from = par_val)
  
  return(bind_cols(input_data, output_data))
}

gather_pars_and_output_in_single_row(my_dir)

setwd("~")
my_dir = "/home/claire/Desktop/technofirstbatch/technology_alphaResources0.1betaTech0.1p0.1atech2.0btech1.0q0.1gamma0.01rb2.0"
gather_pars_and_output_in_single_row(my_dir)
extract_meta_data(my_dir)

# list all sim folders
collect_all_simulations_data <- function(path_to_all_dirs){
  dir_ls(path_to_all_dirs, type = "directory") %>%
    map_dfr(gather_pars_and_output_in_single_row)
}

#==== Get data from all simulations ====

data_set <- collect_all_simulations_data("/home/claire/Dropbox/PhD/Results/technotest")

# Get sub-tibble for 2 varying pars, all others fixed

#==== Filtering (Raph's code) ====
# Fake data frame
# data <- expand_grid(a = c(1, 2, 3), b = c(1, 2, 3), c = c(1, 2, 3), d = c(1, 2, 3))
# data$z <- rnorm(nrow(data))

# Filter specific values using a single operator
filter2 <- function(data, filters, operator = "==") {
  
  # data: a data frame
  # filters: a named vector or list of parameter values, where the names are
  # the names of the parameters to filter
  # operator: optional logical operator to use, defaults to equal
  
  # Create a string containing the filters to apply
  string <- map2(names(filters), filters, ~ paste(.x, operator, .y))
  ## creates a vector of strings "filter == value"
  string <- reduce(string, paste, sep = ", ")
  ## reduces the vector into a single string
  string <- paste0("filter(data, ", string, ")")
  ## creates a string with the function to be applied: "filter(data, fltr1 == x, fltr2 == y, ...)"
  
  # Apply the filters by parsing the string
  eval(parse_expr(string))
  
}

filter2(data, filters = c(a = 1, b = 1))
filter2(data, filters = list(a = 1, b = 1)) # also works

# Filter with any rule, more flexible
filter3 <- function(data, filters) {
  
  # data: a data frame
  # filters: a vector or list of strings defining each filter to apply (will
  # be parsed)
  
  # Create a string containing the filters to apply
  string <- reduce(filters, paste, sep = ", ")
  string <- paste0("filter(data, ", string, ")")
  
  # Apply the filters by parsing the string
  eval(parse_expr(string))
  
}

filter3(data, filters = list("a == 1", "b == 1"))
filter3(data, filters = c("a == 1", "b == 1"))

# I suggest to do the plotting outside, the filtering is a rather self-contained
# task

#==== Raph's stuff (could be useful later on) ====

my_contour <- function(data_set, filters, variable = "resources_mean") {

  data_set %>%
    filter(alphaResources == 0.1, betaTech == 0.1, atech == 2, btech == 1, gamma == 0.01, rb == 2) %>%
    ggplot(aes(x = p, y = q, fill = get(variable))) +
    geom_tile() +
    labs(fill = variable)
    
}

my_contour(data_set, "resources_std")

###

data_plots <- data_set %>%
  group_by(alphaResources, betaTech, atech, btech, gamma, rb) %>%
  nest() %>% 
  mutate(plot = map(data, function(df) {
    
    ggplot(df, aes(x = p, y = q, fill = resources_mean)) +
      geom_tile()
    
  }))

###

#==== Contour Plots Patchworks by Variable ====
# e.g. for p and q

contour_parameter_pair <- function(dataset, filter_full_list, x_par, y_par, response_variable, bounds){
  filter_list <- filter_full_list %>%
    select(-all_of(c(x_par, y_par)))
  dataset %>%
    filter2(filters = unlist(filter_list)) %>%
    ggplot(aes(x = eval(parse_expr(x_par)), y = eval(parse_expr(y_par)), fill = eval(parse_expr(response_variable)))) +
    geom_tile() +
    # scale_fill_gradient(low = "#f7fbff", high = "#08306b") +
    scale_fill_continuous(type = "viridis", limits = c(bounds$low, bounds$high)) +
    labs(x = NULL, y = NULL, fill = response_variable) +
    #theme(legend.position = "none") +
    theme_classic()
}

## checking that the order of graphs is as expected:
## map2(par_comb$x, par_comb$y, ~ c(.x, .y))

# Function to write area instructions as string
area_string <- function(top_placement, left_placement) {
  paste0("area(",top_placement, ",", left_placement, ")")
}

# prepare arguments for automation
#fixed_par_values <- data_set[fitness_parameters][1,]
parameter_list <- data_set %>%
  colnames() %>%
  str_subset(pattern = "_", negate = TRUE)

# to implement fixed pars by hand:
fixed_pars <- tibble(1, 2, 3, 4, 5, 6, 7, 8) %>%
  rename_with(~ parameter_list, c(1, 2, 3, 4, 5, 6, 7, 8))

# to implement fixed pars automatically
find_middle_value <- function(dat, colstr){
  mean_par_value <- dat %>% 
    summarize(mean = mean(!!parse_expr(colstr))) %>%
    as.numeric()
  middle_value <- dat %>% 
    select(all_of(colstr)) %>%
    mutate(absval = abs(!!parse_expr(colstr) - mean_par_value)) %>%
    filter(absval == min(absval)) %>%
    distinct()
  
  return(middle_value[colstr][1,]) # take first row in case there are two values for which the absolute difference is minimal.
}

fixed_pars <- map_dfc(parameter_list, ~ find_middle_value(dat = data_set, colstr = .x))

## Automatize

get_response_variable_bounds <- function(dataset, responsevar) {
  lower_bound <- min(dataset[responsevar])
  upper_bound <- max(dataset[responsevar])
  
  return(list("low" = lower_bound, "high" = upper_bound))
}

contour_plot_patchwork <- function(dataset, fixpars, variable) {
  # get all parameter names 
  fitness_parameters <- names(fixpars)
  # make combinations (without repetitions) of all parameters
  par_comb <- tibble(par = fitness_parameters) %>% 
    expand(x = par, y = par) %>% 
    filter(x < y)
  
  # prepare each contour plot for each parameter combination
  ## set upper and lower limits of the response variable to uniformize throughout all graphs
  boundaries <- get_response_variable_bounds(dataset = data_set, responsevar = variable)
  ## save all graphs in an object
  save_graphs <- map2(par_comb$x, par_comb$y, ~ contour_parameter_pair(data_set, fixpars, x_par = .x, y_par = .y, response_variable = variable, bounds = boundaries) +
                        theme(legend.position = "none"))
  
  # prepare global legend from dummy contour plot
  # NB: need to change response_variable so that it is an argument of the function
  global_legend <- contour_parameter_pair(data_set, fixpars, x_par = par_comb$x[1], y_par = par_comb$y[1], response_variable = variable, bounds = boundaries)  %>%
    cowplot::get_legend() %>% 
    wrap_elements()
  
  # make a list of ordered placements on patchwork for each contour plot
  placements <- tibble(tops = count(par_comb, x)$n, lefts = count(par_comb, y)$n) %>% 
    expand(x = tops, y = lefts) %>% 
    filter(x <= y) %>%
    rename(x = y, y = x)
  
  # turn list into strings containing area function
  all_areas_in_string <- map2(placements$x, placements$y, ~ area_string(top_placement = .x, left_placement = .y + 1)) %>%
    reduce(paste, sep = ", ")
  # make string of all placement areas for left-hand labels
  left_labels_string <- map(1:max(placements), ~ area_string(top_placement = .x, left_placement = 1))  %>%
    reduce(paste, sep = ", ")
  # make string of all placement areas for left-hand labels
  last_row <- max(placements) + 1
  bottom_labels_string <- map(2:last_row, ~ area_string(top_placement = last_row, left_placement = .x)) %>%
    reduce(paste, sep = ", ")
  
  # Collect the labels (left side and bottom)
  last_row_lab <- count(par_comb, x)$x
  first_column_lab <- count(par_comb, y)$y
  
  bottom_labels <- last_row_lab %>%
    map(~ grid::textGrob(.x)) %>%
    map(~ wrap_elements(.x))
  
  left_labels <- first_column_lab %>%
    map(~ grid::textGrob(.x)) %>%
    map(~ wrap_elements(.x))
  
  # collect labels, graphs and legend as a list of ggplot items
  all_graphs <- c(left_labels, save_graphs, bottom_labels, list(global_legend))
  
  # prepare layout
  # NB: the labels and legend areas need to be automatized
  legend_shift <- round((last_row - 1) * sqrt(2) / 4)
  patch_layout <- c(eval(parse_expr(paste0("c(", left_labels_string,")"))), 
                    eval(parse_expr(paste0("c(", all_areas_in_string,")"))), 
                    eval(parse_expr(paste0("c(", bottom_labels_string,")"))),
                    area(1 + legend_shift, last_row - legend_shift + 2))
  
  # plot contours in patchwork following layout
  wrap_plots(all_graphs) +
    plot_layout(design = patch_layout)
  
}

count_occurences <- function(dat, column) {
  dat %>%
    group_by(!!parse_expr(column)) %>%
    n_groups()
}

#==== Contour plot: EXAMPLE ====
# collect the data
#data_set <- collect_all_simulations_data("/home/claire/Dropbox/PhD/Data/Simulations/institutions/techpqalphares0-729")
data_set <- collect_all_simulations_data("/home/claire/Dropbox/PhD/Data/Simulations/institutions/technology0-2500")

# get the list of all parameters
parameter_list <- data_set %>%
  colnames() %>%
  str_subset(pattern = "_", negate = TRUE)

# count the number of distinct values taken on by each parameter
n_par_vals <- map(parameter_list, ~ count_occurences(dat = data_set, column = .x))

# exclude parameters which have only one value (never change between simulations)
changin_pars <- parameter_list[which(n_par_vals > 1)]

# assign specific  values to the parameters that take on different values in different simulations 
distinct_par_vals <- map(parse_exprs(changin_pars), ~ distinct(.data = data_set, !!.x))

# OR: assign middle value to the parameters that take on different values in different simulations 
par_set <- map_dfc(changin_pars, ~ find_middle_value(dat = data_set, colstr = .x))

### IF you want to check what values the changing parameters take on:
map_dfc(changin_pars, ~ data_set %>% select(all_of(.x)) %>% distinct())

# make contour plot for each combination of changing parameter
res_plot <- contour_plot_patchwork(dataset = data_set, fixpars = par_set, variable = "resources_mean")
demo_plot <- contour_plot_patchwork(dataset = data_set, fixpars = par_set, variable = "demography_mean")
tech_plot <- contour_plot_patchwork(dataset = data_set, fixpars = par_set, variable = "technology_mean")
phen_plot <- contour_plot_patchwork(dataset = data_set, fixpars = par_set, variable = "phenotype1_mean")

ggsave(filename = "resources_techfunc.png", plot = res_plot, path = "/home/claire/Dropbox/PhD/Results/figs", width = 10, height = 5, units = "in")
ggsave(filename = "technology_techfunc.png", plot = tech_plot, path = "/home/claire/Dropbox/PhD/Results/figs", width = 10, height = 5, units = "in")
ggsave(filename = "demography_techfunc.png", plot = demo_plot, path = "/home/claire/Dropbox/PhD/Results/figs", width = 10, height = 5, units = "in")
ggsave(filename = "phenotype1_techfunc.png", plot = phen_plot, path = "/home/claire/Dropbox/PhD/Results/figs", width = 10, height = 5, units = "in")

par_combis <- tibble(par = colnames(par_set)) %>% 
  expand(x = par, y = par) %>% 
  filter(x < y)

contour_parameter_pair(data_set, par_set, x_par = par_combis$x[1], y_par = par_combis$y[1], response_variable = "resources_mean", bounds = list("low" = 10, "high" = 110)) %>%
  cowplot::get_legend() %>% 
  wrap_elements()

#==== example from GGally ====
# Small function to display plots only if it's interactive
p_ <- GGally::print_if_interactive

data(tips, package = "reshape")
p_(ggally_facetdensity(tips, mapping = ggplot2::aes(x = total_bill, y = sex)))
p_(ggally_facetdensity(tips,mapping = ggplot2::aes_string(y = "total_bill", x = "sex", color = "sex")))
###

# Desired format:
# Each row is one simulation, each column a parameter value or mean / variance variable

file_path <- "out_demography.txt"
variable_file <- path_file(file_path)
variable_name <- str_match(variable_file,"(?<=_).*(?=\\.)")

# mean # name
# function(x) mean(x) # lambda simple
# function(x) { mean(sqrt(x)) } # lambda complexe
# ~ mean(.x) # formula

mean_column <- paste(variable_name, "_mean", sep = "")
variance_column <- paste(variable_name, "_variance", sep = "")
variable_tibble <- read_csv(variable_file, col_names = c(mean_column, variance_column))
m <- summarize(variable_tibble, mean = mean(!!rlang::parse_expr(mean_column)))
v <- summarize(variable_tibble, std = mean(sqrt(!!rlang::parse_expr(variance_column))))
data_summary <- bind_cols(var_name = variable_name[,1], m, v)



# Example: single simulation ====
# my_dir = "/home/claire/Dropbox/PhD/Results/technotest/technology_alphaResources0.4betaTech0.7p0.6atech2.0btech1.0q0.7gamma0.01rb2.0"
# setwd(my_dir)
my_dir = "/home/claire/Desktop/institution-evolution/mysim"
non_pheno_data <- read_non_phenotype_data(my_dir)
pheno_data <- read_phenotype_data("out_phenotypes.txt")

plot_phenotype_smooth(pheno_data, 1)
plot_phenotype(pheno_data, 1)

## Plot phenotypes
1:4 %>% 
  map(plot_phenotype, phen_dat = pheno_data) %>%
  wrap_plots()

1:4 %>% 
  map(plot_phenotype_smooth, phen_dat = pheno_data) %>%
  wrap_plots()

pheno_data %>% filter(generation > 5000) %>% summarise(mean = mean(phenotype1_mean))

## Plot other variables  
plot_non_phen(non_pheno_data,"demography")
c("consensus", "resources", "demography", "technology") %>% 
  map(plot_non_phen, dat = non_pheno_data) %>%
  wrap_plots()

non_pheno_data %>% filter(generation > 5000) %>% summarise(mean = sqrt(mean(demography_variance)))

#==== Plots for mid thesis ====
ggplot(non_pheno_data) +
  geom_ribbon(mapping = aes(x=generation,
                            ymin=demography_mean-sqrt(demography_variance),
                            ymax=demography_mean+sqrt(demography_variance)),
              colour = "gray") +
  geom_point(mapping=aes(x=generation,y=demography_mean), alpha=0.5) +
  ylim(0,120) +
  xlab("Time (number of generations)") +
  ylab(bquote("Mean demography, " ~ bar("n"))) +
  theme_classic()

ggplot(pheno_data) +
  geom_ribbon(mapping = aes(x=generation,
                            ymin=phenotype1_mean-sqrt(phenotype1_variance),
                            ymax=phenotype1_mean+sqrt(phenotype1_variance)),
              colour = "gray") +
  geom_point(mapping=aes(x=generation,y=phenotype1_mean), alpha=0.5) +
  ylim(0,1) +
  xlab("Time (number of generations)") +
  ylab(bquote("Mean cooperation, " ~ bar("x"))) +
  theme_classic()

##############################################

# Example: multiple simulations ====

extract_mean("out_demography.txt")
extract_meta_data()