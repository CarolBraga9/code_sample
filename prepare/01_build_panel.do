* ===========================================================================
* prepare/01_build_panel.do  -  Load raw panel; create outcome variables
* ===========================================================================
* INPUT  : $data/brazil_health_panel.csv
*
* OUTPUT : $data/panel_clean.dta
*
* VARIABLES CREATED:
*   hosp_rate      — preventable hospitalizations per 10,000 residents
*   mortality_rate — preventable deaths per 10,000 residents
* ---------------------------------------------------------------------------

di as text _newline " [01_build_panel] Loading panel from CSV..."

* ---------------------------------------------------------------------------
* 1. Import CSV
*    stringcols(2) keeps state_code as a string (e.g. "SP", "RJ", "BA")
* ---------------------------------------------------------------------------
import delimited using "$data/brazil_health_panel.csv", ///
    clear varnames(1) stringcols(2)

di as text "  Rows imported : " _N
qui sum year
di as text "  Years         : " r(min) " to " r(max)

* ---------------------------------------------------------------------------
* 1b. Force numeric types on any columns that have converted into strings
* ---------------------------------------------------------------------------

foreach v of varlist population total_hospitalizations total_deaths ///
avg_wage_nominal literacy_rate pct_black_parda {
	cap confirm string variable `v'
	if _rc == 0 {
		destring `v', replace force
		di as text " destring: `v' converted to numeric"
	}
}

* ---------------------------------------------------------------------------
* 2. Declare as panel
* ---------------------------------------------------------------------------
xtset municipality_code year

* ---------------------------------------------------------------------------
* 3. Create outcome variables (rates per 10,000 residents)
* ---------------------------------------------------------------------------
* Population of 0 or missing would produce infinite or missing rates
replace population = . if population <= 0

gen double hosp_rate      = (total_hospitalizations / population) * 10000
gen double mortality_rate = (total_deaths           / population) * 10000

label var hosp_rate      "Preventable hospitalizations per 10,000"
label var mortality_rate "Preventable deaths per 10,000"

* ---------------------------------------------------------------------------
* 4. Sanity check
* ---------------------------------------------------------------------------
di as text _newline "  Outcome summary:"
tabstat hosp_rate mortality_rate, ///
    statistics(n mean sd p10 p50 p90) columns(statistics) format(%9.2f)

* ---------------------------------------------------------------------------
* 5. Save as .dta - makes it faster for future use and analysis
* ---------------------------------------------------------------------------
compress
sort municipality_code year
save "$data/panel_clean.dta", replace

di as text _newline " [01_build_panel] Done. Saved: panel_clean.dta (" _N " obs)"
