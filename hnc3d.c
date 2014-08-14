/* -*- mode: c; c-basic-offset: 2; -*- vim: set sw=2 tw=70 et sta ai: */
/*
  Copyright (c) 2007 Lukas Jager
  Copyright (c) 2013, 2014 Alexei Matveev
  Copyright (c) 2013 Bo Li
*/

/*
  For simple liquids the matrix OZ equation reads

    h = c * [1 + ρ h]

  where the expression in the  square brackets is susceptibility χ = 1
  +  ρh of  the mixture.   The matrix  ρ is  diagonal.  Only  when the
  density of all sites is the same the equation simplifies to the more
  recognizable form

    h = c + ρ c * h.

  However, consider a solute/solvent  mixture in the limit of infinite
  dilution where the  density of the solute is  vanishingly small. The
  corresponding blocks of the matrix equation read:

    h   = c   [1 + ρ  h  ] + c   ρ  h                              (1)
     vv    vv       v  vv     vu  u  uv

  The second  term in  Eq. (1)  vanishes and the  OZ equation  for the
  solvent   structure  becomes   independent  of   the   solute.   The
  solute-solute  correlations are,  of course,  affected by  the dense
  medium even in the infinite dilution limit:

    h   = c   [1 + ρ  h  ] + c   ρ  h                              (2)
     uu    uu       u  uu     uv  v  vu

  Now the remaining two equations

    h   = c   [1 + ρ  h  ] + c   ρ  h                              (3)
     uv    uv       v  vv     uu  u  uv

  and

    h   = c   [1 + ρ  h  ] + c   ρ  h                              (4)
     vu    vu       u  uu     vv  v  vu

  though necessarily  redundant seem to differ. By  removing the terms
  proportional  to  the solute  density  one  gets  two different  but
  equivalent relations:

    h   = c   + c   ρ  h                                           (5)
     uv    uv    uv  v  vv

  and

    h   = c   + c   ρ  h                                           (6)
     vu    vu    vv  v  vu

  For  practical application  these two  equations  may be  used as  a
  relation between the  solute-solvent indirect correlation t =  h - c
  and a another solute-solvent property as a complement to the closure
  relation.  Both equation use the solvent structure as a parameter:

    t   = c   ρ  h                                                 (7)
     uv    uv  v  vv

  or

    t   = c   ρ  h                                                 (8)
     vu    vv  v  vu

  In  the first  case the  structure of  the pure  solvent  (or rather
  infinitely  diluted mixture) is  represented by  the solvent-solvent
  total  correlation  h,  whereas  in  the  second  case  the  solvent
  structure is  represented by the  solvent-solvent direct correlation
  c. The second  of these two forms, Eq.  (8), was originally proposed
  for  use  in 3d  HNC  equations  [1].  However other  (more  recent)
  literature  appears  to prefer  to  start  with  a formulation  that
  resembles more  Eq.  (7) e.g.  Ref. [2].   This alternative approach
  assumes that the structure of the pure solvent is represented by the
  solvent  susceptibility χ  that  mediates the  relation between  the
  total and direct solute-solvent correlations:

    h   = c   χ                                                    (9)
     uv    uv  vv

  with

    χ   = 1 + ρ  h                                                 (10)
     uv        v  vv

  which is  equivalent to Eq. (7). Note  that χ, as it  stands, is not
  symmetric, unless ρ is the same for all sites. FIXME: the code makes
  use of this assumption!

  The  corresponding equation  for radial  site-site  distributions in
  molecular 1d RISM equation in the infinite dilution limit reads

    h   =  ω  * c   * [ω + ρ  h  ]                               (11a)
     uv     u    uv     v   v  vv

  whereas the generalization to the 3d RISM is missing the convolution
  with the solute intra-molecular correlation:

    h   =  c   * [ω + ρ  h  ]                                    (11b)
     uv     uv     v   v  vv

  Here  again the  term  is square  brackets  is the  property of  the
  molecular solvent fixed by  the assumption of the infinite dilution,
  and is a generalization  of the solvent susceptibility for molecular
  solvents:

    χ   =  ω  + ρ  h                                              (12)
     vv     v    v  vv

  With this definition, the expression for the indirect solute-solvent
  correlation

    t   = h   - c   = c   (χ   - 1)                               (13)
     uv    uv    uv    uv   vv

  does  not simplify  to  Eq. (7)  directly  though still  has a  very
  similar structure. Again,  only if ρ is a scalar  one can assume the
  solvent susceptibility χ is symmetric in site indices.

  [1] Numerical solution of the hypernetted chain equation for a
      solute of arbitrary geometry in three dimensions, Dmitrii Beglov
      and Benoît Roux , J.  Chem.  Phys.  103, 360 (1995);
      http://dx.doi.org/10.1063/1.469602

  [2] Three-Dimensional Molecular Theory of Solvation Coupled with
      Molecular Dynamics in Amber, Tyler Luchko, Sergey Gusarov,
      Daniel R. Roe, Carlos Simmerling, David A. Case , Jack Tuszynski
      and Andriy Kovalenko, J. Chem. Theory Comput., 2010, 6 (3), pp
      607–624 http://dx.doi.org/10.1021/ct900460m
*/

#include "bgy3d.h"
#include "bgy3d-getopt.h"
#include "bgy3d-fftw.h"         /* bgy3d_fft_mat_create() */
#include "bgy3d-vec.h"          /* vec_create() */
#include "bgy3d-solutes.h"     /* struct Site, bgy3d_solute_field() */
#include "bgy3d-force.h"        /* bgy3d_pair_potential() */
#include "bgy3d-pure.h"         /* bgy3d_omega_fft_create() */
#include "bgy3d-snes.h"         /* bgy3d_snes_default() */
#include "hnc3d-sles.h"         /* hnc3d_sles_zgesv() */
#include "rism.h"               /* rism_solvent() */
#include "bgy3d-potential.h"    /* info() */
#include "bgy3d-impure.h"       /* Restart */
#include "bgy3d-solvents.h"     /* bgy3d_sites_show() */
#include <math.h>               /* expm1() */
#include "hnc3d.h"


/* Only  in  the  case of  neutral  solutes  the  inverse FFT  of  the
   long-range Coulomb gives something reasonable: */
static const bool neutral_solutes = false;


static void
compute_c (ClosureEnum closure, real beta, Vec v, Vec t, Vec c)
{
  /* No aliasing, we call Fortran here: */
  assert (c != t);
  assert (c != v);

  /* Callback for vec_app3(): */
  void f (int n, real v[n], real t[n], real c[n])
  {
    /* See Fortran implementation  in closures.f90.  NOTE: no aliasing
       here, please! */
    rism_closure (closure, beta, n, v, t, c);
  }
  vec_app3 (f, v, t, c);
}


static void
compute_c1 (ClosureEnum closure, real beta, Vec v, Vec t, Vec dt, Vec dc)
{
  void f (int n, real v[n], real t[n], real dt[n], real dc[n])
  {
    rism_closure1 (closure, beta, n, v, t, dt, dc);
  }
  vec_app4 (f, v, t, dt, dc);
}


static int
delta (int i, int j)
{
  return (i == j) ? 1 : 0;
}


/*
  Use the k-representation of Ornstein-Zernike (OZ) equation

    h = c + ρ c * h

  to compute γ =  h - c form c:

                 -1                -1   2
    γ =  (1 - ρc)   c - c = (1 - ρc)  ρc

  If you scale  c by h3 beforehand or  pass rho' = rho *  h3 and scale
  the  result by h3  in addition,  you will  compute exactly  what the
  older version of the function did:
*/
static void
compute_t2_1 (real rho, Vec c_fft, Vec t_fft)
{
  complex pure f (complex c)
  {
    /* return c / (1.0 - rho * c) - c; */
    return rho * (c * c) / (1.0 - rho * c);
  }
  vec_fft_map1 (t_fft, f, c_fft);
}


/* So far rho is scalar, it could be different for all sites: */
static void
compute_t2_m (int m, real rho, Vec c_fft[m][m], Vec w_fft[m][m], Vec t_fft[m][m])
{
  if (m == 0) return;           /* see ref to c_fft[0][0] */

  local complex *c_fft_[m][m], *w_fft_[m][m], *t_fft_[m][m];

  /* Here ij  and ji are aliased.   We ask to put  real* into complex*
     slots: */
  vec_get_array2 (m, c_fft, (void*) c_fft_);
  vec_get_array2 (m, t_fft, (void*) t_fft_);

  /* Diagonals are NULL, vec_get_array() passes them through: */
  vec_get_array2 (m, w_fft, (void*) w_fft_);

  const int n = vec_local_size (c_fft[0][0]);
  assert (n % 2 == 0);

  {
    complex H[m][m], C[m][m], W[m][m], WC[m][m], T[m][m];

    for (int k = 0; k < n / 2; k++)
      {
        /* for j <= i only: */
        for (int i = 0; i < m; i++)
          for (int j = 0; j <= i; j++)
            {
              /*
                Extract C  and W for  this particular momentum  k from
                scattered arrays into contiguous matrices.
              */
              C[i][j] = C[j][i] = c_fft_[i][j][k];

              /* Diagonal is implicitly 1: */
              W[i][j] = W[j][i] = (i == j) ? 1.0 : w_fft_[i][j][k];
            }

        /* WC,  an  intermediate.  See  comment  on  layout of  result
           below.  The input is symmetric, though: */
        hnc3d_sles_zgemm (m, W, C, WC);

        /* T :=  1 - ρWC.  The  matrix T is  used here as a  free work
           array: */
        for (int i = 0; i < m; i++)
          for (int j = 0; j < m; j++)
            T[i][j] = delta (i, j) - rho * WC[i][j];

        /*
          H := WCW.  Temporarily ---  it will be overwritten with the
          real H  after solving the  linear equations.

          Note that  the matrix multiplication is  performed using the
          Fortran  (column major) interpetation  of the  matrix memory
          layout. In Fortran notation:

            H(i, j) = Σ  WC(i, k) * W(k, j)
                       k

          or, in C-notation:

            H[j][i] = Σ  WC[k][i] * W[j][k]
                       k
        */
        hnc3d_sles_zgemm (m, WC, W, H);

        /*
          Solving the linear equation makes H have the literal meaning
          of the total correlation matrix (input T is destroyed):

                -1                -1
          H := T   * H == (1 - ρc)   * c
        */
        hnc3d_sles_zgesv (m, T, H);


        /*
          The  same  effect  is  achieved  in  1x1  version  of  the  code
          differently:

          T := H - C
        */
        for (int i = 0; i < m; i++)
          for (int j = 0; j <= i; j++)
            t_fft_[i][j][k] = H[i][j] - C[i][j];
      }
  }

  /* Here vec_restore_array2() expects array  of real*, we offer array
     of complex* instead: */
  vec_restore_array2 (m, c_fft, (void*) c_fft_);
  vec_restore_array2 (m, t_fft, (void*) t_fft_);

  /* The case with NULL on the diagonal is handled gracefully: */
  vec_restore_array2 (m, w_fft, (void*) w_fft_);
}


static void
compute_t2 (int m, real rho, Vec c_fft[m][m], Vec w_fft[m][m], Vec t_fft[m][m])
{
  if (m == 1)
    /* Here w = 1, identically: */
    compute_t2_1 (rho, c_fft[0][0], t_fft[0][0]); /* faster */
  else
    compute_t2_m (m, rho, c_fft, w_fft, t_fft); /* works for any m */
}


/*
  There  were  historically  two  types  of HNC  iterations  for  pure
  solvent:

  a) HNC iteration for an indirect correlation t = h - c

     t    ->  dt = t    - t
      in            out    in

     where other  intermediates are considered a function  of that. In
     particular  in this case  another important  intermediate is  y =
     c(t).

  b) HNC iteration for a direct correlation where the total correlation
     is considered a function of that:

     c    ->  dc = c    - c
      in            out    in

     In this case the indirect  correlation γ is considered a function
     of c and is stored in y = t(c).

  The case (a)  with indirect correlation t as  a primary variable won
  over time. Maintaining two  cases appeared infeasible at some point.
*/
typedef struct Ctx2
{
  State *HD;
  int m;
  Vec *v_short;       /* [m][m], in, real, center */
  Vec *v_long_fft;    /* [m][m], in, complex, center */
  Vec *y;             /* [m][m], work, real, y = c(t), not t(c) */
  Vec *t_fft, *c_fft; /* [m][m], work, complex */
  Vec *w_fft;         /* [m][m], in, complex, corner, NULL diagonal */
} Ctx2;


static void
iterate_t2 (Ctx2 *ctx, Vec T, Vec dT)
{
  const int m = ctx->m;

  /* aliases of the correct [m][m] shape: */
  Vec (*c_fft)[m] = (void*) ctx->c_fft;
  Vec (*t_fft)[m] = (void*) ctx->t_fft;
  Vec (*w_fft)[m] = (void*) ctx->w_fft; /* corner */
  Vec (*c)[m] = (void*) ctx->y;         /* y = c(t) here */
  Vec (*v_short)[m] = (void*) ctx->v_short;
  Vec (*v_long_fft)[m] = (void*) ctx->v_long_fft;

  const State *HD = ctx->HD;
  const ProblemData *PD = HD->PD;
  const real rho = PD->rho;
  const real beta = PD->beta;
  const real L3 = volume (PD);
  const real h3 = volume_element (PD);

  /* Establish aliases to the subsections of the long Vec T and dT: */
  local Vec t[m][m], dt[m][m];
  vec_aliases_create2 (T, m, t);
  vec_aliases_create2 (dT, m, dt);

  for (int i = 0; i < m; i++)
    for (int j = 0; j <= i; j++)
      {
        compute_c (PD->closure, beta, v_short[i][j], t[i][j], c[i][j]);

        MatMult (HD->fft_mat, c[i][j], c_fft[i][j]);

        VecScale (c_fft[i][j], h3);

        /*
          The real-space  representation encodes only  the short-range
          part  of  the  direct  corrlation. The  (fixed)  long  range
          contribution is added here:

            C := C  - βV
                  S     L
        */
        VecAXPY (c_fft[i][j], -beta, v_long_fft[i][j]);

        /* Translate distribution to the grid corner. */
        bgy3d_vec_fft_trans (HD->dc, PD->N, c_fft[i][j]);
      }

  /* Solves the OZ linear equation for t_fft[][].: */
  compute_t2 (m, rho, c_fft, w_fft, t_fft);

  for (int i = 0; i < m; i++)
    for (int j = 0; j <= i; j++)
      {
        /* Translate distribution to the grid center. */
        bgy3d_vec_fft_trans (HD->dc, PD->N, t_fft[i][j]);

        /*
          Since we plugged in the Fourier transform of the full direct
          correlation  including  the  long  range part  into  the  OZ
          equation what  we get out  is the full  indirect correlation
          including the  long-range part.   The menmonic is  C +  T is
          short range.  Take it out:

            T := T - βV
             S         L
        */
        VecAXPY (t_fft[i][j], -beta, v_long_fft[i][j]);

        MatMultTranspose (HD->fft_mat, t_fft[i][j], dt[i][j]);

        VecScale (dt[i][j], 1.0/L3);
      }

  /*
    This  destroys the  aliases,  but  does not  free  the memory,  of
    course. The actuall data is owned by Vec T and Vec dT. From now on
    one may access T and dT directly again.
  */
  vec_aliases_destroy2 (T, m, t);
  vec_aliases_destroy2 (dT, m, dt);

  VecAXPY (dT, -1.0, T);
}


/*
         2
    μ = h / 2 - c  - h * (c + c ) / 2
                 S         S   L

  This is  a subexpression in  the summation over all  site-site pairs
  where it is assumed that the long-range contribution in

    - Σ   c
       uv  uv

  cancels out. This is the case when

    c      = -βQ q v
     L,uv       u v L

  and either  solute charges Q or  the solvent charges q  sum to zero.
  Naturally, with  an exact  arithmetics one does  not need  to handle
  short-  and long-range  correlations  separately in  this case.  For
  PSE-n closures  the "renormalized indirect  correlation" x = βv  + t
  appears in the expression of the chemical potential too.

  The  h² term contributes  conditionally. Eventually,  only depletion
  regions (h  < 0) contribute  (KH). See Fortran sources  for details.
*/
static void
compute_mu (ClosureEnum method, Vec x, Vec h, Vec cs, Vec cl, /* in */
            Vec mu)             /* out */
{
  void f (int n, real x[n], real h[n], real cs[n], real cl[n], real mu[n])
  {
    rism_chempot_density (method, n, x, h, cs, cl, mu);
  }
  vec_app5 (f, x, h, cs, cl, mu);
}


static void
compute_mu1 (ClosureEnum method,
             Vec x, Vec dx,
             Vec h, Vec dh,
             Vec c, Vec dc,
             Vec cl,            /* in */
             Vec dm)            /* out */
{
  void f (int n,
          real x[n], real dx[n],
          real h[n], real dh[n],
          real c[n], real dc[n],
          real cl[n], real dm[n])
  {
    rism_chempot_density1 (method, n, x, dx, h, dh, c, dc, cl, dm);
  }
  vec_app8 (f, x, dx, h, dh, c, dc, cl, dm);
}


/*
  Returns the  β-scaled density of the chemical  potential, βμ(r).  To
  get the excess  chemical potential integrate it over  the volume and
  divide by β, cf.:

    βμ = ρ ∫ [½h²(r) - c(r) - ½h(r)c(r)] d³r

  Here  we  pass  h(r)  and  c(r)  and long-range  part  of  c(r)  for
  solute-solvent pair.   The solute might  be the same as  solvent, of
  course.   PSE-n closures  need another  quantity,  the "renormalized
  indirect correlation" x  = -βv + t (referred to  at other plasces as
  t* sometimes).

  Volume integral in cartesian grid is actually:

    Vol(D) = ∫∫∫dxdydz
              D

  The shape of arrays passed here may be arbitrary, though in practice
  it is either m x m or 1 x m:
*/
static void
chempot_density (ClosureEnum method, int n, int m,
                 Vec x[n][m],   /* in */
                 Vec h[n][m],   /* in */
                 Vec cs[n][m],  /* in */
                 Vec cl[n][m],  /* in, long range */
                 Vec mu)        /* out */
{
  /* increment for all solvent sites */
  local Vec dmu = vec_duplicate (mu);

  /* Clear accumulator: */
  VecSet (mu, 0.0);

  for (int i = 0; i < n; i++)
    for (int j = 0; j < m; j++)
      {
        compute_mu (method, x[i][j], h[i][j], cs[i][j], cl[i][j], dmu);

        VecAXPY (mu, 1.0, dmu);
      }

  vec_destroy (&dmu);
}


static void
chempot_density1 (ClosureEnum method, int n, int m,
                  Vec x[n][m], Vec dx[n][m], /* in */
                  Vec h[n][m], Vec dh[n][m], /* in */
                  Vec c[n][m], Vec dc[n][m], /* in */
                  Vec cl[n][m],              /* in, long range */
                  Vec dm)                    /* out */
{
  /* Increment for all solvent sites */
  local Vec dm1 = vec_duplicate (dm);

  /* Clear accumulator: */
  VecSet (dm, 0.0);

  for (int i = 0; i < n; i++)
    for (int j = 0; j < m; j++)
      {
        compute_mu1 (method,
                     x[i][j], dx[i][j],
                     h[i][j], dh[i][j],
                     c[i][j], dc[i][j],
                     cl[i][j], dm1);

        VecAXPY (dm, 1.0, dm1);
      }

  vec_destroy (&dm1);
}


/*
  Interface to get chemical potential of solvent-solvent pair from Vec
  x = βv + t, h, c, and cl, return the value of chemical potential.

  The   argument   "closure"   choses   between   HNC,   KH   and   GF
  functionals. The State  struct also holds a setting  for the closure
  --- that one is  ignored to allow computing any  kind of functional.
*/
static real
chempot (const State *HD, ClosureEnum method, int n, int m,
         Vec x[n][m], Vec h[n][m], Vec c[n][m], Vec cl[n][m]) /* in */
{
  const ProblemData *PD = HD->PD;
  const real beta = PD->beta;
  const real h3 = volume_element (PD);

  /* Vector for chemical potential density */
  local Vec mu_dens = vec_create (HD->da);

  /* Get β-scaled chemical potential density */
  chempot_density (method, n, m, x, h, c, cl, mu_dens);

  /* Volume integral scaled by a factor: */
  const real mu = PD->rho * vec_sum (mu_dens) * h3 / beta;

  vec_destroy (&mu_dens);

  return mu;
}


static real
chempot1 (const State *HD, ClosureEnum method, int n, int m,
          Vec x[n][m], Vec dx[n][m],
          Vec h[n][m], Vec dh[n][m],
          Vec c[n][m], Vec dc[n][m],
          Vec cl[n][m]) /* in */
{
  const ProblemData *PD = HD->PD;
  const real beta = PD->beta;
  const real h3 = volume_element (PD);

  /* Vector for chemical potential density */
  local Vec mu_dens = vec_create (HD->da);

  /* Get β-scaled chemical potential density */
  chempot_density1 (method, n, m, x, dx, h, dh, c, dc, cl, mu_dens);

  /* Volume integral scaled by a factor: */
  const real mu = PD->rho * vec_sum (mu_dens) * h3 / beta;

  vec_destroy (&mu_dens);

  return mu;
}


/*
  Prints chemical  potentials on  tty.  The default  is marked  with a
  star.

  FIXME: the idea  to evaluate all functionals from  the same input is
  not as good as may seem on  the first sight. Note that there is more
  than one  way to do that. Currently  one evaluates h and  c from the
  solution t according  to the native (SCF) closure  and uses the form
  of the chemical potential functional expressed via those x, h, and c
  that corresponds  to another closure. A different  result would have
  been obtained if one evaluated h and c using that second closure. It
  is  not clear  which  of the  multiple  ways is  more consistent  or
  otherwise preferred.  Basically the  question boils down to what one
  should consider  final output  of the SCF  procedure to be  used for
  post-SCF application of the functionals.
*/
static void
print_chempot (const State *HD, int n, int m,
               Vec x[n][m], Vec h[n][m], Vec c[n][m], Vec cl[n][m]) /* in */
{
  /* FIXME:  as  implemented, for  method  ==  PY  the default  energy
     functional is GF: */
  const ClosureEnum methods[3] = {CLOSURE_HNC, CLOSURE_KH, CLOSURE_PY};
  const char *names[3] = {"HNC", "KH", "GF"};
  real mu[3];

  /* Silent computing: */
  for (int i = 0; i < 3; i++)
    mu[i] = chempot (HD, methods[i], n, m, x, h, c, cl);

  /* Printing only: */
  PRINTF (" # Chemical potentials, default is marked with *:\n");
  for (int i = 0; i < 3; i++)
    PRINTF (" # mu = %f kcal (%s)%s\n", mu[i], names[i],
                 ((methods[i] == HD->PD->closure)? "*" : ""));
}


/*
  Solving for indirect correlation t = h - c and thus, also for direct
  correlation c  and other quantities  of HNC equation.   The indirect
  correlation  t  appears  as  a  primary  variable  here.  All  other
  unknowns, including the direction  correlation c, are functionals of
  that.

  Historically  this  code supported  another  mode  where the  direct
  correlation  c served  as  a  primary variable.   In  that case  the
  indirect correlation t was a functional of that.

  This 3D code operates  with essentially 1D quantities represented on
  3D grids (modulo finite grid artifacts). It competes with the proper
  1D variant in rism.f90. The 1D  code offers DRISM which this 3D code
  does not support yet. See how  we generate initial guess with the 1D
  code here.
*/
void
hnc3d_solvent_solve (const ProblemData *PD,
                     int m, const Site solvent[m],
                     Vec g[m][m])
{
  /* Code used to be verbose: */
  bgy3d_problem_data_print (PD);

  State *HD = bgy3d_state_make (PD); /* FIXME: rm unused fields */

  PRINTF ("(iterations for γ)\n");

  /*
    For primary variable t there  will be two exclusive ways to access
    the data:  via the  long Vec  T or  m * (m  + 1)  / 2  shorter Vec
    t[m][m] aliased to the subsections of the longer one.
  */
  local Vec T = vec_pack_create2 (HD->da, m); /* long Vec */

  /* Generate initial guess using much faster 1D code: */
  {
    /*
      Problem data for use in 1d-RISM code. If you do not upscale, the
      rmax = max (PD->L) / 2 will be too low for interpolation:
    */
    ProblemData pd = rism_upscale (PD);

    const int nrad = rism_nrad (&pd);
    const real rmax = rism_rmax (&pd);

    real t_rad[m][m][nrad];

    /* 1d-RISM calculation.  Dont  need neither susceptibility nor the
       result dictionary, need only t(r): */
    rism_solvent (&pd, m, solvent, t_rad, NULL, NULL);

    {
      local Vec t[m][m];
      vec_aliases_create2 (T, m, t); /* aliases to subsections */

      const real dr = rmax / nrad;

      for (int i = 0; i < m; i++)
        for (int j = 0; j <= i; j++)
          vec_rtab (HD, nrad, t_rad[i][j], dr, t[i][j]);

      vec_aliases_destroy2 (T, m, t);
    }
  }

  /*
    Most of these  Vecs will be a functional of  primary variable t or
    constant.  Earlier  versions supported  direct correlation c  as a
    primary variable.
  */
  local Vec c[m][m];
  vec_create2 (HD->da, m, c);

  /* Prepare intra-molecular correlations. The origin is at the corner
     as suitable for convolutions. Diagonal will be NULL: */
  local Vec w_fft[m][m];
  bgy3d_omega_fft_create (HD, m, solvent, w_fft); /* creates them */

  /* Solvent-solvent interaction  is a  sum of two  terms, short-range
     and long-range: */
  local Vec v_short[m][m];      /* real */
  vec_create2 (HD->da, m, v_short);

  local Vec v_long_fft[m][m];   /* complex */
  vec_create2 (HD->dc, m, v_long_fft);

  /* Get solvent-solvent site-site interactions: */
  for (int i = 0; i < m; i++)
    for (int j = 0; j <= i; j++)
      bgy3d_pair_potential (HD, solvent[i], solvent[j],
                            v_short[i][j], v_long_fft[i][j]);

  {
    local Vec t_fft[m][m];
    vec_create2 (HD->dc, m, t_fft); /* complex */

    local Vec c_fft[m][m];
    vec_create2 (HD->dc, m, c_fft); /* complex */

    /*
      Find a T such that dT as returned by iterate_t2 (&ctx, T, dT) is
      zero.   Cast is there  to silence  the mismatch  in the  type of
      first pointer argument: struct Ctx2* vs. void*:
    */
    {
      Ctx2 ctx =
        {
          .HD = HD,
          .m = m,
          .v_short = (void*) v_short,       /* in */
          .v_long_fft = (void*) v_long_fft, /* in */
          .y = (void*) c,                   /* work, c(t)*/
          .t_fft = (void*) t_fft,           /* work, fft(t) */
          .c_fft = (void*) c_fft,           /* work, fft(c(t)) */
          .w_fft = (void*) w_fft,           /* in */
        };

      /* FIXME: no Jacobian yet! */
      bgy3d_snes_default (PD, &ctx, (VecFunc1) iterate_t2, NULL, T);
    }

    /* Free local stuff */
    vec_destroy2 (m, t_fft);
    vec_destroy2 (m, c_fft);
  }
  /*
    The approach with the primary variable  x == t won over time.  The
    direct correlation c(t) is  a dependent quantity! FIXME: we assume
    that the  value of c on  exit from the SNES  solver corresponds to
    the final t. If not, recompute it with compute_c() again.
  */

  /* Now  that T  has  converged  we will  post-process  it using  the
     aliases t[][]: */
  local Vec t[m][m];
  vec_aliases_create2 (T, m, t); /* aliases to subsections */

  Vec h[m][m];                  /* FIXME: not deallocated! */
  vec_create2 (HD->da, m, h);

  /* Compute h = c + t: */
  for (int i = 0; i < m; i++)
    for (int j = 0; j <= i; j++)
      VecWAXPY (h[i][j], 1.0, c[i][j], t[i][j]);

  /* Chemical potential */
  {
    const real beta = HD->PD->beta;
    const real L3 = volume (PD);

    /*
      NOTE: this is  the only place where one  needs real-space rep of
      the  long-range  Coulomb.   So   far  it  is  computed  by  FFT.
      Alternative is to tablulate it  on the real-space grid using the
      analytic expression. Surprisingly, for a couple of tests we made
      (LJC, TIP3P)  the difference between the  two approaches appears
      small.

      FIXME: For  the essentially 3D potentials  in the solute/solvent
      code  we already  have  the option  to  get the  real space  rep
      directly. Should we also do it here for consistency?

      FIXME: also  all of v_long_fft[][]  differ only by  factors, see
      how we deal with that to save space in solute/solvent code.
    */
    local Vec cl[m][m];        /* real-space long-range correlation */
    vec_create2 (HD->da, m, cl);

    /* Renormalized  indirect  correlation x  =  -βv  +  t appears  in
       expression for chemical potentials with PSE-n closures :*/
    local Vec x[m][m];
    vec_create2 (HD->da, m, x);

    for (int i = 0; i < m; i++)
      for (int j = 0; j <= i; j++)
        {
          /* Get real representation of long-range Coulomb potential */
          MatMultTranspose (HD->fft_mat, v_long_fft[i][j], cl[i][j]);

          /*
            Scale  Vec cl  to  get long-range  correlation (division  by
            volume is part of the inverse FFT):

              c  = -βv
               L      L
          */
          VecScale (cl[i][j], -beta/L3);

          /* Renormalized indirect correlation: x = -βv + t:  */
          VecWAXPY (x[i][j], -beta, v_short[i][j], t[i][j]);
        }

    /* The function chempot() operates  on rectangular arrays, we pass
       an m x m square ones: */
    print_chempot (HD, m, m, x, h, c, cl);

    vec_destroy2 (m, cl);
    vec_destroy2 (m, x);
  }

  /* No more used: */
  vec_aliases_destroy2 (T, m, t);
  vec_pack_destroy2 (&T);
  vec_destroy2 (m, c);
  vec_destroy2 (m, v_short);
  vec_destroy2 (m, v_long_fft);

  /*
    Compute  the  solvent susceptibility,  χ  =  ω  + ρh,  in  Fourier
    representation for  future use in  solute/solvent calculations. It
    appears to be more  convenient to operate with δχ = χ  - 1 so this
    is what is actually saved to disk.
  */
  {
    local Vec chi[m][m];
    vec_create2 (HD->da, m, chi);

    local Vec chi_fft[m][m];
    vec_create2 (HD->dc, m, chi_fft);

    const real dV = volume_element (PD);

    for (int i = 0; i < m; i++)
      for (int j = 0; j <= i; j++)
        {
          /*
              δχ = χ -  1 = (ω - 1) + ρh.

            The first ω-term is  only well representable on the k-grid
            and will be added later:
          */
          VecSet (chi[i][j], 0.0);
          VecAXPY (chi[i][j], PD->rho, h[i][j]);

          /* δχ(k) = FFT(δχ(r)) */
          MatMult (HD->fft_mat, chi[i][j], chi_fft[i][j]);
          VecScale (chi_fft[i][j], dV);

          /* Translate the  distribution to the grid  corner.  This is
             what one expects in convolution integrals: */
          bgy3d_vec_fft_trans (HD->dc, HD->PD->N, chi_fft[i][j]);

          /*
            Intra-molecular correlation  ω(k) is centered  at the grid
            corner, so add this only after translating chi_fft[][]:
          */
          if (w_fft[i][j])
            VecAXPY (chi_fft[i][j], 1.0, w_fft[i][j]);
          else
            /* ω - 1 == 0 identically, nothing to do! */
            assert (i == j);
        }

    /* The Fourier  rep is what is actually  read in solvent_kernel(),
       see below: */
    bgy3d_vec_save2 ("x%d%d-fft.bin", m, chi_fft);

    vec_destroy2 (m, chi);
    vec_destroy2 (m, chi_fft);
  }

  /* no more used: */
  for (int i = 0; i < m; i++)
    for (int j = 0; j < i; j++)   /* sic! */
      vec_destroy (&w_fft[i][j]); /* Diagonal is NULL! */

  /* Delegated to the caller: vec_destroy (&h); */

  bgy3d_state_destroy (HD);

  /* g = 1 + h, store in Vec h for output: */
  for (int i = 0; i < m; i++)
    for (int j = 0; j <= i; j++)
      VecShift (h[i][j], 1.0);  /* FIXME: misnomer! */

  /* Dont forget to vec_destroy2() it! */
  for (int i = 0; i < m; i++)
    for (int j = 0; j <= i; j++)
      g[i][j] = g[j][i] = h[i][j]; /* FIXME: misnomer! */

  bgy3d_vec_save2 ("g%d%d.bin", m, g);
}


/*
  In k-space compute the convolution star

    y = A * x

  which is currently applied to compute

    t   = (χ   - 1) * c
     vu     vv         vu

  or, in earlier versions, also

    t   = ρ c   *  h
     vu      vv     vu

  Compare to Eqs.   (7) and (8) in the  header comments, respectively.
  Given that the solute index  "u" is redundant, both expressions have
  the structure of the matrix-vector product of a (fixed) solvent pair
  quantitiy  and a  (variable) "vector"  of site  distributions around
  solute    impurity    to    give    another   "vector"    of    site
  distributions.

  The names of  the local variables correspond neither  to Eq. (7) nor
  to Eq.  (8).  Since the convention is chosen so that the convolution
  theorem is factorless there will be no overall factor.

  FIXME: (comments  outdated) Note that  the solvent-solvent site-site
  correlation c  is eventually long-range.  In Fourier  rep that would
  mean  c(k)  is  singular at  k  =  0.   Here  there are  no  special
  precautions  to treat the  assymptotic interactions  of the  (so far
  neutral) solute  species with the charged solvent  sites.  Note that
  in  3d  solute/solvent  case   we  do  not  operate  with  site-site
  distributions/potentials,    but    rather    with   the    "solvent
  site"-"compound solute" quantities. If the physics works as expected
  the assymptotic decay of such potentials and distributions is "fast"
  for neutral solutes.  FIXME: this  is not true anymore if the solute
  is charged.
*/
static void
star (int m, Vec a_fft[m][m], Vec x_fft[m], Vec y_fft[m])
{
  /*
    FMA stays for "fused multiply-add".  This is an elementary step of
    the matrix multiplication is

      y  += A  * x
       i     ij   j
  */
  complex pure fma (complex y, complex a, complex x)
  {
    return y + a * x;
  }

  /* For each solvent site ... */
  for (int i = 0; i < m; i++)
    {
      /* ... sum over solvent sites: */
      VecSet (y_fft[i], 0.0);
      for (int j = 0; j < m; j++)
        vec_fft_map3 (y_fft[i], /* argument aliasing! */
                      fma, y_fft[i], a_fft[i][j], x_fft[j]);
    }
}


/*
  HNC3d   iteration   for  a   fixed   direct   correlation  of   pure
  solvent. There were two cases at some point:

  a) Iteration with the indirect correlation t as a primary variable

     t    ->  dt = t    - t
      in            out    in

  b)  Iteration  with   an  (almost  discontinous)  total  correlation
     function h as a primary variable

     h    ->  dh = h    - h
      in            out    in

  At some point  it appeared impractical to maintain  two branches, so
  that the case (a) with  indirect correlation t as a primary variable
  won.
*/
typedef struct Ctx1
{
  State *HD;
  int m;
  real *charge;                 /* [m], fixed */
  Vec *v_short;                 /* [m], real, fixed */
  Vec v_long_fft;               /* complex, fixed */
  Vec *c;                       /* [m], real, work */
  Vec *c_fft, *t_fft;           /* [m], complex, work */
  Vec *chi_fft;                 /* [m][m], complex, fixed */
  Vec *tau_fft;                 /* [m], complex, fixed */
} Ctx1;


/*
  Implements the objective function for non-linear solver:

    dt = (χ - 1) * c(t) - t

  Must have the interface of VecFunc1, see bgy3d-snes.h.
*/
static void
iterate_t1 (Ctx1 *ctx, Vec T, Vec dT)
{
  /* alias of the right shape: */
  const int m = ctx->m;
  Vec (*chi_fft)[m] = (void*) ctx->chi_fft; /* [m][m], complex, in */

  const ProblemData *PD = ctx->HD->PD;
  const real beta = PD->beta;
  const real h3 = volume_element (PD);
  const real L3 = volume (PD);

  /* Establish aliases to the subsections of the long Vec T and dT: */
  local Vec t[m], dt[m];
  vec_aliases_create1 (T, m, t);
  vec_aliases_create1 (dT, m, dt);

  /*
    The  new  candidate for  the  direct  uv-correlation  c using  the
    closure relation:
  */
  for (int i = 0; i < m; i++)
    {
      compute_c (PD->closure, beta, ctx->v_short[i], t[i], ctx->c[i]);

      /* fft(c).  Here  c is the  3d unknown direct  uv-correlation of
         the solvent sites and the solute species as the whole: */
      MatMult (ctx->HD->fft_mat, ctx->c[i], ctx->c_fft[i]);

      /* scaling by h^3 in forward FFT */
      VecScale (ctx->c_fft[i], h3);

      /*
        The real-space  representation encodes only  the short-range
        part  of  the  direct  corrlation. The  (fixed)  long  range
        contribution is added here:

          C := C  - βV
                S     L

        The long-range asymptotics is  of electrostatic origin so that
        site-specific potentials are proportional to the site charges:
      */
      if (!ctx->tau_fft)
        VecAXPY (ctx->c_fft[i], -beta * ctx->charge[i], ctx->v_long_fft);
    }

  /*
    Now

      t   = (χ - 1) * c
       vu     vv       vu

    Here χ  is the constant solvent  susceptibility.  The "convolution
    star" corresponds  to a matrix multiplication in  the k-space: for
    each solvent site sum over  solvent sites.  Note that the input in
    chi_fft[][] corresponds to χ - 1.

    Now we  apply the  scaling of  h^3 in forward  FFT and  divide the
    result by L^3 in backward FFT, replace  1.0 / N3 as 1.0 ( 1.0 / N3
    = h^3 / L^3 )
  */
  star (m, chi_fft, ctx->c_fft, ctx->t_fft);

  /* t = fft^-1 (fft(c) * fft(h)). Here t is 3d t1. */
  for (int i = 0; i < m; i++)
    {
      /*
        Since we plugged  in the Fourier transform of  the full direct
        correlation including the long range part into the OZ equation
        what we get out is the full indirect correlation including the
        long-range part.  The menmonic is  C + T is short range.  Take
        it out:

          T := T - βV
           S         L
      */
      if (ctx->tau_fft)
        VecAXPY (ctx->t_fft[i], -beta * EPSILON0INV, ctx->tau_fft[i]);
      else
        VecAXPY (ctx->t_fft[i], -beta * ctx->charge[i], ctx->v_long_fft);

      MatMultTranspose (ctx->HD->fft_mat, ctx->t_fft[i], dt[i]);

      /* Scaling by inverse volume factor in backward FFT */
      VecScale (dt[i], 1.0 / L3);
    }


  /*
    This  destroys the  aliases,  but  does not  free  the memory,  of
    course. The actuall data is owned by Vec T and Vec dT. From now on
    one may access T and dT directly again.
  */
  vec_aliases_destroy1 (T, m, t);
  vec_aliases_destroy1 (dT, m, dt);

  /*
    dt := t    - t
           out    in
  */
  VecAXPY (dT, -1.0, T);
}


/* Must have the interface of VecFunc2, see bgy3d-snes.h: */
static void
jacobian_t1 (Ctx1 *ctx, Vec T, Vec dT, Vec JdT)
{
  /* See iterate_t1() above! */
  const int m = ctx->m;
  Vec (*chi_fft)[m] = (void*) ctx->chi_fft; /* [m][m], complex, in */

  const ProblemData *PD = ctx->HD->PD;
  const real beta = PD->beta;
  const real h3 = volume_element (PD);
  const real L3 = volume (PD);

  /* Establish aliases to the subsections of the long Vecs: */
  local Vec t[m], dt[m], jdt[m];
  vec_aliases_create1 (T, m, t);
  vec_aliases_create1 (dT, m, dt);
  vec_aliases_create1 (JdT, m, jdt);

  for (int i = 0; i < m; i++)
    {
      /* Re-use ctx->c[] work array for dc(r): */
      compute_c1 (PD->closure, beta, ctx->v_short[i], t[i], dt[i], ctx->c[i]);

      /* Re-use ctx->c_fft[] work array for dc(k): */
      MatMult (ctx->HD->fft_mat, ctx->c[i], ctx->c_fft[i]);

      VecScale (ctx->c_fft[i], h3);
    }

  /* Re-use ctx->t_fft[] work array for (χ - 1) * dc: */
  star (m, chi_fft, ctx->c_fft, ctx->t_fft);

  /* t = fft^-1 (fft(c) * fft(h)). Here t is 3d t1. */
  for (int i = 0; i < m; i++)
    {
      /* Put J * dT = (χ - 1) * dc into the Vec provided by the solver: */
      MatMultTranspose (ctx->HD->fft_mat, ctx->t_fft[i], jdt[i]);

      /* Scaling by inverse volume factor in backward FFT */
      VecScale (jdt[i], 1.0 / L3);
    }

  vec_aliases_destroy1 (T, m, t);
  vec_aliases_destroy1 (dT, m, dt);
  vec_aliases_destroy1 (JdT, m, jdt);

  /*
    J * δt := δF = δ(T[t] - t) = δT - δt = (χ - 1) * δc - δt
  */
  VecAXPY (JdT, -1.0, dT);
}


/*************************************************************/
/* A FEW FUNCTIONS TO MAKE SOLVENT SUSCEPTIBILITY AVAIALBLE. */
/*************************************************************/


/*
  Layed off  from solvent_kernel().  Reads  χ - 1 into  chi_fft[][] as
  previousely  written by  solvent solver.   See hnc3d_solvent_solve()
  above.
*/
static void
solvent_kernel_file3 (int m, Vec chi_fft[m][m]) /* out */
{
  bgy3d_vec_read2 ("x%d%d-fft.bin", m, chi_fft); /* ready for use as is */
}


/* Layed off from  solvent_kernel(). Reads 1d site-site susceptibility
   into a 3d Vec then FFTs it. Not really used. */
static void
solvent_kernel_file1 (State *HD, int m, Vec chi_fft[m][m]) /* out */
{
  /*
    Load radial  data from text file.   FIXME: representing long-range
    on a real-space grid is intrinsically broken!
  */
  const real dV = volume_element (HD->PD);

  local Vec chi[m][m];
  vec_create2 (HD->da, m, chi);

  bgy3d_vec_read_radial2 (HD->da, HD->PD, "x%d%d.txt", m, chi);

  for (int i = 0; i < m; i++)
    for (int j = 0; j <= i; j++)
      {
        MatMult (HD->fft_mat, chi[i][j], chi_fft[i][j]);
        VecScale (chi_fft[i][j], dV);

        /* Translate the distribution to the grid corner. This is what
           one expects in convolution integrals. */
        bgy3d_vec_fft_trans (HD->dc, HD->PD->N, chi_fft[i][j]);
      }
  vec_destroy2 (m, chi);
}

/* Layed off  from solvent_kernel().  Puts χ -  1 into  chi_fft[][] as
   computed by 1d RISM solvent solver. See ./rism.f90. */
static void
solvent_kernel_rism1 (State *HD, int m, const Site solvent[m], /* in */
                      Vec chi_fft[m][m], /* out, corner */
                      Vec tau_fft[m])    /* out, center, optional */
{
  /*
    Problem data for use in 1d-RISM  code.  If you do not upscale, the
    rmax =  max (PD->L) / 2 will  be too low for  interpolation on the
    r-grid. Though here only the k-grid is of interest.
  */
  ProblemData pd = rism_upscale (HD->PD);

  /*
    The struct  ProblemData encodes 3D  domain, the 1D solver  has its
    own  conventions how  to derive  the radial  grid  parameters from
    those of the 3D domain:
   */
  const int nrad = rism_nrad (&pd);
  const real rmax = rism_rmax (&pd);

  real x_fft[m][m][nrad];

  /*
    1D-RISM calculation.   Dont need neither  indirect correlation nor
    the result dictionary, only need χ(k):
  */
  rism_solvent (&pd, m, solvent, NULL, x_fft, NULL);

  /*
    The code  that tabulates  the k-rep on  3D grid  makes assumptions
    about the 1D grid:  the lowest k is dk/2 where dr *  dk = π / nrad
    and dr = rmax / nrad:
  */
  const real dk = M_PI / rmax;

  /*
    Ask the 1D code to compute T[v] + v = χ * v for a Coulomb field of
    a Gaussian charge distribution of finite width.  The input Coulomb
    field is  fully specified by  the Gaussian width and  solvent site
    charges.   Note  that the  1/ε₀  factor  is  NOT included  in  the
    dimensionless result. The output is non-trivially site-specific.
  */
  if (tau_fft)
    {
      real tau_fft_[m][nrad];   /* 1D version */

      rism_solute_renorm (m, solvent, rmax, nrad, x_fft, G_COULOMB_INVERSE_RANGE,
                          tau_fft_);

      for (int i = 0; i < m; i++)
        vec_ktab (HD, nrad, tau_fft_[i], dk, tau_fft[i]);

      /* Translate distribution to the grid center: */
      for (int i = 0; i < m; i++)
        bgy3d_vec_fft_trans (HD->dc, HD->PD->N, tau_fft[i]);
    }
  /*
    By now in each of m  3D tables tau_fft[i] we have an approximation
    for  some radial  function  that corresponds  to  a unit  gaussian
    solute charge at  the origin.  A molecular solute  will consist of
    many charges of different magnitude and at different locations. It
    is,  however, not  the  task  of the  procedure  that returns  the
    solvent kernel to account for that.  Let the caller superimpose as
    many   terms   as   there    are   solute   sites   instead.   See
    bgy3d_solute_form() for how to do that.

    NOTE: When adding the resulting renormalization term do not forget
    to scale the dimensionless addition by -β/ε₀, see iterate_t1().
  */

  /* The solute/solvent code expects χ - 1. Offset the diagonal: */
  for (int i = 0; i < m; i++)
    for (int k = 0; k < nrad; k++)
      x_fft[i][i][k] -= 1;

  /* FIXME: assuming symmetric χ - 1 with aliasing: */
  for (int i = 0; i < m; i++)
    for (int j = 0; j <= i; j++)
      vec_ktab (HD, nrad, x_fft[i][j], dk, chi_fft[i][j]);
}


/*
  Puts solvent susceptibility χ - 1 into chi_fft[][] by a one of a few
  available  methods  solver.    The  logic  dispatcher.   See  actual
  solvent_kernel_*() functions above.
*/
static void
solvent_kernel (State *HD, int m, const Site solvent[m], /* in */
                Vec chi_fft[m][m],                       /* out */
                Vec **tau_fft)  /* out, [m] or NULL */
{
  if (bgy3d_getopt_test ("solvent-3d"))
    {
      /*
        FIXME: we get the solvent description as an argument, but read
        the file to get susceptibility.  There is no guarantee the two
        sources are consistent.

        FIXME: Optimized NG scheme  not implemented in these branches,
        we do yet construct, allocate and return tau_fft[m] here:
      */
      tau_fft = NULL;
      if (bgy3d_getopt_test ("from-radial-g2")) /* FIXME: better name? */
        solvent_kernel_file1 (HD, m, chi_fft);    /* never used */
      else
        solvent_kernel_file3 (m, chi_fft); /* regular case */
    }
  else
    {
      /*
        Here we can offer  renormalization of the indirect correlation
        function t.   Other branches do  not, so it would  be somewhat
        illogical to  request that solvent_kernel()  always expects an
        array  of allocated Vecs.   Instead we  create and  return one
        only in this case:
      */
      if (bgy3d_getopt_test ("no-renorm"))
        *tau_fft = NULL;
      else
        {
          /* The caller is reponsible to free them: */
          *tau_fft = malloc (m * sizeof (Vec));
          vec_create1 (HD->dc, m, *tau_fft);
        }

      /* Should handle NULL for last argument */
      solvent_kernel_rism1 (HD, m, solvent, chi_fft, *tau_fft);
    }
}


/*
  XXX: hm,  I am  getting very big  (in absolute terms)  mean energies
  here, around -25.8 kcal for PR-SPC/E water. Most of it, around -28.5
  kcal  is  the  (long-range)  electrostatic energy.   The  literature
  operates  with energies  of about  -41  kJ instead  [1]. The  formal
  definition of the internal energy is rather U = ∂(βA) / ∂β, and I am
  not  even sure  if  the *excess*  chemical  potential μ  == A  here.
  Numerical  experiment shows that  such a  derivative might  be quite
  different, in  this case about  -13 kcal or  -55 kJ. Anyway,  we are
  mostly  testing integration  of  singular terms  in preparation  for
  forces here.

  [1] http://www1.lsbu.ac.uk/water/models.html
*/
static real
energy (State *HD, int m, const Site solvent[m],
        Vec h[m],               /* in */
        Vec v_short[m],         /* in */
        Vec uc)                 /* in */
{
  /* Solvent charge density (divided by ρ): */
  local Vec nv = vec_duplicate (uc);
  local Vec g = vec_duplicate (uc);
  const real dN = HD->PD->rho * volume_element (HD->PD);

  real e = 0.0;
  VecSet (nv, 0.0);
  for (int i = 0; i < m; i++)
    {
      /* FIXME:  Assuming  neutral  solvent  here.  The  factor  ρ  is
         included in dN. */
      VecAXPY (nv, solvent[i].charge, h[i]);

      /* Short-range  contribution,  potential  v  is  singular,  g  ~
         exp(-βv) is negligibly small. See how it works together: */
      VecCopy (h[i], g);
      VecShift (g, 1.0);
      e += vec_dot (g, v_short[i]) * dN;
    }
  /* Long-range Coulomb term: */
  e += vec_dot (nv, uc) * dN;

  vec_destroy (&nv);
  vec_destroy (&g);

  return e;
}


static real
energy1 (State *HD,
         int m, const Site solvent[m],
         int n, const Site solute[n],
         Vec h[m],               /* in */
         real dx[n][3])          /* in */
{
  local Vec dv[m];
  vec_create1 (HD->da, m, dv);

  /* Compute differential dv of the solute field: */
  bgy3d_solute_field1 (HD, m, solvent, n, solute, dx, dv);

  local Vec g = vec_create (HD->da);
  const real dN = HD->PD->rho * volume_element (HD->PD);

  real de = 0.0;
  for (int i = 0; i < m; i++)
    {
      /* Differential  dv  is singular,  g  ~  exp(-βv) is  negligibly
         small. See how it works together: */
      VecCopy (h[i], g);
      VecShift (g, 1.0);
      /* PRINTF ("XXX: min(dv) = %f max(dv) = %f\n", vec_min (dv[i]), vec_max (dv[i])); */
      /* PRINTF ("XXX: min(g) = %f max(g) = %f\n", vec_min (g), vec_max (g)); */

      de += vec_dot (g, dv[i]) * dN;
      /* PRINTF ("XXX: pass\n"); */
    }

  vec_destroy1 (m, dv);
  vec_destroy (&g);

  return de;
}


static void
forces (State *HD,
        int m, const Site solvent[m],
        int n, const Site solute[n],
        Vec h[m],               /* in */
        real f[n][3])           /* out */
{
  real dx[n][3];

  void set_dx (int k)
  {
    int k1 = 0;
    for (int i = 0; i < n; i++)
      FOR_DIM
        {
          dx[i][dim] = (k == k1? 1.0: 0.0);
          k1++;
        }
    assert (k1 == n * 3);
  }

  int k = 0;
  for (int i = 0; i < n; i++)
    FOR_DIM
      {
        set_dx (k);
        f[i][dim] = - energy1 (HD, m, solvent, n, solute, h, dx);
        k++;
      }
  assert (k == n * 3);
}


/*
  Solving  HNC3d equations.   Solvent  susceptibility χ  -  1 of  pure
  solvent  appears  as a  fixed  input  here.  A primary  variable  is
  indirect correlation t related to h by one of the closure relations.

  Historically  another   branch  of   the  code  treated   the  total
  correlation  h as  a primary  variable.  At  least for  water  in OW
  solvent (water-like model, just  a neutral oxygen with LJ parameters
  of  water) Newton  iteration over  t  ~ log  [g exp(βv)]  converges,
  whereas iteration over h = g -  1 does not.  The problem with h as a
  primary  variable  cannot be  severe  as  the  Jager solver  manages
  that. On  the other hand h  = g -  1 is nearly discontinuous  at the
  cavity border and formally constrained by h >= -1.  Intuitively this
  does  not make  the  task of  the  fixpoint solver  easier. So  that
  alternative has been abandoned in favor of indirect correlation t as
  a primary variable.
*/
void
hnc3d_solute_solve (const ProblemData *PD,
                    const int m, const Site solvent[m],
                    const int n, const Site solute[n],
                    void (*density)(int k, const real x[k][3], real rho[k]),
                    real *mu,   /* out, chemical potential */
                    Vec g[m],
                    Context **medium,  /* out */
                    Restart **restart) /* inout, so far unchanged  */
{
  /* Default is to not apply boundary condition in HNC code: */
  const PetscBool cage = false;

  /* Code used to be verbose: */
  bgy3d_problem_data_print (PD);

  const real L3 = volume (PD);

  PRINTF ("(iterations for γ)\n");

  State *HD = bgy3d_state_make (PD); /* FIXME: rm unused fields */

  /* This will be  a functional h(t) of primary  variable.  FIXME: not
     deallocated: */
  Vec h[m];
  vec_create1 (HD->da, m, h);

  /* Site-specific short-range field of the solute: */
  local Vec v_short[m];
  vec_create1 (HD->da, m, v_short);

  /*
    Get   solute-solvent  interaction.    Fill  v_short[i]   with  the
    short-range potential  acting on solvent site  "i". The long-range
    part, Vec uc_fft,  is represented on the k-grid  and is assumed to
    differ  only   by  factors   proportional  to  the   solvent  site
    charges. Neither  one is spherically  symmetric for a solute  of a
    general shape --- do not confuse with 1D formalizm.

    Note that  asymptotic Coulomb field of the  *neutral* solute would
    be formally of  the short-range.  In practice it  appears that the
    observables do not  change if we treat it as  either the short- or
    the long  range (as now).  Also  for such neutral  species it does
    not matter much if we  obtain the real space representation of the
    Coulomb, needed later for chemical potential, by an FFT of uc_fft.

    Fourier transform  of long-range Coulomb field of  the solute, and
    the corresponging charge density  of smeared cores (used later for
    observables) go here:
  */
  local Vec uc_fft = vec_create (HD->dc);
  local Vec uc_rho = vec_create (HD->da); /* used for observables */

  bgy3d_solute_field (HD, m, solvent, n, solute,
                      v_short, uc_fft,    /* out */
                      uc_rho,   /* out, smeared cores */
                      NULL,     /* dont need uc, yet */
                      density); /* in, electron density callback */

  /*
    Scaling  factors  for  the  site-specific long  range  potentials.
    Instead of  storing multiple proportional fields we  will pass the
    factors separately:
  */
  real charge[m];
  for (int i = 0; i < m; i++)
    charge[i] = solvent[i].charge;

  /*
    For primary variable t there are  two ways to access the data: via
    the long Vec  T and m shorter Vec t[m]  aliased to the subsections
    of the longer one.
  */
  local Vec T = vec_pack_create1 (HD->da, m); /* long Vec */

  /* Zero as intial guess for t  is (almost?) the same as exp(-βv) - 1
     initial guess for h: */
  if (restart && *restart)
    {
      /*
        If the argument  is present and valid, this is  the data to be
        used for resuming iterations.  So  far this data is just a ref
        to a long Vec that happens to fit into a pointer:
      */
      Vec T_old = (Vec) *restart;

      /* Initialize long Vec  T by copying restart data  from the last
         run: */
      VecCopy (T_old, T);
      bgy3d_restart_destroy (*restart);
    }
  else
    VecSet (T, 0.0);

  {
    local Vec c_fft[m];
    vec_create1 (HD->dc, m, c_fft); /* complex */

    local Vec t_fft[m];
    vec_create1 (HD->dc, m, t_fft); /* complex */

    /*
      This should be  the only pair quantity, χ -  1. FIXME: note that
      this is  a property  of the  pure solvent and  is (in  theory) a
      spherically  symmetric  quantity.   Spherical symmetry  is  only
      approximate  if  χ  was  prepared   by  the  3D  code  for  pure
      solvent. Also this is a complex Vec holding real data (modulo 3D
      artifacts). We are wasting here quite some memory!
    */
    local Vec chi_fft[m][m];
    vec_create2 (HD->dc, m, chi_fft);        /* complex */

    /*
      This one will hold site-specific renormalization χ * uc later as
      an array tau_fft[m]. Only used for an optimized Ng scheme if the
      solvent_kernel() can supply  that. Currenly, only 1D-RISM kernel
      is capable of doing that.
    */
    local Vec *tau_fft = NULL;  /* complex, [m] or NULL */

    /*
      Get  the solvent-solvent  susceptibility  (offset by  one) as  a
      matrix of complex Vecs chi_fft[m][m]. The kernel derived from 1D
      RISM is  capable or supplying an array  of renormalization terms
      in tau_fft[m] in addition. Others just set it to NULL:
    */
    solvent_kernel (HD, m, solvent, chi_fft, &tau_fft);

    /*
      Now  chi_fft[][] contains  χ -  1  and tau_fft[],  if not  NULL,
      contains the  result of application χ  * uc for  a single center
      uc.   The solvent  kernel knows  nothing about  geometry  of the
      solute and it should stay  like that.  To get a superposition of
      the  long-range potentials  of  all solute  centers weighted  by
      their charge we apply the convolution with the form factor here:
    */
    if (tau_fft)
      {
        /* Once again,  n is  the number of  solute sites  form factor
           will get n charges and n positions: */
        real q[n], x[n][3];

        /* The   charges  we   have  copied   before  were   those  of
           solvent. Here we need those of solute. And positions: */
        for (int i = 0; i < n; i++)
          {
            q[i] = solute[i].charge;

            FOR_DIM
              x[i][dim] = solute[i].x[dim];
          }

        /*
          The convolution  with the electric form  factor adds another
          charge dimension to the result.   Do not forget to scale the
          term  by  -β/ε₀, when  adding  to  the  renormalized t,  see
          iterate_t1(). FIXME: or should we rather make tau_fft[] have
          the dimension  of the potential  to be measuted in  kcal? In
          this case one would need to scale by 1/ε₀ right away.

          Again,  m is the  number of  solvent sites  and this  is the
          number of different renormalization functions tau_fft[m].
        */
        for (int i = 0; i < m; i++) /* m: over solvent sites ... */
          bgy3d_solute_form (HD, n, q, x, tau_fft[i]);
        /* n, q[n], x[n][3]: solute charges and positions */
      }

    /*
      Find T  such that dt  as returned by  iterate_t1 (HD, T,  dT) is
      zero. Cast is there to silence the mismatch in the type of first
      pointer argument: Ctx1* vs. void*:
    */
    {
      /* Work area for iterate_t1(): */
      Ctx1 ctx =
        {
          .HD = HD,
          .m = m,
          .charge = charge,           /* [m], in */
          .v_short = v_short,         /* [m], real, in */
          .v_long_fft = uc_fft,       /* complex, in */
          .c = h,                     /* [m], work for c(t) */
          .chi_fft = (void*) chi_fft, /* [m][m], pair quantitity, in */
          .c_fft = c_fft,             /* [m], work for c(t) */
          .t_fft = t_fft,             /* [m], work for t(c(t))) */
          .tau_fft = tau_fft,         /* [m] or NULL, complex, in */
        };

      bgy3d_snes_default (PD, &ctx, (VecFunc1) iterate_t1, (VecFunc2) jacobian_t1, T);
    }
    vec_destroy1 (m, c_fft);
    vec_destroy1 (m, t_fft);
    if (tau_fft)
      {
        vec_destroy1 (m, tau_fft);
        free (tau_fft);
        tau_fft = NULL;         /* because local */
      }

    /* This should have been the only pair quantity: */
    vec_destroy2 (m, chi_fft);
  }

  /*
    Now that the solution T has  converged, use it to compute the rest
    of the  quantities.  (Re)evaluate  c(t) and h(t)  without assuming
    that e.g. Vec h already has any meaningful value.  We need h and c
    to to compute chemical potential:
  */
  local Vec t[m];
  vec_aliases_create1 (T, m, t); /* aliases to subsections */

  local Vec c[m];
  vec_create1 (HD->da, m, c);

  /* Closure  relation, c  = c(t),  used to  compute h  and  later the
     chemical potential: */
  for (int i = 0; i < m; i++)
    compute_c (PD->closure, PD->beta, v_short[i], t[i], c[i]);

  /* h = c + t, used for chempot and output: */
  for (int i = 0; i < m; i++)
    VecWAXPY (h[i], 1.0, c[i], t[i]);

  /*
    Now get the real-space represenation of long-range part of Coulomb
    field, which  would be supplied to  chemical potential calculation
    later.   It is  also  used  to compute  the  observables, such  as
    electrostatic interaction energy of  the solute and solvent charge
    densities,  see   the  call   to  info()  below.   The  real-space
    representation is not (and should not be) used during iterations.

    When comparing the expectation values of electrostatic interaction
    computed as <ρ(v)|U(u)> and <U(v)|ρ(u)> a much better agreement is
    obtained if both potentials are  obtained in the same way from the
    corresponding  charge  denisties, e.g.   by  solving the  Posisson
    equation.

    We do  not yet have a way  to properly treat the  Coulomb field of
    the medium that carries a  net charge.  A combination of (inverse)
    FFT and bgy3d_poisson() is not likely to give very accurate result
    in this case due to the long range nature of the field.
   */
  local Vec uc = vec_create (HD->da);
  if (neutral_solutes)          /* was always assumed */
    {
      /* The field of  neutral species is actually of  short range, so
         this worked for them: */
      MatMultTranspose (HD->fft_mat, uc_fft, uc);

      /* Apply inverse volume factor after inverse FFT */
      VecScale (uc, 1.0 / L3);
    }
  else
    bgy3d_solute_field (HD, m, solvent, n, solute, NULL, NULL, NULL,
                        uc, density); /* the rest computed before */

  /* Should not be needed anymore: */
  vec_destroy (&uc_fft);


  /* Excess chemical potential: */
  {
    /*
       We used  to supply the  long-range part for  chemical potential
       calculation  obtained by FFT  over the  finite size  unit cell.
       This  is possibly  inaccurate for  the long-range  potential of
       charged systems.  Check the value of const bool neutral_solutes
       that controls that.

       FIXME:  Though  the chemical  potential  code  does assume  the
       asymptotics of  the direct  correlations to be  proportional to
       the solvent charges (see how we handle the term linear in C) we
       still supply m redundant vectors:
     */
    local Vec cl[m];
    vec_create1 (HD->da, m, cl);

    /* Renormalized indirect correlation: x = -βv + t: */
    local Vec x[m];
    vec_create1 (HD->da, m, x);

    for (int i = 0; i < m; i++)
      {
        VecSet (cl[i], 0.0);
        VecAXPY (cl[i], -PD->beta * charge[i], uc);

        /* Renormalized indirect correlation: x = -βv + t: */
        VecWAXPY (x[i], -PD->beta, v_short[i], t[i]);
      }

    /*
      In  3d  models  the  solute  is  effectively  a  single  (albeit
      non-spherical) site. Treat the arrays  h[m], c[m] and cl[m] as 1
      x m arrays here.

      First   and  foremost   compute  the   self-consistent  chemical
      potential to be returned to the caller:
    */
    *mu = chempot (HD, HD->PD->closure, 1, m,
                   (void*) x, (void*) h, (void*) c, (void*) cl);

    /* This computes,  prints and  discards chemical potential  by all
       available functionals */
    print_chempot (HD, 1, m, (void*) x, (void*) h, (void*) c, (void*) cl);

    vec_destroy1 (m, cl);
    vec_destroy1 (m, x);
  }

  /* Derivatives of the chemical potential: */
  if (true)
    {
      PRINTF ("# XXX: call energy 5 ...\n");
      const real e = energy (HD, m, solvent, h, v_short, uc);
      PRINTF ("# XXX: energy = %f\n", e);

      real f[n][3], fsum[3] = {0.0, 0.0, 0.0};
      forces (HD, m, solvent, n, solute, h, f);
      for (int i = 0; i < n; i++)
        {
          FOR_DIM
            fsum[dim] += f[i][dim];
          PRINTF ("# XXX: f(%d) = (%f %f %f)\n", i, f[i][0], f[i][1], f[i][2]);
        }
      PRINTF ("# XXX: f(s) = (%f %f %f)\n", fsum[0], fsum[1], fsum[2]);
    }

  /* Last used for x = -βv + t and in chempot code above. */
  vec_destroy1 (m, v_short);
  vec_destroy1 (m, c);
  vec_aliases_destroy1 (T, m, t);


  /* Do not destroy  the long Vec T, return it as  restart info if the
     caller requested that: */
  if (restart)
    {
      /*
        This is probably QM code  calling, eventually this will not be
        the last  call during  SCF.  Pass  the long Vec  T to  help us
        restart iterations  in the next  SCF round.  At this  point we
        give up ownersip of the long  Vec T to the caller.  The caller
        will  eventually have  to dispose  of it  by means  of calling
        bgy3d_restart_destroy(),  unless  it is  passed  back to  this
        function.
      */
      *restart = (void*) T;
      T = NULL;                 /* because declared local */
    }
  else
    vec_pack_destroy1 (&T);     /* not vec_destroy()! */


  /* g := h + 1 */
  for (int i = 0; i < m; i++)
    VecShift (h[i], 1.0);       /* FIXME: misnomer! */

  /* Return  the   Context  **ret  to  caller   for  integration  over
     electrostatic potential of solvent */
  Context *ret = info (HD, m, solvent, n, solute, h, uc, uc_rho, cage);
  if (medium)
    *medium = ret;
  else
    bgy3d_pot_destroy (ret);

  /* Keep uc and uc_rho until being used in info() */
  vec_destroy (&uc);
  vec_destroy (&uc_rho);

  /* free stuff */
  /* Delegated to the caller: vec_destroy (&h) */

  bgy3d_state_destroy (HD);

  /* Caller is supposed to destroy it! */
  for (int i = 0; i < m; i++)
    g[i] = h[i];                /* FIXME: misnomer! */

  bgy3d_vec_save1 ("g%d.bin", m, g);
}
