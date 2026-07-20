
# ==============================================================================
# prepare_data.R
# Brazil: Health Has No Price Full Data Preparation 
# Author: Carolina Abdalla Braga, University of Chicago
# ==============================================================================
#
# GOAL
#   Builds the analysis-ready panel from raw administrative sources and exports
#   it as a CSV file that the Stata can read without Python. (My vLab had no Python
#   so this was the best workaround I could find). Run this script ONCE before
#   running master.do in Stata.  After the CSV is created, Stata is fully self-
#   contained and this script never needs to run again unless you change the raw
#   data or sample years.
#
# WHAT THIS SCRIPT DOES (in order)
#   Phase 1 SIH   : Downloads hospitalizations from DataSUS
#   Phase 2 SIM   : Downloads deaths from DataSUS
#   Phase 3 Pop   : Fetches municipal population from the IBGE SIDRA API
#   Phase 4 Demo  : Reads race and literacy from local IBGE Census CSVs
#   Phase 5 RAIS  : Reads formal-employment microdata from local TXT files
#   Phase 6 Assem : Joins all sources into one balanced panel in DuckDB
#   Export  CSV   : Writes the final panel to a CSV for Stata
#
# PRE-REQUISITES (files that must exist on disk before running)
# This was an unfortunate problem with the automatic data collection from the server.
# It did not properly connect and the data had to be manually downloaded. 
# They are attached in the "necessary files folder"
#
#   1. RAIS microdata  (.txt files, semi-colon delimited) in RAIS_DIR
#   2. IBGE race CSV   (tabela2093.csv) downloaded from IBGE SIDRA table 2093
#   3. IBGE literacy CSV (tabela1383.csv) downloaded from IBGE SIDRA table 1383
#
#   Edit the PATHS block below to match your machine.
#
# OUTPUT
#   stata_sample/data/brazil_health_panel.csv Stata reads this
#   data/processed/brazil_health_data_FULL.duckdbintermediate DuckDB store
#
# ------------------------------------------------------------------------------

# ==============================================================================
# 0. SETUP
# ==============================================================================

# Set to TRUE to drop and reload the RAIS table from scratch.
# Leave FALSE after the first successful run to avoid re-processing ~50 GB.
FORCE_CLEAN_RAIS <- FALSE

suppressPackageStartupMessages({
  library(data.table)   # fast CSV reading for RAIS microdata
  library(tidyverse)    # data wrangling
  library(microdatasus) # DataSUS API wrappers for SIH and SIM
  library(duckdb)       # analytical database used as intermediate store
  library(DBI)          # generic database interface
  library(jsonlite)     # parse IBGE API responses
  library(httr)         # HTTP requests for IBGE SIDRA API
  library(stringr)      # string helpers
  library(readr)        # write_csv for the final export
})

setDTthreads(2)   # cap data.table CPU usage to avoid freezing on large RAIS files
gc()

# ==============================================================================
# PATHS -> edit these to match your machine
# ==============================================================================
YEARS        <- 2008:2016
RAIS_DIR     <- "C:/Users/carol/OneDrive/Documents/data/raw"
CSV_RACE     <- "C:/Users/carol/OneDrive/Documents/Harris/Master Thesis/Code/stata_sample/necessary_files/tabela2093.csv"
CSV_LIT      <- "C:/Users/carol/OneDrive/Documents/Harris/Master Thesis/Code/stata_sample/necessary_files/tabela1383.csv"
DB_PATH      <- "C:/Users/carol/OneDrive/Documents/Harris/Master Thesis/Code/data/processed/brazil_health_data_FULL.duckdb"
CSV_OUT      <- "C:/Users/carol/OneDrive/Documents/Harris/Master Thesis/Code/stata_sample/data/brazil_health_panel.csv"

# Brazilian state IBGE codes (all 27 UFs)
UFS <- c("11","12","13","14","15","16","17","21","22","23","24","25","26",
         "27","28","29","31","32","33","35","41","42","43","50","51","52","53")

# Create the processed-data folder if it does not exist yet
dir.create(dirname(DB_PATH), showWarnings = FALSE, recursive = TRUE)
dir.create(dirname(CSV_OUT), showWarnings = FALSE, recursive = TRUE)

# Open (or create) the DuckDB database.
# If this errors with "file already in use", close all other R sessions that
# may have the database open, then re-run.
db_con <- tryCatch(
  dbConnect(duckdb(), dbdir = DB_PATH, read_only = FALSE),
  error = function(e) {
    message("\n[!] Could not open DuckDB (read-write): ", conditionMessage(e))
    message("    -> Close all other R sessions / scripts using this database, then re-run.")
    message("    -> If the database is already complete, the Export section below will")
    message("       still run using a separate read-only connection.\n")
    NULL
  }
)

pipeline_ok <- !is.null(db_con) && dbIsValid(db_con)
message("=== STARTING PREPARE PIPELINE ===")

# ==============================================================================
# PHASE 1 SIH: Preventable Hospitalizations
# ==============================================================================
# Fetches monthly SIH-RD micro-records from DataSUS, keeps only the residence
# municipality and year, then aggregates to annual counts per municipality.
# Skips download if the table already exists in the database.
# ==============================================================================
if (!pipeline_ok) {
  message("[!] Skipping Phases 1-6: no database connection. Export will still run if data already exists.")
}

message("\nPhase 1: SIH hospitalizations...")

if (pipeline_ok && !dbExistsTable(db_con, "sih_data_final")) {

  dbExecute(db_con, "
    CREATE TABLE sih_data_final (
      year                 DOUBLE,
      municipality_code    VARCHAR,
      total_hospitalizations BIGINT
    )
  ")

  for (yr in YEARS) {
    message(paste("  Year:", yr))
    monthly <- list()

    for (m in 1:12) {
      tryCatch({
        raw <- fetch_datasus(year_start = yr, month_start = m,
                             year_end   = yr, month_end   = m,
                             information_system = "SIH-RD")
        if (!is.null(raw) && nrow(raw) > 0) {
          monthly[[m]] <- raw %>%
            select(year = ANO_CMPT, municipality_code = MUNIC_RES) %>%
            mutate(municipality_code = substr(municipality_code, 1, 6),
                   year = as.numeric(substr(year, 1, 4))) %>%
            group_by(year, municipality_code) %>%
            summarise(total_hospitalizations = n(), .groups = "drop")
        }
        rm(raw); gc()
      }, error = function(e) message(paste("    [!] Month", m, "failed:", e$message)))
    }

    if (length(monthly) > 0) {
      annual <- bind_rows(monthly) %>%
        group_by(year, municipality_code) %>%
        summarise(total_hospitalizations = sum(total_hospitalizations), .groups = "drop")
      dbWriteTable(db_con, "sih_data_final", annual, append = TRUE)
    }
    rm(monthly); gc()
  }

} else {
  message("  -> Table already exists. Skipping.")
}

# ==============================================================================
# PHASE 2 SIM: Preventable Deaths
# ==============================================================================
# Fetches annual SIM-DO records from DataSUS, extracts the death year from the
# DTOBITO field, and aggregates to annual death counts per municipality.
# ==============================================================================
message("\nPhase 2: SIM deaths...")

if (pipeline_ok && !dbExistsTable(db_con, "sim_data_final")) {

  sim_list <- list()
  for (yr in YEARS) {
    tryCatch({
      raw <- fetch_datasus(year_start = yr, year_end = yr,
                           information_system = "SIM-DO")
      sim_list[[as.character(yr)]] <- raw %>%
        select(year = DTOBITO, municipality_code = CODMUNRES) %>%
        mutate(year = as.numeric(str_extract(year, "\\d{4}$")),
               municipality_code = substr(municipality_code, 1, 6)) %>%
        group_by(year, municipality_code) %>%
        summarise(total_deaths = n(), .groups = "drop")
      rm(raw); gc()
    }, error = function(e) message(paste("  [!] Year", yr, "failed:", e$message)))
  }

  if (length(sim_list) > 0)
    dbWriteTable(db_con, "sim_data_final", bind_rows(sim_list), overwrite = TRUE)

} else {
  message("  -> Table already exists. Skipping.")
}

# ==============================================================================
# PHASE 3 Population: IBGE SIDRA API
# ==============================================================================
# Pulls municipal population from two SIDRA tables:
#   Table 200 / variable 93  Census 2010 headcount
#   Table 6579 / variable 9324 inter-Census estimates (all other years)
# Pauses 0.1 s between requests to respect the API rate limit.
# ==============================================================================
message("\nPhase 3: IBGE population...")

if (pipeline_ok && !dbExistsTable(db_con, "ibge_population")) {

  HTTP_HEADER <- httr::user_agent("Mozilla/5.0")
  pop_list <- list()

  for (yr in YEARS) {
    t_id <- ifelse(yr == 2010, 200, 6579)
    v_id <- ifelse(yr == 2010, 93,  9324)

    for (uf in UFS) {
      url <- paste0(
        "https://apisidra.ibge.gov.br/values/t/", t_id,
        "/p/", yr, "/v/", v_id, "/n3/", uf, "/n6/all"
      )
      res <- httr::GET(url, HTTP_HEADER, httr::config(ssl_verifypeer = 0L))

      if (res$status_code == 200) {
        raw <- jsonlite::fromJSON(httr::content(res, "text"), flatten = TRUE)
        if (nrow(raw) > 1)
          pop_list[[paste0(yr, uf)]] <- raw[-1, ] %>%
            select(year = D1C, municipality_code = D3C, population = V) %>%
            mutate(across(everything(), as.numeric))
      }
      Sys.sleep(0.1)
    }
  }

  if (length(pop_list) > 0)
    dbWriteTable(db_con, "ibge_population", bind_rows(pop_list), overwrite = TRUE)

} else {
  message("  -> Table already exists. Skipping.")
}

# ==============================================================================
# PHASE 4 Demographics: Race and Literacy from IBGE Census CSVs
# ==============================================================================
# Both tables are from the 2010 Population Census (IBGE SIDRA) and are treated
# as time-invariant baselines.  They must be downloaded manually and placed in
# the paths set above (CSV_RACE, CSV_LIT).
#
#   tabela2093.csv  Population by race/colour (preto + pardo pct_black_parda)
#   tabela1383.csv  Literacy rate for residents aged 10+
# ==============================================================================
message("\nPhase 4: Demographics (race + literacy)...")

if (!file.exists(CSV_RACE) || !file.exists(CSV_LIT)) {
  stop(
    "Missing Census CSV files.\n",
    "  Expected: ", CSV_RACE, "\n",
    "  Expected: ", CSV_LIT,  "\n",
    "Download from IBGE SIDRA (tables 2093 and 1383) and re-run."
  )
}

df_race <- fread(CSV_RACE, encoding = "Latin-1", header = FALSE, skip = 6) %>%
  filter(V3 == "Total") %>%
  select(
    municipality_code        = V1,
    base_count_pop_race_total = V5,
    base_count_race_white    = V8,
    base_count_race_black    = V11,
    base_count_race_parda    = V17
  ) %>%
  mutate(municipality_code = substr(as.character(municipality_code), 1, 6)) %>%
  mutate(across(-municipality_code, ~as.numeric(na_if(., "-")))) %>%
  mutate(across(-municipality_code, ~replace_na(., 0)))

df_lit <- fread(CSV_LIT, encoding = "Latin-1", header = FALSE, skip = 6) %>%
  select(municipality_code = V1, literacy_rate = V5) %>%
  mutate(
    municipality_code = substr(as.character(municipality_code), 1, 6),
    literacy_rate = as.numeric(na_if(as.character(literacy_rate), "..."))
  ) %>%
  filter(!is.na(municipality_code)) %>%
  mutate(literacy_rate = replace_na(literacy_rate, mean(literacy_rate, na.rm = TRUE)))

df_demo <- full_join(df_lit, df_race, by = "municipality_code")
if (pipeline_ok) {
  dbWriteTable(db_con, "ibge_demographics", df_demo, overwrite = TRUE)
  message("  -> Demographics saved.")
} else {
  message("  -> Demographics processed but not written (no DB connection).")
}

# ==============================================================================
# PHASE 5 RAIS: Formal Employment and Wages
# ==============================================================================
# Reads all semi-colon delimited RAIS microdata files found under RAIS_DIR.
# Column names vary across states and vintages (including encoding differences
# for accented characters), so columns are matched by lowercased keyword rather
# than by position.
#
# The active-employment filter accepts multiple encodings Ministerio do Trabalho
# has used over the years: 1, "Sim", "S", "TRUE", etc.
# ==============================================================================
message("\nPhase 5: RAIS formal employment...")

process_rais_file <- function(f, db_con) {
  fname <- basename(f)
  yr    <- str_extract(fname, "\\d{4}")
  if (is.na(yr)) return()
  message(paste("  ->", fname))

  tryCatch({
    # Read just the header row to discover column names for this vintage
    header    <- fread(f, sep = ";", dec = ",", encoding = "Latin-1",
                       header = TRUE, nrows = 0)
    cols      <- names(header)
    cols_norm <- tolower(iconv(cols, to = "ASCII//TRANSLIT"))

    col_mun  <- cols[grep("municipio",         cols_norm)[1]]
    col_vinc <- cols[grep("vinculo ativo 31",  cols_norm)[1]]
    col_wage <- cols[grep("vl remun media nom", cols_norm)[1]]

    if (is.na(col_mun) || is.na(col_vinc) || is.na(col_wage)) {
      message("     [!] Required columns not found. Skipping.")
      return()
    }

    # Read only the three needed columns; keep as character to handle Brazilian
    # numeric format ("3.500,00") and varied active-job encodings safely
    dt <- fread(f, sep = ";", dec = ",", encoding = "Latin-1",
                select       = c(col_mun, col_vinc, col_wage),
                colClasses   = "character",
                showProgress = FALSE)
    setnames(dt,
             old = c(col_mun, col_vinc, col_wage),
             new = c("mun", "vinc_ativo", "wage"))

    # Convert Brazilian wage format: "3.500,00" -> 3500
    dt[, wage_num := as.numeric(gsub(",", ".", gsub("\\.", "", trimws(wage))))]

    # Broad active-job filter handles 1, "Sim", "S", "TRUE", "ATIVO", etc.
    vinc_clean  <- trimws(toupper(as.character(dt$vinc_ativo)))
    active_mask <- vinc_clean %in% c("1", "TRUE", "SIM", "S", "YES", "ATIVO")
    dt_agg <- dt[active_mask,
                 .(total_formal_jobs = .N,
                   avg_wage_nominal  = mean(wage_num, na.rm = TRUE)),
                 by = .(mun)]

    # Numeric fallback for vintages that use a non-zero number instead of a flag
    if (nrow(dt_agg) == 0) {
      vinc_num <- suppressWarnings(as.numeric(dt$vinc_ativo))
      dt_agg <- dt[!is.na(vinc_num) & vinc_num > 0,
                   .(total_formal_jobs = .N,
                     avg_wage_nominal  = mean(wage_num, na.rm = TRUE)),
                   by = .(mun)]
      if (nrow(dt_agg) == 0) {
        message("     [!] No active jobs found skipping file.")
        return()
      }
    }

    dt_agg[, year              := as.numeric(yr)]
    dt_agg[, municipality_code := substr(as.character(mun), 1, 6)]
    dt_agg[, mun               := NULL]

    dbWriteTable(db_con, "rais_data_final", dt_agg, append = TRUE)
    rm(dt, dt_agg); gc()

  }, error = function(e) message(paste("     [!] Error:", e$message)))
}

# Drop and reload if forced; otherwise skip if the table has data
rais_needs_loading <- pipeline_ok
if (pipeline_ok && dbExistsTable(db_con, "rais_data_final")) {
  if (FORCE_CLEAN_RAIS) {
    message("  FORCE_CLEAN_RAIS = TRUE: dropping and reloading.")
    dbExecute(db_con, "DROP TABLE rais_data_final")
  } else {
    n <- dbGetQuery(db_con, "SELECT count(*) AS n FROM rais_data_final")$n
    if (n > 0) {
      message(paste("  -> Table already exists (", n, "rows). Skipping.",
                    "Set FORCE_CLEAN_RAIS = TRUE to reload."))
      rais_needs_loading <- FALSE
    } else {
      dbExecute(db_con, "DROP TABLE rais_data_final")
    }
  }
}

if (rais_needs_loading) {
  rais_files <- list.files(RAIS_DIR, pattern = "\\.txt$",
                           full.names = TRUE, recursive = TRUE)
  dbExecute(db_con, "
    CREATE TABLE rais_data_final (
      year               DOUBLE,
      municipality_code  VARCHAR,
      total_formal_jobs  DOUBLE,
      avg_wage_nominal   DOUBLE
    )
  ")
  if (length(rais_files) == 0) {
    message("  [!] No RAIS .txt files found in RAIS_DIR.")
  } else {
    for (f in rais_files) { process_rais_file(f, db_con); gc() }
  }
}

# ==============================================================================
# PHASE 6 Final Assembly
# ==============================================================================
# Left-joins all tables onto the population spine so every municipality-year
# combination has a row, even if some administrative sources have no record
# (counts default to 0 via COALESCE).
# ==============================================================================
message("\nPhase 6: Assembling final panel...")

if (!pipeline_ok) {
  message("  -> Skipping: no database connection.")
} else {

dbExecute(db_con, "DROP TABLE IF EXISTS final_panel_complete")
dbExecute(db_con, "
  CREATE TABLE final_panel_complete AS
  SELECT
    pop.year,
    SUBSTRING(pop.municipality_code, 1, 6)   AS municipality_code,
    SUBSTRING(pop.municipality_code, 1, 2)   AS state_code,
    pop.population,
    COALESCE(sih.total_hospitalizations, 0)  AS total_hospitalizations,
    COALESCE(sim.total_deaths,           0)  AS total_deaths,
    rais.total_formal_jobs,
    rais.avg_wage_nominal,
    dem.* EXCLUDE (municipality_code)
  FROM ibge_population pop
  LEFT JOIN sih_data_final   sih  ON pop.year = sih.year
        AND SUBSTRING(pop.municipality_code, 1, 6) = sih.municipality_code
  LEFT JOIN sim_data_final   sim  ON pop.year = sim.year
        AND SUBSTRING(pop.municipality_code, 1, 6) = sim.municipality_code
  LEFT JOIN rais_data_final  rais ON pop.year = rais.year
        AND SUBSTRING(pop.municipality_code, 1, 6) = rais.municipality_code
  LEFT JOIN ibge_demographics dem
        ON SUBSTRING(pop.municipality_code, 1, 6) = CAST(dem.municipality_code AS VARCHAR)
")

n_rows   <- dbGetQuery(db_con, "SELECT count(*) AS n FROM final_panel_complete")$n
n_munic  <- dbGetQuery(db_con, "SELECT count(DISTINCT municipality_code) AS n FROM final_panel_complete")$n
n_states <- dbGetQuery(db_con, "SELECT count(DISTINCT state_code) AS n FROM final_panel_complete")$n
message(sprintf("  -> Panel: %d rows | %d municipalities | %d states", n_rows, n_munic, n_states))

dbDisconnect(db_con, shutdown = TRUE)
message("Phase 6 complete. DuckDB closed.")

} # end if (pipeline_ok)

# ==============================================================================
# EXPORT Write CSV for Stata
# ==============================================================================
# Opens the DuckDB in read-only mode, pulls the final panel, computes
# pct_black_parda (share of population that is Black or Parda), and writes
# the CSV.  This is the only file Stata ever reads.
# ==============================================================================
message("\nExport: Writing CSV for Stata...")

con <- dbConnect(duckdb(), dbdir = DB_PATH, read_only = TRUE)

df <- tbl(con, "final_panel_complete") %>%
  collect() %>%
  transmute(
    municipality_code,
    state_code,
    year,
    total_hospitalizations = replace_na(total_hospitalizations, 0),
    total_deaths           = replace_na(total_deaths,           0),
    population,
    avg_wage_nominal,
    literacy_rate,
    pct_black_parda = (replace_na(base_count_race_black, 0) +
                       replace_na(base_count_race_parda, 0)) /
                      (replace_na(base_count_pop_race_total, 0) + 1)
  )

dbDisconnect(con)

write_csv(df, CSV_OUT)
message(sprintf("Done: %d rows written to:\n  %s", nrow(df), CSV_OUT))
message("\n=== ALL DONE. Run master.do in Stata next. ===")
