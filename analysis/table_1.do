* ===========================================================================
* analysis/table_1.do  -  Table 2: Event study regression coefficients
* ===========================================================================
* INPUT  : $data/panel_analysis.dta
*
* OUTPUT : $tables/table2_event_study.tex  (LaTeX via esttab)
*
* MODELS:
*   (1) Hosp. Rate   — Basic     (municipality + year FE)
*   (2) Hosp. Rate   — Controlled (+ baseline x year interaction trends)
*   (3) Mortality Rate — Basic
*   (4) Mortality Rate — Controlled
*
* All models: municipality FE, year FE, SE clustered by municipality.
* Reference period: k = -1 (year 2012) — omitted by construction.
* "Controlled" adds: standardized baseline wage, hospitalization rate,
*  literacy, and race share, each interacted with year dummies.  This
*  allows municipalities to follow characteristic-specific time trends,
*  partially addressing the parallel-trends concern visible in pre-trends.
*
* Stored estimates (for fig_1.do): m_hosp_basic, m_hosp_ctrl,
*                                   m_mort_basic, m_mort_ctrl
* ---------------------------------------------------------------------------

di as text _newline " [table_1] Running event study regressions (4 models)..."

use "$data/panel_analysis.dta", clear

* Locals for regressor lists (keeps regression commands concise)
local evars  pre4 pre3 pre2 post0 post1 post2 post3
local trends c.base_wage_std#i.year      ///
             c.base_hosp_std#i.year      ///
             c.base_literacy_std#i.year  ///
             c.base_pct_black_std#i.year

* ===========================================================================
* MODEL 1: Hospitalization rate — Basic specification
* ===========================================================================
reghdfe hosp_rate `evars' , ///
    absorb(municipality_code year) ///
    cluster(municipality_code) ///
    nocons

estimates store m_hosp_basic
di as text "  (1) Hosp. Rate   — Basic     : N=" e(N) "  Within R2=" %6.4f e(r2_within)

* ===========================================================================
* MODEL 2: Hospitalization rate — Controlled specification
* ===========================================================================
* The baseline-x-year terms are nuisance controls; they absorb municipality-
* specific linear (and nonlinear, via the full year-FE interaction) trends
* driven by pre-policy observable differences.

reghdfe hosp_rate `evars' `trends' , ///
    absorb(municipality_code year) ///
    cluster(municipality_code) ///
    nocons

estimates store m_hosp_ctrl
di as text "  (2) Hosp. Rate   — Controlled: N=" e(N) "  Within R2=" %6.4f e(r2_within)

* ===========================================================================
* MODEL 3: Mortality rate — Basic specification
* ===========================================================================
reghdfe mortality_rate `evars' , ///
    absorb(municipality_code year) ///
    cluster(municipality_code) ///
    nocons

estimates store m_mort_basic
di as text "  (3) Mort. Rate   — Basic     : N=" e(N) "  Within R2=" %6.4f e(r2_within)

* ===========================================================================
* MODEL 4: Mortality rate — Controlled specification
* ===========================================================================
reghdfe mortality_rate `evars' `trends' , ///
    absorb(municipality_code year) ///
    cluster(municipality_code) ///
    nocons

estimates store m_mort_ctrl
di as text "  (4) Mort. Rate   — Controlled: N=" e(N) "  Within R2=" %6.4f e(r2_within)

* ===========================================================================
* EXPORT: LaTeX regression table
* ===========================================================================
esttab m_hosp_basic m_hosp_ctrl m_mort_basic m_mort_ctrl          ///
    using "$tables/table2_event_study.tex", replace                ///
    booktabs                                                       ///
    keep(`evars')                                                  ///
    order(`evars')                                                 ///
    coeflabels(                                                    ///
        pre4  "Treated \$\times\$ \$k = -4\$"                     ///
        pre3  "Treated \$\times\$ \$k = -3\$"                     ///
        pre2  "Treated \$\times\$ \$k = -2\$"                     ///
        post0 "Treated \$\times\$ \$k = 0\$"                      ///
        post1 "Treated \$\times\$ \$k = 1\$"                      ///
        post2 "Treated \$\times\$ \$k = 2\$"                      ///
        post3 "Treated \$\times\$ \$k = 3\$")                     ///
    mtitles("Hosp. Basic" "Hosp. Controlled" "Mort. Basic" "Mort. Controlled") ///
    mgroups("Hospitalization Rate (per 10,000)" "Mortality Rate (per 10,000)", ///
            pattern(1 0 1 0)                                       ///
            prefix(\multicolumn{@span}{c}{) suffix(})              ///
            span erepeat(\cmidrule(lr){@span}))                    ///
    stats(N r2 r2_within N_clust,                                  ///
          fmt(0 3 3 0)                                             ///
          labels("Observations" "R\$^2\$" "Within R\$^2\$" "Municipalities")) ///
    star(* 0.1 ** 0.05 *** 0.01)                                   ///
    se                                                             ///
    note("Municipality and year fixed effects in all models."      ///
         "Standard errors clustered at the municipality level in parentheses." ///
         "Reference period: \$k = -1\$ (year 2012)."              ///
         "313 treated (Target LI-HD) and 441 control (Reference LI-LD) municipalities." ///
         "Controlled models add standardized 2010 baseline wage, hospitalization rate," ///
         "literacy rate, and race share each interacted with year dummies.")  ///
    label

di as text "  Saved: table2_event_study.tex"

* ===========================================================================
* Quick console preview of results
* ===========================================================================
di as text _newline "  --- Console Preview ---"
esttab m_hosp_basic m_hosp_ctrl m_mort_basic m_mort_ctrl,          ///
    keep(`evars') order(`evars')                                   ///
    star(* 0.1 ** 0.05 *** 0.01) se                               ///
    stats(N r2_within, fmt(0 3) labels("N" "Within R2"))          ///
    mtitles("Hosp Basic" "Hosp Ctrl" "Mort Basic" "Mort Ctrl")

di as text _newline " [table_1] Done."
