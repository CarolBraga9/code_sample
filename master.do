* ===========================================================================
* master.do  -  Master script: runs the full analysis pipeline in sequence
* ===========================================================================
* GOAL  : One do file that reproduces all tables and figures.
*
* SETUP: Need to run R p.R to build full dataset
*   1. Edit globals.do: set $root to match your machine if needed
*   2. Install required packages (uncomment block in globals.do, run once)
*   3. In Stata:
*        cd "C:/Users/carol/OneDrive/Documents/Harris/Master Thesis/Code/stata_sample"
*        do master.do
*
* OUTPUTS  : Tables (.tex, .csv) → output/tables/
*            Figures (.png)       → output/graphs/
*            Session log          → output/logs/
*
* AUTHOR   : Carolina Abdalla Braga, University of Chicago
*
* NOTES    :  Code adapted from R. Data building and sourcing from R because of 
* 			  the specific packages that are already build there. Data pulled from 
*			  Brazilian free repositories from DATASUS and IBGE.
* ---------------------------------------------------------------------------

* 0. Load project globals (paths, package list)
cd "C:\Users\carolbraga\Downloads\stata_sample"
do "globals.do"

* Confirm CSV exists before proceeding
cap confirm file "$data/brazil_health_panel.csv"
if _rc != 0 {
    di as error "Input file not found: $data/brazil_health_panel.csv"
    di as error "Run prepare_data.R in RStudio first, then re-run master.do"
    exit 601
}

* Open log that records all console output
cap log close _all
log using "$logs/master_`c(current_date)'.txt", text replace name(master)

di as result _newline ///
   "======================================================================" _newline ///
   " Brazil: Health Has No Price  |  Stata Replication" _newline ///
   " Started : `c(current_time)'  |  `c(current_date)'" _newline ///
   "======================================================================"

* ---------------------------------------------------------------------------
* STEP 1 — DATA PREPARATION
*
*   01_build_panel.do   : import CSV; create hosp_rate and mortality_rate
*   02_strata_assign.do : assign analytical strata; build event-study dataset
* ---------------------------------------------------------------------------
di as result _newline " > STEP 1: Data Preparation"
do "$prep/01_build_panel.do"
do "$prep/02_strata_assign.do"

* ---------------------------------------------------------------------------
* STEP 2 — ANALYSIS OUTPUTS
*
*   sum_tab.do   : Table 1 — baseline summary statistics by strata
*   table_1.do   : Table 2 — event study regression coefficients (4 models)
*   fig_1.do     : Figures  — event study plots and income-quartile heterogeneity
*   table_2.do   : Table 3  — heterogeneity event study by income quartile
* ---------------------------------------------------------------------------
di as result _newline " > STEP 2: Analysis and Outputs"
do "$anly/sum_tab.do"
do "$anly/table_1.do"    // stores estimates in memory — must run before fig_1.do
do "$anly/fig_1.do"
do "$anly/table_2.do"

di as result _newline ///
   "======================================================================" _newline ///
   " All outputs saved to: $output" _newline ///
   " Finished : `c(current_time)'" _newline ///
   "======================================================================"

log close master


* ---------------------------------------------------------------------------
* GIT : stage and push and changes to track files
* Requires git to be installed  and in your system paths
* Remove ore comment this block if you prefer to commit manually.
* ---------------------------------------------------------------------------

shell git -C
"C:\Users\carolbraga\Downloads\stata_sample" add -A

shell git -C
"C:\Users\carolbraga\Downloads\stata_sample" commit -m "Analysis run `c (current_date)' `c(current_time)'"

shell git -C
"C:\Users\carolbraga\Downloads\stata_sample" push