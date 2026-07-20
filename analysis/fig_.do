* ===========================================================================
* analysis/fig_1.do  -  Event study figures
* ===========================================================================
* INPUT  : Stored estimates from table_1.do (must run in the same session)
*          $data/panel_maps.dta  (for income-quartile heterogeneity figure)
*
* OUTPUT : $graphs/fig1a_hosp_event_study.png
*          $graphs/fig1b_mort_event_study.png
*          $graphs/fig1c_income_quartile_heterogeneity.png
*
* FIGURE STRUCTURE:
*   Fig 1a — Hospitalization rate: Basic vs. Controlled on same plot
*   Fig 1b — Mortality rate:       Basic vs. Controlled on same plot
*   Fig 1c — Hospitalization rate: HD vs. LD disease burden within each
*             income quartile (Q1 lowest to Q4 highest), basic spec only
*
* ---------------------------------------------------------------------------

di as text _newline " [fig_1] Drawing event study figures..."

* ---------------------------------------------------------------------------
* 0. Verify that required stored estimates are available
* ---------------------------------------------------------------------------
foreach m in m_hosp_basic m_hosp_ctrl m_mort_basic m_mort_ctrl {
    cap estimates restore `m'
    if _rc != 0 {
        di as error "  ERROR: estimate '`m'' not found. Run table_1.do first."
        exit 198
    }
}

* Variable order for all event-study plots (chronological)
local evars   pre4 pre3 pre2 post0 post1 post2 post3

* Coefficient labels for coefplot
local xlabels pre4="-4" pre3="-3" pre2="-2" post0="0" post1="1" post2="2" post3="3"

* Shared graphic options (applied to all three figures)
local gr_opts                                                           ///
    vertical                                                            ///
    yline(0, lpattern(dash) lcolor(gs10) lwidth(thin))                 ///
    xline(3.5, lpattern(dot) lcolor(gs10) lwidth(thin))                ///
    xtitle("Years relative to treatment" "(reference: k = -1, year 2012)", size(small)) ///
    ytitle("Coefficient estimate", size(small))                         ///
    legend(rows(1) position(6) size(vsmall) symxsize(2.5))             ///
    graphregion(color(white)) bgcolor(white)                            ///
    ysize(4) xsize(9)

* ===========================================================================
* FIGURE 1a — Hospitalization Rate: Basic vs. Controlled
* ===========================================================================
coefplot                                                                ///
    (m_hosp_basic,                                                      ///
        label("Basic")                                                  ///
        msymbol(circle) mcolor(navy) msize(medsmall)                    ///
        ciopts(recast(rcap) lcolor(navy) lwidth(medthick)))             ///
    (m_hosp_ctrl,                                                       ///
        label("With baseline {&times} year controls")                   ///
        msymbol(triangle) mcolor(cranberry) msize(medsmall)             ///
        ciopts(recast(rcap) lcolor(cranberry) lwidth(medthick)))        ///
    ,                                                                   ///
    keep(`evars') order(`evars') coeflabels(`xlabels')                  ///
    title("Event Study: Hospitalization Rate (per 10,000)", size(medsmall)) ///
    subtitle("Target (LI-HD) vs. Reference (LI-LD)  |  Municipality + Year FE  |  95% CI", ///
             size(vsmall))                                              ///
    `gr_opts'

graph export "$graphs/fig1a_hosp_event_study.png", replace width(2400)
di as text "  Saved: fig1a_hosp_event_study.png"

* ===========================================================================
* FIGURE 1b — Mortality Rate: Basic vs. Controlled
* ===========================================================================
coefplot                                                                ///
    (m_mort_basic,                                                      ///
        label("Basic")                                                  ///
        msymbol(circle) mcolor(navy) msize(medsmall)                    ///
        ciopts(recast(rcap) lcolor(navy) lwidth(medthick)))             ///
    (m_mort_ctrl,                                                       ///
        label("With baseline {&times} year controls")                   ///
        msymbol(triangle) mcolor(cranberry) msize(medsmall)             ///
        ciopts(recast(rcap) lcolor(cranberry) lwidth(medthick)))        ///
    ,                                                                   ///
    keep(`evars') order(`evars') coeflabels(`xlabels')                  ///
    title("Event Study: Mortality Rate (per 10,000)", size(medsmall))   ///
    subtitle("Target (LI-HD) vs. Reference (LI-LD)  |  Municipality + Year FE  |  95% CI", ///
             size(vsmall))                                              ///
    `gr_opts'

graph export "$graphs/fig1b_mort_event_study.png", replace width(2400)
di as text "  Saved: fig1b_mort_event_study.png"

* ===========================================================================
* FIGURE 1c — Heterogeneity: HD vs. LD within each income quartile
* ===========================================================================
di as text _newline "  Running income-quartile heterogeneity models for figure..."

use "$data/panel_maps.dta", clear

* Keep municipalities at the extremes of the disease distribution (Q1 and Q4)
* within each income quartile, so we can estimate Q4-vs-Q1 disease effect
keep if inlist(dis_q, 1, 4) & !missing(inc_q)

* Treatment = high disease burden (Q4) within each income group
gen byte treated_het = (dis_q == 4)
label var treated_het "= 1 if Q4 disease burden (high disease), within income quartile"

* Event time
gen int event_time = year - $treat_year
replace event_time = -$pre_window if event_time < -$pre_window
replace event_time = $post_window if event_time > $post_window

* Interaction dummies (same structure as main analysis)
forvalues t = 2/$pre_window {
    gen byte pre`t' = (event_time == -`t') * treated_het
}
forvalues t = 0/$post_window {
    gen byte post`t' = (event_time == `t') * treated_het
}

xtset municipality_code year

* Run basic event study within each income quartile (Q1 to Q4)
local qlabels `""Q1 Income (Lowest)" "Q2 Income" "Q3 Income" "Q4 Income (Highest)""'
local q = 0
foreach lbl of local qlabels {
    local ++q
    qui reghdfe hosp_rate `evars' if inc_q == `q', ///
        absorb(municipality_code year) cluster(municipality_code) nocons
    estimates store het_q`q'
    di as text "    Q`q' done: N=" e(N) "  Within R2=" %5.3f e(r2_within)
}

* Plot all four income quartiles on one graph
coefplot                                                                ///
    (het_q1, label("Q1 Income (Lowest)")                               ///
        msymbol(circle)   mcolor(navy)    ciopts(recast(rcap) lcolor(navy)))    ///
    (het_q2, label("Q2 Income")                                        ///
        msymbol(square)   mcolor(teal)    ciopts(recast(rcap) lcolor(teal)))    ///
    (het_q3, label("Q3 Income")                                        ///
        msymbol(diamond)  mcolor(orange)  ciopts(recast(rcap) lcolor(orange)))  ///
    (het_q4, label("Q4 Income (Highest)")                              ///
        msymbol(triangle) mcolor(maroon)  ciopts(recast(rcap) lcolor(maroon)))  ///
    ,                                                                   ///
    keep(`evars') order(`evars') coeflabels(`xlabels')                  ///
    title("Hosp. Rate: High vs. Low Disease Burden by Income Quartile", ///
          size(medsmall))                                               ///
    subtitle("Each series compares Q4 disease vs. Q1 disease within the same income quartile  |  95% CI", ///
             size(vsmall))                                              ///
    `gr_opts'

graph export "$graphs/fig1c_income_quartile_heterogeneity.png", replace width(2400)
di as text "  Saved: fig1c_income_quartile_heterogeneity.png"

di as text _newline " [fig_1] Done. All figures saved to: $graphs"
