* ===========================================================================
* globals.do  -  Project-wide path definitions and analysis parameters
* ===========================================================================
* GOAL	   : Have all global vaiables that are used across the project.
*            Is called automatically by master.do — do not run in alone.
* AUTHOR   : Carolina Abdalla Braga, University of Chicago
* ---------------------------------------------------------------------------

clear all
set more off
set varabbrev off
version 17.0

* ---------------------------------------------------------------------------
* 1. MAIN DIRECTORY
*    Change this to match your local machine before running anything.
* ---------------------------------------------------------------------------
global root "C:\Users\carolbraga\Downloads\stata_sample"

* ---------------------------------------------------------------------------
* 2. SUB-DIRECTORIES  (no need to edit these)
* ---------------------------------------------------------------------------
global data    "$root/data"          // raw and processed Stata datasets
global prep    "$root/prepare"       // data preparation do-files
global anly    "$root/analysis"      // analysis do-files
global output  "$root/output"
global tables  "$output/tables"      // LaTeX and CSV tables
global graphs  "$output/graphs"      // exported PNG figures
global logs    "$output/logs"        // session log files

* Create output folders if they do not yet exist
foreach dir in "$output" "$tables" "$graphs" "$logs" {
    cap mkdir "`dir'"
}

* ---------------------------------------------------------------------------
* 3. ANALYSIS PARAMETERS
* ---------------------------------------------------------------------------
global treat_year  2013   // t = 0 in the event study 
global pre_window  4      // number of pre-treatment periods
global post_window 3      // number of post-treatment periods

* ---------------------------------------------------------------------------
* 4. REQUIRED PACKAGES
*   Run once on a new machine to make sure all images and tables can be 
*	completed.
* ---------------------------------------------------------------------------

ssc install require, replace   // deoendecy manager required by reghdfe v6+
ssc install reghdfe, replace   // high-dimensional FE regressions (Correia 2017)
ssc install ftools,  replace   // required dependency for reghdfe
ssc install coefplot, replace  // coefficient and event-study plots (Jann 2014)
ssc install estout,  replace   // publication-quality regression tables (Jann 2005)
ssc install gtools, replace    // fast xtile / collapse (Caceres Bravo 2018)

