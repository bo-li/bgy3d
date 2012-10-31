;;
;; hexane ECP, RKS.
;;
((operations
  (operations_symm #t)
  (operations_integral #t)
  (operations_scf #t)
  (operations_properties #t))
 ;; (tasks (task "Gradients"))
 (main_options
  (integrals_on_file #f)                ; This is faster
  (relativistic "false")                ; This is an ECP calculation
  (spin_restricted #t))                 ; hexane is closed shell
 (geo
  ("C" (3.22954323411637316058 -5.31391198030148702608 0.0))
  ("C" (3.18230006217201427877 -2.41507094979562603816 0.0))
  ("C" (0.46298308505471704174 -1.42296433896408952014 0.0))
  ("C" (0.45542417754361962065 1.47209723778622275722 0.0))
  ("C" (-2.26389279957367761637 2.46420384861775927525 0.0))
  ("C" (-2.27901061459587245855 5.35548597161252284207 0.0))
  ("H" (4.22542929870345838915 -5.97909584127806008197 1.67618774058585312664))
  ("H" (4.21787039119236096806 -5.97909584127806008197 -1.68185692121917619246))
  ("H" (1.30580127254207949325 -6.05468491638903429287 .00566918063332306581))
  ("H" (4.16117858485913030989 -1.72721036628576071900 -1.67807746746362748192))
  ("H" (4.15928885798135595462 -1.72721036628576071900 1.68185692121917619246))
  ("H" (-0.51589543763239898937 -2.10704546871840612876 1.67996719434140183719))
  ("H" (-0.51400571075462463410 -2.10704546871840612876 -1.68185692121917619246))
  ("H" (1.43052324647518694123 2.15806809441831372111 -1.68185692121917619246))
  ("H" (1.43052324647518694123 2.15806809441831372111 1.68185692121917619246))
  ("H" (-3.24277132226079364749 1.78390217261899137717 1.68185692121917619246))
  ("H" (-3.24277132226079364749 1.78390217261899137717 -1.68185692121917619246))
  ("H" (-1.31524990693095126961 6.05468491638903429287 -1.68185692121917619246))
  ("H" (-1.31524990693095126961 6.05468491638903429287 1.68185692121917619246))
  ("H" (-4.22542929870345838915 6.02822874010019331905 0.0)))
 (mixing (chmix 0.5) (start_after_cycle 5))
 (grid (sym_reduce #t) (weight_grads #t))
 (rep 20 (gridatom (nrad 30) (nang 131)))
 (xc_control (xc "pbe"))
 (ecp "nwchem" "C" "crenbl_ecp" "ahlrichs_coulomb_fitting")
 (ecp "nwchem" "C" "crenbl_ecp" "ahlrichs_coulomb_fitting")
 (ecp "nwchem" "C" "crenbl_ecp" "ahlrichs_coulomb_fitting")
 (ecp "nwchem" "C" "crenbl_ecp" "ahlrichs_coulomb_fitting")
 (ecp "nwchem" "C" "crenbl_ecp" "ahlrichs_coulomb_fitting")
 (ecp "nwchem" "C" "crenbl_ecp" "ahlrichs_coulomb_fitting")
 (bas "nwchem" "H" "crenbl_ecp" "ahlrichs_coulomb_fitting")
 (bas "nwchem" "H" "crenbl_ecp" "ahlrichs_coulomb_fitting")
 (bas "nwchem" "H" "crenbl_ecp" "ahlrichs_coulomb_fitting")
 (bas "nwchem" "H" "crenbl_ecp" "ahlrichs_coulomb_fitting")
 (bas "nwchem" "H" "crenbl_ecp" "ahlrichs_coulomb_fitting")
 (bas "nwchem" "H" "crenbl_ecp" "ahlrichs_coulomb_fitting")
 (bas "nwchem" "H" "crenbl_ecp" "ahlrichs_coulomb_fitting")
 (bas "nwchem" "H" "crenbl_ecp" "ahlrichs_coulomb_fitting")
 (bas "nwchem" "H" "crenbl_ecp" "ahlrichs_coulomb_fitting")
 (bas "nwchem" "H" "crenbl_ecp" "ahlrichs_coulomb_fitting")
 (bas "nwchem" "H" "crenbl_ecp" "ahlrichs_coulomb_fitting")
 (bas "nwchem" "H" "crenbl_ecp" "ahlrichs_coulomb_fitting")
 (bas "nwchem" "H" "crenbl_ecp" "ahlrichs_coulomb_fitting")
 (bas "nwchem" "H" "crenbl_ecp" "ahlrichs_coulomb_fitting")
 (properties
  (plot_orbitals #t))
 (orbital_plot
  (n_input_lines 0)
  (density_plot #t)
  (density_tot #t)))

;;;
;;; BGY3d input  follows. The parameter solute specifies  the table to
;;; take the  site-specific force field  parameters. The names  of the
;;; sites are those specified in PG input above:
;;;
((solute "hexane"))
