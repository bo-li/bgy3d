/*==========================================================*/
/*  $Id: bgy3dH2O_solutes.c,v 1.3 2007-08-03 15:59:50 jager Exp $ */
/*==========================================================*/

#include "bgy3d.h"
#include "bgy3d_SolventParameters.h"

typedef struct Site {
    char name[5];            /* atom types. What are they used for? */
    real x[3];               /* coordinates */
    real sigma;              /* sigma for LJ */
    real epsilon;            /* epsilon for LJ */
    real charge;             /* charge */
} Site;

/* Solute is  isomorphic to an  array of sites.  Consider  handling it
   like that in the code.   Structs with flexible array members may be
   confusing. Such struct is convenient for literal data, though: */
typedef struct Solute {
    int n;                      /* number of sites */
    Site sites[];               /* site descriptions */
} Solute;

#if 0
static void ComputeSoluteDatafromCoulomb (BGY3dH2OData BHD, Vec uc, const real x0[3], real q2);
#endif
static void ComputeSoluteDatafromCoulombII (BGY3dH2OData BHD, Vec uc, const real x0[3], real q2);
static void ComputeSoluteDatafromCoulomb_QM (BGY3dH2OData BHD, Vec uc, Vec gs, real q);
static void RecomputeInitialSoluteData_QM (BGY3dH2OData BHD, const Site S[], int nsites, real damp, real damp_LJ);
static void RecomputeInitialSoluteData_II (BGY3dH2OData BHD, const Site S[], int nsites, real damp, real damp_LJ);

/*
 * These two functions  obey the same interface. They  are supposed to
 * get (1)  parameters of  the solvent site  such as its  location and
 * force field  parameters, and  (2) a description  of the  solute and
 * return a  real number such as  an interaction energy  or the charge
 * density:
 */
static real ljc (real x, real y, real z, real epsilon, real sigma, real charge, const Site S[], int nsites);
static real rho (real x, real y, real z, real epsilon, real sigma, real charge, const Site S[], int nsites);

/*
 * This function expects a callback obeying the above interface as one
 * of the arguments:
 */
static void field (DA da, const ProblemData *PD,
                   const Site S[], int nsites,
                   real epsilon, real sigma, real charge, real fact,
                   double (*f)(real x, real y, real z,
                               real eps, real sig, real chg,
                               const Site S[], int nsites),
                   Vec v);

// FIXME: maybe #include "solutes.h" instead?

/*********************************/
/* Water */
/*********************************/

static Solute Water =
  {3, {{"O", {-0.2929, 0.0, 0.0}, 3.1506, 0.1521, -0.834},
       {"OH", {0.2929, 0.757, 0.0}, 0.4, 0.046, 0.417},
       {"OH", {0.2929, -0.757, 0.0}, 0.4, 0.046, 0.417}}};

/*********************************/
/* CS2 */
/*********************************/

static Solute CarbonDisulfide =
  {3, {{"C", {0.0, 0.0, 0.0}, 3.2, 0.10128, -0.308},
       {"S1", {-1.56, 0.0, 0.0}, 3.52, 0.395, 0.154},
       {"S2", {1.56, 0.0, 0.0}, 3.52, 0.395, 0.154}}};

/*********************************/
/* HCl */
/*********************************/

static Solute HydrogenChloride =
  {2, {{"H", {0.6285, 0.0, 0.0}, 2.735, 0.03971, 0.2},
       {"Cl", {-0.6285, 0.0, 0.0}, 3.353, 0.51434, -0.2}}};

/*********************************/
/* Methanol */
/*********************************/

static Solute Methanol =
  {6, {{"C", {-0.748, -0.015, 0.024}, 3.5, 0.066, 0.145},
       {"HC1", {-1.293, -0.202, -0.901}, 2.5, 0.03, 0.04},
       {"HC2", {-1.263, 0.754, 0.6}, 2.5, 0.03, 0.04},
       {"HC3", {-0.699, -0.934, 0.609}, 2.5, 0.03, 0.04},
       {"O", {0.558, 0.42, -0.278}, 3.12, 0.17, -0.683},
       {"OH", {0.716, 1.404, 0.137}, 0.4, 0.04, 0.418}}};

/*********************************/
/* Hexane */
/*********************************/

static Solute Hexane =
  {20, {{"C", {1.709, -2.812, 0.0}, 3.5, 0.066, -0.18},
        {"C", {1.684, -1.278, 0.0}, 3.5, 0.066, -0.12},
        {"C", {0.245, -0.753, 0.0}, 3.5, 0.066, -0.12},
        {"C", {0.241, 0.779, 0.0}, 3.5, 0.066, -0.12},
        {"C", {-1.198, 1.304, 0.0}, 3.5, 0.066, -0.12},
        {"C", {-1.206, 2.834, 0.0}, 3.5, 0.066, -0.18},
        {"H", {2.236, -3.164, 0.887}, 2.5, 0.03, 0.06},
        {"H", {2.232, -3.164, -0.89}, 2.5, 0.03, 0.06},
        {"H", {0.691, -3.204, 0.003}, 2.5, 0.03, 0.06},
        {"H", {2.202, -0.914, -0.888}, 2.5, 0.03, 0.06},
        {"H", {2.201, -0.914, 0.89}, 2.5, 0.03, 0.06},
        {"H", {-0.273, -1.115, 0.889}, 2.5, 0.03, 0.06},
        {"H", {-0.272, -1.115, -0.89}, 2.5, 0.03, 0.06},
        {"H", {0.757, 1.142, -0.89}, 2.5, 0.03, 0.06},
        {"H", {0.757, 1.141, 0.89}, 2.5, 0.03, 0.06},
        {"H", {-1.716, 0.944, 0.89}, 2.5, 0.03, 0.06},
        {"H", {-1.716, 0.944, -0.89}, 2.5, 0.03, 0.06},
        {"H", {-0.696, 3.204, -0.89}, 2.5, 0.03, 0.06},
        {"H", {-0.696, 3.204, 0.89}, 2.5, 0.03, 0.06},
        {"H", {-2.236, 3.19, 0.0}, 2.5, 0.03, 0.06}}};

/* BUTANOIC ACID */
/* H1 sigma and epsilon adopted */

static Solute ButanoicAcid =
  {14, {{"C1", {1.422, -0.017, 0.0}, 3.75, 0.105, 0.52},
        {"O1", {1.422, 1.353, 0.0}, 2.96, 0.21, -0.44},
        {"O2", {2.643, -0.722, 0.0}, 3.0, 0.17, -0.53},
        {"C2", {0.1, -0.78, 0.0}, 3.5, 0.066, -0.12},
        {"C3", {-1.06, 0.212, 0.0}, 3.5, 0.066, -0.12},
        {"C4", {-2.381, -0.551, 0.0}, 3.5, 0.066, -0.18},
        {"OH", {3.21, -0.461, 0.882}, 3.4, 0.046, 0.45},
        {"H2", {0.043, -1.407, 0.89}, 2.5, 0.03, 0.06},
        {"H3", {0.043, -1.407, -0.89}, 2.5, 0.03, 0.06},
        {"H4", {-1.002, 0.838, -0.89}, 2.5, 0.03, 0.06},
        {"H5", {-1.002, 0.838, 0.89}, 2.5, 0.03, 0.06},
        {"H6", {-2.439, -1.178, 0.89}, 2.5, 0.03, 0.06},
        {"H7", {-2.439, -1.178, -0.89}, 2.5, 0.03, 0.06},
        {"H8", {-3.21, 0.157, 0.0}, 2.5, 0.03, 0.06}}};

static void recompute_initial_data (BGY3dH2OData BHD, const Solute *S, real damp, real damp_LJ)
{
    /* Functions that do the real work operate on array of sites: */
#ifndef QM
    RecomputeInitialSoluteData_II (BHD, S->sites, S->n, damp, damp_LJ);
#else
    RecomputeInitialSoluteData_QM (BHD, S->sites, S->n, damp, damp_LJ);
#endif
}

void RecomputeInitialSoluteData_Water(BGY3dH2OData BHD, real damp, real damp_LJ, real zpad)
{
  PetscPrintf(PETSC_COMM_WORLD,"Solute is Water.\n");
  recompute_initial_data (BHD, &Water, damp, damp_LJ);
}

void RecomputeInitialSoluteData_CS2(BGY3dH2OData BHD, real damp, real damp_LJ, real zpad)
{
  PetscPrintf(PETSC_COMM_WORLD,"Solute is CarbonDisulfide.\n");
  recompute_initial_data (BHD, &CarbonDisulfide, damp, damp_LJ);
}

void RecomputeInitialSoluteData_HCl(BGY3dH2OData BHD, real damp, real damp_LJ, real zpad)
{
  PetscPrintf(PETSC_COMM_WORLD,"Solute is HCl.\n");
  recompute_initial_data (BHD, &HydrogenChloride, damp, damp_LJ);
}

void RecomputeInitialSoluteData_Methanol(BGY3dH2OData BHD, real damp, real damp_LJ, real zpad)
{
  PetscPrintf(PETSC_COMM_WORLD,"Solute is Methanol.\n");
  recompute_initial_data (BHD, &Methanol, damp, damp_LJ);
}

void RecomputeInitialSoluteData_Hexane(BGY3dH2OData BHD, real damp, real damp_LJ, real zpad)
{
  PetscPrintf(PETSC_COMM_WORLD,"Solute is Hexane.\n");
  recompute_initial_data (BHD, &Hexane, damp, damp_LJ);
}

void RecomputeInitialSoluteData_ButanoicAcid(BGY3dH2OData BHD, real damp, real damp_LJ, real zpad)
{
  PetscPrintf(PETSC_COMM_WORLD,"Solute is Butanoic Acid.\n");
  recompute_initial_data (BHD, &ButanoicAcid, damp, damp_LJ);
}

/*
 * Create initial solute data.
 *
 * XXX: See (5.106) and (5.08)  in the thesis.  Return BHD->gH_ini and
 *      BHD->gO_ini (beta *  (VM_LJ + VM_coulomb_short)) and BHD->ucH,
 *      BHD->ucO (beta * VM_coulomb_long), but is beta missing here?
 */

static void RecomputeInitialSoluteData_II(BGY3dH2OData BHD, const Site S[], int nsites, real damp, real damp_LJ)
{
  PetscPrintf(PETSC_COMM_WORLD,"Recomputing solute data with damping factor %f (damp_LJ=%f)\n", damp, damp_LJ);

  VecSet(BHD->gHO_ini, 0.0);    /* What is it used for? */
  VecSet(BHD->ucHO, 0.0);
  FOR_DIM
    {
      VecSet(BHD->fH_l[dim], 0.0);
      VecSet(BHD->fO_l[dim], 0.0);
      VecSet(BHD->fHO_l[dim], 0.0); /* What is it used for? */
    }

  /*
    Calculate FF potential for all solvent sites.

    Beta  is the  (inverse) temperature.   For historical  reasons the
    solute  field  acting on  solvent  sites  is  defined having  this
    factor.

    FIXME:  scaling the  epsilon of  the  solvent site  by factor  X^2
    scales the interaction with the  solute by factor X. Why not using
    this fact instead of handling damp/damp_LJ separately?  Similarly,
    scaling the  solvent site  charge by a  factor scales  the Coulomb
    interaction.  At  least in the  two test examples the  two factors
    are  identical.   Initial  version  of  the code  scaled  LJ-  and
    short-range Coulomb interaction  using two different factors.  The
    new code uses just one, that is why the assertion:
  */
  real factor = damp * BHD->PD->beta;
  assert (damp == damp_LJ);
  assert (factor >= 0.0);

  /*
   * Fill ff-interaction  of H  and O sites  with the solute  into the
   * respective arrays.
   *
   * FIXME: Force field parameters, (eH, sH, qH) and (eO, sO, qO), for
   * H and O are #defined at some obscure place:
   *
   * We  supply ljc()  as  a  callback function  that  is supposed  to
   * compute the  interaction of  a charged LJ  solvent site  with the
   * solute.
   */
  field (BHD->da, BHD->PD, S, nsites, eH, sH, qH, factor, ljc, BHD->gH_ini);
  field (BHD->da, BHD->PD, S, nsites, eO, sO, qO, factor, ljc, BHD->gO_ini);

  /*
   * Compute the charge density  of the solute.  The callback function
   * rho() sums charge distribution for  each solute site and does not
   * use (epsilon,  sigma, charge) parameters of the  solvent site, so
   * that  we  provide -1.0  for  them.   The  overall factor  is  1.0
   * (idependent of the solvent charge):
   */

  Vec rho_solute; /* Vector for solute charge density */

  DACreateGlobalVector (BHD->da, &rho_solute);

  field (BHD->da, BHD->PD, S, nsites, -1.0, -1.0, -1.0, 1.0, rho, rho_solute);

  /*
   * This  solves the  Poisson equation  and puts  resulting potential
   * into a pre-allocated (?) vector BHD->v[0].
   */
  ComputeSoluteDatafromCoulomb_QM (BHD, BHD->v[0], rho_solute, 1.0 * damp);

  VecDestroy (rho_solute);

  VecSet (BHD->ucH, 0.0);
  VecAXPY (BHD->ucH, qH, BHD->v[0]);

  VecSet (BHD->ucO, 0.0);
  VecAXPY (BHD->ucO, qO, BHD->v[0]);
}


#if 0
static void ComputeSoluteDatafromCoulomb (BGY3dH2OData BHD, Vec uc, const real x0[3], real q2)
{
    DA da;
    ProblemData *PD;
    int x[3], n[3], i[3], ic[3], N[3], index;
    real h[3], interval[2], k, fac, L, sign, fac2, L2;
    fftw_complex *fft_data;

    PD = BHD->PD;
    da = BHD->da;
    fft_data = BHD->g_fft;

    FOR_DIM
        h[dim] = PD->h[dim];
    FOR_DIM
        N[dim] = PD->N[dim];

    interval[0] = PD->interval[0];
    L = PD->interval[1] - PD->interval[0];
    L2 = 0.5 * L;

    /* Get local portion of the grid */
    DAGetCorners(da, &(x[0]), &(x[1]), &(x[2]), &(n[0]), &(n[1]), &(n[2]));

    /* Loop over local portion of the k-grid */
    index = 0;
    for (i[2] = x[2]; i[2] < x[2] + n[2]; i[2]++)
        for (i[1] = x[1]; i[1] < x[1] + n[1]; i[1]++)
            for (i[0] = x[0]; i[0] < x[0] + n[0]; i[0]++)
                {
                    /* set force vectors */

                    FOR_DIM {
                        if (i[dim] <= N[dim] / 2)
                            ic[dim] = i[dim];
                        else
                            ic[dim] = i[dim] - N[dim];
                    }

                    if (ic[0] == 0 && ic[1] == 0 && ic[2] == 0) {
                        /* No  point  to  scale   zeros  with  q2  *  fac,
                           obviousely: */
                        fft_data[index].re = 0;
                        fft_data[index].im = 0;
                    }
                    else {
                        k = (SQR(ic[2]) + SQR(ic[1]) + SQR(ic[0])) / SQR(L);
                        fac = EPSILON0INV / M_PI / k;
                        fac2= 2. * M_PI / L;
                        sign = cos(fac2 * ic[0] * (x0[0] - L2)) * cos(fac2 * ic[1] * (x0[1] - L2))
                            * cos(fac2 * ic[2] * (x0[2] - L2));
                        // sign = COSSIGN(ic[0]) * COSSIGN(ic[1]) * COSSIGN(ic[2]);
                        /* potential */
                        fft_data[index].re = q2 * sign * fac * exp(-k * SQR(M_PI) / SQR(G));
                        fft_data[index].im = 0;

                    }
                    index++;
                }

    /* FFT potential */
    ComputeVecfromFFT_fftw(da, BHD->fft_plan_bw, uc, fft_data,
                           BHD->fft_scratch, x, n, 0);

    VecScale(uc, 1./L/L/L);
}
#endif


static void ComputeSoluteDatafromCoulombII (BGY3dH2OData BHD, Vec uc, const real x0[3], real q2)
{
    DA da;
    ProblemData *PD;
    int x[3], n[3], i[3], ic[3], N[3], index;
    real r[3], h[3], interval[2], k, fac, L, h3;
    fftw_complex *fft_data, *dg_fft;
    PetscScalar ***v_vec;

    PD = BHD->PD;
    da = BHD->da;
    fft_data = BHD->g_fft;
    dg_fft = BHD->gfg2_fft;
    FOR_DIM
        h[dim] = PD->h[dim];
    FOR_DIM
        N[dim] = PD->N[dim];
    h3 = h[0] * h[1] * h[2];

    interval[0] = PD->interval[0];
    L = PD->interval[1] - PD->interval[0];

    /* Get local portion of the grid */
    DAGetCorners(da, &(x[0]), &(x[1]), &(x[2]), &(n[0]), &(n[1]), &(n[2]));

    DAVecGetArray(da, uc, &v_vec);

    /*                        3         2 2
     * rho(r) = (G / sqrt(PI))   exp(- G r )
     */
    fac = pow(G / sqrt(M_PI), 3.0);

    /* loop over local portion of grid */
    for (i[2] = x[2]; i[2] < x[2] + n[2]; i[2]++)
        for (i[1] = x[1]; i[1] < x[1] + n[1]; i[1]++)
            for (i[0] = x[0]; i[0] < x[0] + n[0]; i[0]++) {
                /* set force vectors */

                FOR_DIM
                    r[dim] = i[dim] * h[dim] + interval[0] - x0[dim];

                // XXX:  Gaussian distribution
                real r_s = sqrt(SQR(r[0]) + SQR(r[1]) + SQR(r[2]));

                v_vec[i[2]][i[1]][i[0]] = fac * exp(-SQR(r_s * G));
            }
    DAVecRestoreArray(da, uc, &v_vec);

    // XXX:  convert to fft_complex
    ComputeFFTfromVec_fftw(da, BHD->fft_plan_fw, uc, fft_data,
                           BHD->fft_scratch, x, n, 0);

    /* Loop over local portion of the k-grid: */
    index = 0;
    for (i[2] = x[2]; i[2] < x[2] + n[2]; i[2]++)
        for (i[1] = x[1]; i[1] < x[1] + n[1]; i[1]++)
            for (i[0] = x[0]; i[0] < x[0] + n[0]; i[0]++) {
                /* set force vectors */

                FOR_DIM {
                    if (i[dim] <= N[dim] / 2)
                        ic[dim] = i[dim];
                    else
                        ic[dim] = i[dim] - N[dim];
                }

                if (ic[0] == 0 && ic[1] == 0 && ic[2] == 0) {
                    /* No  point  to  scale   zeros  with  q2  *  fac,
                       obviousely: */
                    dg_fft[index].re = 0;
                    dg_fft[index].im = 0;
                }
                else {
                    // XXX:  Fourier component of V_coulomb_long ??
                    k = (SQR(ic[2]) + SQR(ic[1]) + SQR(ic[0])) / SQR(L);
                    fac = h3 * EPSILON0INV / M_PI / k;

                    dg_fft[index].re = q2 * fac * fft_data[index].re;
                    dg_fft[index].im = q2 * fac * fft_data[index].im;
                }
                index++;
            }

    /* FFT, fft_complex to Vec */
    ComputeVecfromFFT_fftw(da, BHD->fft_plan_bw, uc, dg_fft,
                           BHD->fft_scratch, x, n, 0);

    VecScale(uc, 1./L/L/L);
}

static void RecomputeInitialSoluteData_QM(BGY3dH2OData BHD, const Site S[], int nsites, real damp, real damp_LJ)
{
    PetscPrintf(PETSC_COMM_WORLD,"Recomputing solute(QM) data with damping factor %f (damp_LJ=%f)\n", damp, damp_LJ);

    /*
     * Calculate LJ potential for all solvent sites.
     *
     * Beta is  the (inverse) temperature. For  historical reasons the
     * solute  field acting on  solvent sites  is defined  having this
     * factor.
     */
    real factor = damp_LJ * BHD->PD->beta;
    assert (factor >= 0.0);

    /*
     * Fill LJ-interaction of  H and O sites with  the solute into the
     * respective arrays.
     *
     * FIXME: LJ-parameters,  (eH, sH) and (eO,  sO), for H  and O are
     * #defined at some obscure place:
     *
     * We  supply ljc()  as a  callback function  that is  supposed to
     * compute the interaction  of a charged LJ solvent  site with the
     * solute.
     *
     * At  this place  the (short  range) Coulomb  interaction  of the
     * solvent  site  with  the  solute was  deliberately  omitted  by
     * specifying zero charge of the solvent site:
     */
    field (BHD->da, BHD->PD, S, nsites, eH, sH, 0.0, factor, ljc, BHD->gH_ini);
    field (BHD->da, BHD->PD, S, nsites, eO, sO, 0.0, factor, ljc, BHD->gO_ini);

    /*
     * Compute  the  charge  density  of  the  solute.   The  callback
     * function rho()  sums charge  distribution for each  solute site
     * and  does not use  (epsilon, sigma,  charge) parameters  of the
     * solvent site,  so that we  provide -1.0 for them.   The overall
     * factor is 1.0 (idependent of the solvent charge):
     */

    Vec rho_solute; /* Vector for solute charge density */

    DACreateGlobalVector (BHD->da, &rho_solute);

    field (BHD->da, BHD->PD, S, nsites, -1.0, -1.0, -1.0, 1.0, rho, rho_solute);

    /*
     * This solves  the Poisson equation and  puts resulting potential
     * into a pre-allocated (?) vector BHD->v[0].
     */
    ComputeSoluteDatafromCoulomb_QM (BHD, BHD->v[0], rho_solute, 1.0 * damp);

    VecDestroy (rho_solute);

    VecSet (BHD->ucH, 0.0);
    VecAXPY (BHD->ucH, qH, BHD->v[0]);

    VecSet (BHD->ucO, 0.0);
    VecAXPY (BHD->ucO, qO, BHD->v[0]);
}

#if 0
/*
 * For debug purposes:
 */
static void dump (BGY3dH2OData BHD)
{
    PetscViewer viewer;

    /* print  to check */
    PetscPrintf(PETSC_COMM_WORLD, "Writing binarys \n");
    PetscViewerBinaryOpen(PETSC_COMM_WORLD, "LJH.bin", FILE_MODE_WRITE, &viewer);
    VecView(BHD->gH_ini, viewer);
    PetscViewerDestroy(viewer);
    PetscViewerBinaryOpen(PETSC_COMM_WORLD, "LJO.bin", FILE_MODE_WRITE, &viewer);
    VecView(BHD->gO_ini, viewer);
    PetscViewerDestroy(viewer);
    /* PetscViewerBinaryOpen(PETSC_COMM_WORLD, "gs.bin", FILE_MODE_WRITE, &viewer); */
    /* VecView(sumgs, viewer); */
    PetscViewerDestroy(viewer);
    PetscViewerBinaryOpen(PETSC_COMM_WORLD, "ucH.bin", FILE_MODE_WRITE, &viewer);
    VecView(BHD->ucH, viewer);
    PetscViewerDestroy(viewer);
    PetscViewerBinaryOpen(PETSC_COMM_WORLD, "ucO.bin", FILE_MODE_WRITE, &viewer);
    VecView(BHD->ucO, viewer);
    PetscViewerDestroy(viewer);
}
#endif

/*
 * Calculate a  real field "f"  for the solvent site  characterized by
 * (epsilon, sigma)  in the presence of  the solute S  with an overall
 * factor "fact" at every point (x, y, z) of the local grid.
 *
 * The function f(x, y, z, eps, sig,  chg, S) can be ljc() or rho() as
 * two examples.
 *
 * Vector "v" is the intent(out) argument.
 */
static void field (DA da, const ProblemData *PD,
                   const Site S[], int nsites,
                   real epsilon, real sigma, real charge, real fact,
                   real (*f)(real x, real y, real z,
                             real eps, real sig, real chg,
                             const Site S[], int nsites),
                   Vec v)
{
    PetscScalar ***vec;
    real h[3];
    int i0, j0, k0;
    int ni, nj, nk;

    /*
     * FIXME: do we really assume that intervals for x-, y- and z- are
     * the same? This  basically means the corner of  the unit cell is
     * at (offset, offset, offset):
     */
    real offset = PD->interval[0];

    FOR_DIM
        h[dim] = PD->h[dim];

    /* Get local portion of the grid */
    DAGetCorners (da, &i0, &j0, &k0, &ni, &nj, &nk);

    DAVecGetArray (da, v, &vec);

    /* loop over local portion of grid */
    for (int k = k0; k < k0 + nk; k++) {

        real z = k * h[2] + offset;

        for (int j = j0; j < j0 + nj; j++) {

            real y = j * h[1] + offset;

            for (int i = i0; i < i0 + ni; i++) {

                real x = i * h[0] + offset;

                /*
                 * Compute the field f at (x, y, z) <-> (i, j, k) e.g.
                 * by summing (LJ) contributions from all solute sites
                 * at that grid point:
                 */
                vec[k][j][i] = fact * f (x, y, z, epsilon, sigma, charge, S, nsites);
            }
        }
    }
    DAVecRestoreArray (da, v, &vec);
}

/*
 * Interaction of a charged LJ site (epsilon, sigma, charge) at (x, y,
 * z) with the solute S:
 */
static real ljc (real x, real y, real z,
                 real epsilon, real sigma, real charge,
                 const Site S[], int nsites)
{
    /* Sum force field contribution from all solute sites: */
    real field = 0.0;

    for (int site = 0; site < nsites; site++) {

        /* Interaction parameters for a pair of LJ sites: */
        real e2 = sqrt (epsilon * S[site].epsilon);
        real s2 = 0.5 * (sigma + S[site].sigma);

        /* Distance from a grid point to this site: */
        real r_s = sqrt (SQR(x - S[site].x[0]) +
                         SQR(y - S[site].x[1]) +
                         SQR(z - S[site].x[2]));

        /* 1. Lennard-Jones */
        field += Lennard_Jones (r_s, e2, s2);

        /* 2. Coulomb,  short range part.  For  historical reasons the
           overall scaling factor, the  product of solvent- and solute
           site charges, is handled by the function itself: */
        field += Coulomb_short (r_s, charge * S[site].charge);
    }

    return field;
}

/*
 * Charge  density  of  the solute  S  at  (x,  y, z).   Solvent  site
 * parameters (epsilon, sigma, charge)  are here to keep the interface
 * of rho() the same as that of ljc().
 *
 * Each gaussian is evaluated as:
 *
 *   rho(r) = q * [ G / sqrt(pi)]^3 * exp[-G^2 * (r - x0)^2]
 */
static real rho (real x, real y, real z,
                 real epsilon, real sigma, real charge, /* all three unused */
                 const Site S[], int nsites)
{
    /* G  is predefind  in bgy3d_SolventParameters.h  FIXME:  make the
       gaussian width a property of  the (solute) site in the same way
       as the charge of the site. */
    real prefac = pow(G / sqrt(M_PI), 3.0);

    /* Sum Gaussian contributions from all solute sites: */
    real field = 0.0;

    for (int site = 0; site < nsites; site++) {

        /* Square of the distance from a grid point to this site: */
        real r2 = (SQR(x - S[site].x[0]) +
                   SQR(y - S[site].x[1]) +
                   SQR(z - S[site].x[2]));

        /* Gaussian  distribution, note  that G  is not  a  width, but
           rather an inverse of it: */
        field += prefac * S[site].charge * exp(- G * G * r2);
    }

    return field;
}

/*
  Solve  Poisson  Equation  in  Fourier space  and  get  elestrostatic
  potential by inverse FFT.

  Vec uc is intent(out).
  Vec rho is intent(in).
  real q is the overall factor.

  Side effects:

  Appears to use BHD->g_fft and BHD->fft_scratch as working storage.
*/
void ComputeSoluteDatafromCoulomb_QM (BGY3dH2OData BHD, Vec uc, Vec rho, real q)
{
    int x[3], n[3], i[3], ic[3], N[3], index;
    real h[3], interval[2], k2, fac, L, h3;
    fftw_complex *fft_work;

    interval[0] = BHD->PD->interval[0];
    interval[1] = BHD->PD->interval[1];
    L = interval[1] - interval[0];
    FOR_DIM
        h[dim] = BHD->PD->h[dim];
    FOR_DIM
        N[dim] = BHD->PD->N[dim];
    h3 = h[0] * h[1] * h[2];

    /* FIXME: are we using this  as a scratch storage? Do we overwrite
       something important? */
    fft_work = BHD->g_fft;

    /* Get local portion of the grid */
    DAGetCorners(BHD->da, &(x[0]), &(x[1]), &(x[2]), &(n[0]), &(n[1]), &(n[2]));

    /* Get FFT of rho: rho(i, j, k) -> fft_rho(kx, ky, kz) placed into
       fft_work(kx, ky, kz): */
    ComputeFFTfromVec_fftw(BHD->da, BHD->fft_plan_fw, rho, fft_work, BHD->fft_scratch, x, n, 0);

    /*
      Solving Poisson Equation (SI units) with FFT and IFFT:

          - LAPLACIAN U (x, y, z) = (1 / epsilon0) rho(x, y, z)
                       c

      because of x = i h, y = j  h, and z = k h, with grid spacing h =
      L / n:

             2   2
          - n / L  LAPLACIAN uc(i, j, k) = (1 / epsilon0) rho(i, j, k)

      FFT (see FFTW manual "What FFTW Really Computes"):

                                    2          2    2
      fft_uc(kx, ky, kz) = 1 / [4 pi epsilon0 k  / L ] fft_rho(kx, ky, kz)

      with

           2    2    2    2
          k = kx + ky + kz

      IFFT (see FFTW manual "What FFTW Really Computes"):

      because: IFFT(fft_uc(kx, ky, kz)) = n^3 * uc(i, j, k)

                     3   3
      uc(i, j, k) = h / L  * IFFT(fft_uc(kx, ky, kz))
    */

    // EPSILON0INV = 1 / 4 * pi * epsilon0:
    real scale = q * EPSILON0INV / M_PI * h3 / (L * L * L);

    index = 0;
    for (i[2] = x[2]; i[2] < x[2] + n[2]; i[2]++)
        for (i[1] = x[1]; i[1] < x[1] + n[1]; i[1]++)
            for (i[0] = x[0]; i[0] < x[0] + n[0]; i[0]++) {

                FOR_DIM {
                    if( i[dim] <= N[dim] / 2)
                        ic[dim] = i[dim];
                    else
                        ic[dim] = i[dim] - N[dim];
                }

                if (ic[0] == 0 && ic[1] == 0 && ic[2] == 0) {
                    /* No point to scale zeros, obviousely: */
                    fft_work[index].re = 0;
                    fft_work[index].im = 0;
                }
                else {
                    k2 = (SQR(ic[2]) + SQR(ic[1]) + SQR(ic[0])) / SQR(L);

                    fac = scale / k2;

                    /* Here  we compute  in place:  uc(kx, ky,  kz) :=
                       scale * rho(kx, ky, kz) / k^2 */
                    fft_work[index].re = fac * fft_work[index].re;
                    fft_work[index].im = fac * fft_work[index].im;
                }
                index++;
            }
    // NOT NEEDED: VecSet(uc, 00.0);

    /* uc := IFFT(uc(kx, ky, kz)) */
    ComputeVecfromFFT_fftw(BHD->da, BHD->fft_plan_bw, uc, fft_work, BHD->fft_scratch, x, n, 0);
}
