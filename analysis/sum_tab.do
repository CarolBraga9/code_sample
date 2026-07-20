* ===========================================================================
* analysis/sum_tab.do  -  Table 1: Baseline characteristics by strata
* ===========================================================================
* INPUT  : $data/panel_maps.dta
*
* OUTPUT : $tables/table1_baseline.tex
*          $tables/table1_baseline.csv
*
* Shows 2010 cross-sectional mean values for each analytical strata.
* The four main groups (Target, Reference, Placebo HI-HD, Placebo HI-LD)
* are shown first; the residual "Middle" group follows.
* ---------------------------------------------------------------------------

di as text _newline " [sum_tab] Building Table 1: Baseline Characteristics..."

use "$data/panel_maps.dta", clear

* Restrict to 2010 baseline year
keep if year == 2010

* ---------------------------------------------------------------------------
* 1. Compute group-level means (collapse to strata x variable cells)
* ---------------------------------------------------------------------------
* Convert proportion to percentage for display
replace pct_black_parda = pct_black_parda * 100

collapse ///
    (count) n_muni    = municipality_code   ///
    (mean)  hosp      = hosp_rate           ///
            wage      = avg_wage_nominal     ///
            pop       = population           ///
            pct_black = pct_black_parda      ///
            literacy  = literacy_rate        ///
    , by(strata_main)

* Remove unclassified row (municipalities with no baseline wage)
drop if missing(strata_main) | strata_main == ""

* ---------------------------------------------------------------------------
* 2. Sort in preferred display order
* ---------------------------------------------------------------------------
gen byte sort_order = .
replace sort_order = 1 if strata_main == "Target (LI-HD)"
replace sort_order = 2 if strata_main == "Reference (LI-LD)"
replace sort_order = 3 if strata_main == "Placebo (HI-HD)"
replace sort_order = 4 if strata_main == "Placebo (HI-LD)"
replace sort_order = 5 if strata_main == "Middle"
sort sort_order

* ---------------------------------------------------------------------------
* 3. Display in Stata console
* ---------------------------------------------------------------------------
di as text _newline "  Table 1 — Baseline Characteristics (2010):"
list strata_main n_muni hosp wage pct_black literacy, ///
    sep(0) noobs abbreviate(20)

* ---------------------------------------------------------------------------
* 4. Export to CSV
* ---------------------------------------------------------------------------
export delimited using "$tables/table1_baseline.csv", replace
di as text "  Saved: table1_baseline.csv"

* ---------------------------------------------------------------------------
* 5. Export to LaTeX (hand-written for clean formatting)
* ---------------------------------------------------------------------------
file open fh using "$tables/table1_baseline.tex", write replace

file write fh "\begin{table}[H]" _newline
file write fh "\caption{\textbf{Baseline Characteristics (2010) by Strata}}" _newline
file write fh "\label{tab:baseline}" _newline
file write fh "\centering" _newline
file write fh "\resizebox{\textwidth}{!}{%" _newline
file write fh "\begin{tabular}{lrrrrr}" _newline
file write fh "    \toprule" _newline
file write fh "    \textbf{Strata} & \textbf{N munic.} & \textbf{Hosp.\ Rate} & \textbf{Avg.\ Wage} & \textbf{\% Black/Mixed} & \textbf{Literacy (\%)} \\" _newline
file write fh "    & & \textit{(per 10k)} & \textit{(R\$)} & & \\" _newline
file write fh "    \midrule" _newline

* Write one row per stratum
forvalues i = 1/`=_N' {
    local sname : di strata_main[`i']
    local n     : di %6.0f    n_muni[`i']
    local h     : di %9.1f    hosp[`i']
    local w     : di %9.1f    wage[`i']
    local b     : di %5.1f    pct_black[`i']
    local l     : di %5.1f    literacy[`i']
    file write fh "    `sname' & `n' & `h' & `w' & `b' & `l' \\" _newline
}

file write fh "    \bottomrule" _newline
file write fh "\end{tabular}}" _newline
file write fh "\begin{tablenotes}" _newline
file write fh "\small" _newline
file write fh "\item \textit{Notes:} Mean values in 2010. Hosp.\ Rate = preventable hospitalizations per 10,000 residents. Avg.\ Wage = average nominal monthly wage (R\$). Primary event study sample uses Target and Reference only (754 municipalities, 6{,}786 observations)." _newline
file write fh "\end{tablenotes}" _newline
file write fh "\end{table}" _newline

file close fh
di as text "  Saved: table1_baseline.tex"
di as text " [sum_tab] Done."
