* ===========================================================================
* analysis/table_2.do  -  Table 3: Income-quartile heterogeneity in event study
* ===========================================================================
* INPUT  : $data/panel_maps.dta
*
* OUTPUT : $tables/table3_heterogeneity.tex  (LaTeX via esttab)
*
* DESIGN:
*   Estimates the hospitalization event study for each income quartile
*   separately, comparing high-disease-burden (Q4) against low-disease-burden
*   (Q1) municipalities within that quartile.  Under the price-sensitivity
*   mechanism, the treatment effect should be largest (most negative post-
*   treatment) in the lowest-income quartile and decrease monotonically as
*   income rises.
*
*   One column per income quartile; basic specification (municipality + year
*   FE, clustered SE) for comparability across groups.
* ---------------------------------------------------------------------------

di as text _newline " [table_2] Running heterogeneity by income quartile..."

use "$data/panel_maps.dta", clear

* ---------------------------------------------------------------------------
* 1. Sample: municipalities at disease extremes (Q1 low, Q4 high)
* ---------------------------------------------------------------------------
keep if inlist(dis_q, 1, 4) & !missing(inc_q)

* Treatment indicator: Q4 disease = treated within each income group
gen byte treated_het = (dis_q == 4)
label var treated_het "= 1 if Q4 disease burden within income quartile"

* ---------------------------------------------------------------------------
* 2. Event time and interaction dummies
* ---------------------------------------------------------------------------
gen int event_time = year - $treat_year
replace event_time = -$pre_window if event_time < -$pre_window
replace event_time = $post_window if event_time > $post_window

local evars pre4 pre3 pre2 post0 post1 post2 post3

forvalues t = 2/$pre_window {
    gen byte pre`t' = (event_time == -`t') * treated_het
    label var pre`t' "Treated_het x (k = -`t')"
}
forvalues t = 0/$post_window {
    gen byte post`t' = (event_time == `t') * treated_het
    label var post`t' "Treated_het x (k = `t')"
}

xtset municipality_code year

* ---------------------------------------------------------------------------
* 3. Run event study within each income quartile
* ---------------------------------------------------------------------------
forvalues q = 1/4 {
    reghdfe hosp_rate `evars' if inc_q == `q', ///
        absorb(municipality_code year)          ///
        cluster(municipality_code)              ///
        nocons

    estimates store het_q`q'
    di as text "  Q`q': N=" e(N) "  clusters=" e(N_clust) "  Within R2=" %6.4f e(r2_within)
}

* ---------------------------------------------------------------------------
* 4. Export LaTeX table
* ---------------------------------------------------------------------------
esttab het_q1 het_q2 het_q3 het_q4                                    ///
    using "$tables/table3_heterogeneity.tex", replace                  ///
    booktabs                                                           ///
    keep(`evars') order(`evars')                                       ///
    coeflabels(                                                        ///
        pre4  "Treated \$\times\$ \$k = -4\$"                         ///
        pre3  "Treated \$\times\$ \$k = -3\$"                         ///
        pre2  "Treated \$\times\$ \$k = -2\$"                         ///
        post0 "Treated \$\times\$ \$k = 0\$"                          ///
        post1 "Treated \$\times\$ \$k = 1\$"                          ///
        post2 "Treated \$\times\$ \$k = 2\$"                          ///
        post3 "Treated \$\times\$ \$k = 3\$")                         ///
    mtitles("Q1 (Lowest)" "Q2" "Q3" "Q4 (Highest)")                   ///
    mgroups("Hospitalization Rate (per 10,000): High vs. Low Disease Burden by Income Quartile", ///
            pattern(1 0 0 0)                                           ///
            prefix(\multicolumn{@span}{c}{) suffix(}) span)            ///
    stats(N r2_within N_clust,                                         ///
          fmt(0 3 0)                                                   ///
          labels("Observations" "Within R\$^2\$" "Municipalities"))    ///
    star(* 0.1 ** 0.05 *** 0.01)                                       ///
    se                                                                 ///
    note("Municipality and year fixed effects. SE clustered at municipality level." ///
         "Each column compares Q4-disease vs Q1-disease municipalities within the income quartile." ///
         "Reference period: \$k = -1\$ (year 2012). Treatment indicator = 1 for Q4-disease municipalities.") ///
    label

di as text "  Saved: table3_heterogeneity.tex"

* ---------------------------------------------------------------------------
* 5. Console preview
* ---------------------------------------------------------------------------
di as text _newline "  --- Console Preview ---"
esttab het_q1 het_q2 het_q3 het_q4,                                   ///
    keep(`evars') order(`evars')                                       ///
    star(* 0.1 ** 0.05 *** 0.01) se                                   ///
    stats(N r2_within, fmt(0 3) labels("N" "Within R2"))              ///
    mtitles("Q1 Income" "Q2 Income" "Q3 Income" "Q4 Income")

di as text _newline " [table_2] Done."
