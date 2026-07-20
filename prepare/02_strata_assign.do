* ===========================================================================
* prepare/02_strata_assign.do  -  Assign strata; build datasets
* ===========================================================================
* INPUT  : $data/panel_clean.dta
*
* OUTPUT : $data/panel_maps.dta       — full panel with strata labels
*                                        (all municipalities; used for
*                                         descriptive statistics and maps)
*          $data/panel_analysis.dta   — event-study panel restricted to
*                                        Target (LI-HD) vs. Reference (LI-LD)
*
* STRATA DEFINITION  (quartiles computed on 2010 cross-section):
*   Target (LI-HD)    — income Q1 & disease Q4  → primary treatment group
*   Reference (LI-LD) — income Q1 & disease Q1  → comparison group
*   Placebo (HI-HD)   — income Q4 & disease Q4  → high-income placebo
*   Placebo (HI-LD)   — income Q4 & disease Q1  → high-income placebo
*   Middle            — all remaining quartile combinations
*
* BASELINE COVARIATES created for the controlled specification:
*   base_wage_std, base_hosp_std, base_literacy_std, base_pct_black_std
*   Each is a standardized (mean 0, SD 1) value of the 2010 baseline
*   characteristic, interacted with year dummies in the regression to allow
*   municipalities to follow differential time trends.
*
* EVENT-STUDY VARIABLES created in panel_analysis.dta:
*   treated   — 1 for Target (LI-HD), 0 for Reference (LI-LD)
*   event_time — years relative to $treat_year, clamped to [-4, 3]
*   pre2–pre4  — Treated × 1(event_time == -k) for k = 2, 3, 4
*   post0–post3 — Treated × 1(event_time == k) for k = 0, 1, 2, 3
*   (Reference period is event_time == -1; no dummy created → omitted)
* ---------------------------------------------------------------------------

di as text _newline " [02_strata_assign] Assigning strata and building analysis dataset..."

use "$data/panel_clean.dta", clear

* ===========================================================================
* PART A — BASELINE VALUES (2010 cross-section)
* ===========================================================================

* ---------------------------------------------------------------------------
* A1. Baseline wage
*     Prefer 2010; fall back to nearest pre-treatment year when 2010 is
*     missing (some municipalities had no formal-sector workers in 2010).
*	  Probably due to some data instability with the servers. Ideal to have full
*	  data, but this is the work around I was able to find.
* ---------------------------------------------------------------------------
preserve
    keep if year <= 2012 & !missing(avg_wage_nominal)
    gen dist = abs(year - 2010)
    bysort municipality_code (dist year): keep if _n == 1   // nearest to 2010
    rename avg_wage_nominal base_wage
    keep municipality_code base_wage
    tempfile base_wages
    save `base_wages'
restore

merge m:1 municipality_code using `base_wages', nogen
label var base_wage "Baseline avg nominal wage (R$, closest pre-treat year to 2010)"

* ---------------------------------------------------------------------------
* A2. 2010 baseline values for hospitalization rate, literacy, and race
* ---------------------------------------------------------------------------
preserve
    keep if year == 2010
    rename hosp_rate     base_hosp
    rename literacy_rate base_literacy
    rename pct_black_parda base_pct_black
    keep municipality_code base_hosp base_literacy base_pct_black
    tempfile base_2010
    save `base_2010'
restore

merge m:1 municipality_code using `base_2010', nogen

* ===========================================================================
* PART B — QUARTILE ASSIGNMENT AND STRATA
* ===========================================================================

* ---------------------------------------------------------------------------
* B1. Compute income and disease quartile cutoffs on the 2010 cross-section
*     (restricted to municipalities with valid baseline wage and hosp rate)
* ---------------------------------------------------------------------------
preserve
    keep if year == 2010 & !missing(base_wage) & !missing(base_hosp)
    xtile inc_q = base_wage, nq(4)
    xtile dis_q = base_hosp, nq(4)
    keep municipality_code inc_q dis_q
    tempfile quartiles
    save `quartiles'
restore

merge m:1 municipality_code using `quartiles', nogen

* ---------------------------------------------------------------------------
* B2. Assign strata labels
* ---------------------------------------------------------------------------
gen strata_main = "Middle"
replace strata_main = "Target (LI-HD)"    if inc_q == 1 & dis_q == 4
replace strata_main = "Reference (LI-LD)" if inc_q == 1 & dis_q == 1
replace strata_main = "Placebo (HI-HD)"   if inc_q == 4 & dis_q == 4
replace strata_main = "Placebo (HI-LD)"   if inc_q == 4 & dis_q == 1
replace strata_main = ""                  if missing(base_wage)

label var strata_main "Analytical strata (income x disease burden quartile)"
label var inc_q "Income quartile (1=lowest wage, 4=highest)"
label var dis_q "Disease quartile (1=lowest hosp rate, 4=highest)"

* Distribution check
di as text _newline "  Strata distribution (2010 cross-section):"
tab strata_main if year == 2010, missing

* ===========================================================================
* PART C — STANDARDIZED BASELINE COVARIATES
* ===========================================================================
* Impute the small share of missing values with the 2010 median before
* standardizing (avoids dropping municipalities from the controlled model)

foreach v in base_literacy base_pct_black {
    qui sum `v' if year == 2010, detail
    replace `v' = r(p50) if missing(`v')
}

* Standardize using 2010 distribution (mean 0, SD 1)
foreach v in base_wage base_hosp base_literacy base_pct_black {
    qui sum `v' if year == 2010
    gen double `v'_std = (`v' - r(mean)) / r(sd)
    label var `v'_std "Standardized `v' (2010 distribution)"
}

rename base_literacy_std   base_literacy_std
rename base_pct_black_std  base_pct_black_std

* ===========================================================================
* PART D — SAVE FULL PANEL (for maps and summary statistics)
* ===========================================================================
compress
sort municipality_code year
save "$data/panel_maps.dta", replace
di as text "  Saved: panel_maps.dta (" _N " obs)"

* ===========================================================================
* PART E — BUILD EVENT-STUDY PANEL (Target + Reference only)
* ===========================================================================

* Restrict to the two analysis groups
keep if inlist(strata_main, "Target (LI-HD)", "Reference (LI-LD)")
keep if !missing(base_wage) & !missing(base_hosp)

* Treatment indicator
gen byte treated = (strata_main == "Target (LI-HD)")
label define lbl_treated 0 "Reference (LI-LD)" 1 "Target (LI-HD)"
label values treated lbl_treated
label var treated "= 1 if Target (LI-HD) municipality"

* Event time: years relative to treatment year, clamped to analysis window
gen int event_time = year - $treat_year
replace event_time = -$pre_window if event_time < -$pre_window
replace event_time = $post_window if event_time > $post_window
label var event_time "Years relative to treatment (t* = $treat_year)"

* ---------------------------------------------------------------------------
* Event-time interaction dummies
*   Reference period: event_time == -1  → omitted (no dummy created)
*   Pre-treatment  : event_time == -k for k = 2, 3, 4
*   Post-treatment : event_time == k  for k = 0, 1, 2, 3
* ---------------------------------------------------------------------------
forvalues t = 2/$pre_window {
    gen byte pre`t' = (event_time == -`t') * treated
    label var pre`t' "Treated x (k = -`t')"
}
forvalues t = 0/$post_window {
    gen byte post`t' = (event_time == `t') * treated
    label var post`t' "Treated x (k = `t')"
}

* Re-declare as panel after subsetting
xtset municipality_code year

* Summary
qui levelsof municipality_code if treated == 1 & year == 2010
di as text _newline "  Treated municipalities  (Target)   : " `r(r)'
qui levelsof municipality_code if treated == 0 & year == 2010
di as text "  Control municipalities (Reference): " `r(r)'
di as text "  Total observations in analysis panel: " _N

compress
sort municipality_code year
save "$data/panel_analysis.dta", replace
di as text _newline " [02_strata_assign] Done. Saved: panel_analysis.dta (" _N " obs)"
