;;
;; Butanoic Acid, ECP, RKS.
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
  (spin_restricted #t))                 ; HCl is closed shell
 (symmetry_group (point_group "C1"))
 (unique_atom_number (n_unique_atoms 14))
 (unique_atom (name "C1") (z 6) (n_equal_atoms 1))
 (2.68719131551167391874 -.03212535327967542659 0.0)
 (unique_atom (name "O1") (z 8) (n_equal_atoms 1))
 (2.68719131551167391874 2.55680017572946189315 0.0)
 (unique_atom (name "O2") (z 8) (n_equal_atoms 1))
 (4.99454757165777367597 -1.36438265105445047069 0.0)
 (unique_atom (name "C2") (z 6) (n_equal_atoms 1))
 (.18897266635103192114 -1.47398679753804898496 0.0)
 (unique_atom (name "C3") (z 6) (n_equal_atoms 1))
 (-2.00311026332093836418 .40062205266418767283 0.0)
 (unique_atom (name "C4") (z 6) (n_equal_atoms 1))
 (-4.49943918581807004256 -1.04123939159418588553 0.0)
 (unique_atom (name "OH") (z 1) (n_equal_atoms 1))
 (6.06602258986812466889 -.87116399187825715649 1.66673891721610154453)
 (unique_atom (name "H2") (z 1) (n_equal_atoms 1))
 (.08125824653094372609 -2.65884541555901913057 1.68185673052418409822)
 (unique_atom (name "H3") (z 1) (n_equal_atoms 1))
 (.08125824653094372609 -2.65884541555901913057 -1.68185673052418409822)
 (unique_atom (name "H4") (z 1) (n_equal_atoms 1))
 (-1.89350611683733984991 1.58359094402164749923 -1.68185673052418409822)
 (unique_atom (name "H5") (z 1) (n_equal_atoms 1))
 (-1.89350611683733984991 1.58359094402164749923 1.68185673052418409822)
 (unique_atom (name "H6") (z 1) (n_equal_atoms 1))
 (-4.60904333230166855683 -2.22609826201819051092 1.68185673052418409822)
 (unique_atom (name "H7") (z 1) (n_equal_atoms 1))
 (-4.60904333230166855683 -2.22609826201819051092 -1.68185673052418409822)
 (unique_atom (name "H8") (z 1) (n_equal_atoms 1))
 (-6.06602258986812466889 .29668708617112011620 0.0)
 (mixing (chmix 0.5) (start_after_cycle 5))
 (grid (sym_reduce #t) (weight_grads #t))
 (gridatom (nrad 30) (nang 131))
 (gridatom (nrad 30) (nang 131))
 (gridatom (nrad 30) (nang 131))
 (gridatom (nrad 30) (nang 131))
 (gridatom (nrad 30) (nang 131))
 (gridatom (nrad 30) (nang 131))
 (gridatom (nrad 30) (nang 131))
 (gridatom (nrad 30) (nang 131))
 (gridatom (nrad 30) (nang 131))
 (gridatom (nrad 30) (nang 131))
 (gridatom (nrad 30) (nang 131))
 (gridatom (nrad 30) (nang 131))
 (gridatom (nrad 30) (nang 131))
 (gridatom (nrad 30) (nang 131))
 (xc_control (xc "pbe"))
 (ecp "nwchem" "C" "crenbl_ecp" "ahlrichs_coulomb_fitting")
 (ecp "nwchem" "O" "crenbl_ecp" "ahlrichs_coulomb_fitting")
 (ecp "nwchem" "O" "crenbl_ecp" "ahlrichs_coulomb_fitting")
 (ecp "nwchem" "C" "crenbl_ecp" "ahlrichs_coulomb_fitting")
 (ecp "nwchem" "C" "crenbl_ecp" "ahlrichs_coulomb_fitting")
 (ecp "nwchem" "C" "crenbl_ecp" "ahlrichs_coulomb_fitting")
 (basis "nwchem" "H" "crenbl_ecp" "ahlrichs_coulomb_fitting")
 (basis "nwchem" "H" "crenbl_ecp" "ahlrichs_coulomb_fitting")
 (basis "nwchem" "H" "crenbl_ecp" "ahlrichs_coulomb_fitting")
 (basis "nwchem" "H" "crenbl_ecp" "ahlrichs_coulomb_fitting")
 (basis "nwchem" "H" "crenbl_ecp" "ahlrichs_coulomb_fitting")
 (basis "nwchem" "H" "crenbl_ecp" "ahlrichs_coulomb_fitting")
 (basis "nwchem" "H" "crenbl_ecp" "ahlrichs_coulomb_fitting")
 (basis "nwchem" "H" "crenbl_ecp" "ahlrichs_coulomb_fitting")
 (properties
  (plot_orbitals #t))
 (orbital_plot
  (n_input_lines 0)
  (density_plot #t)
  (density_tot #t)))
