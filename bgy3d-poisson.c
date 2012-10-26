/* -*- mode: c; c-basic-offset: 2; -*- vim: set sw=2 et sta ai: */
/*==========================================================*/
/*  $Id: bgy3dH2O_solutes.c,v 1.3 2007-08-03 15:59:50 jager Exp $ */
/*==========================================================*/

#include "bgy3d.h"
#include "bgy3d-poisson.h"

/*
  Solve  Poisson  Equation  in  Fourier space  and  get  elestrostatic
  potential by inverse FFT.

  Vec uc is intent(out).
  Vec rho is intent(in).
  real q is the overall factor.

  As a  matter of  fact, it  appears that one  could provide  the same
  factual parameter  for rho and  uc to effectively solve  the Poisson
  equation "in place".

  Except of  temporary allocation of a  complex Vec does  not have any
  side effect.
*/
void bgy3d_poisson (const State *BHD, Vec uc, Vec rho, real q)
{
  const real *interval = BHD->PD->interval; /* [2] */
  const real *h = BHD->PD->h;   /* h[3] */
  const int *N = BHD->PD->N;    /* N[3] */

  const real L = interval[1] - interval[0];
  const real h3 = h[0] * h[1] * h[2];

  /* Scratch complex vector: */
  Vec work;
  DACreateGlobalVector (BHD->dc, &work);

  /* Get FFT of  rho: rho(i, j, k) -> fft_rho(kx,  ky, kz) placed into
     complex work: */
  MatMult (BHD->fft_mat, rho, work);

  /*
    Solving Poisson Equation (SI units) with FFT and IFFT:

        - ΔU (x, y, z) = (1 / ε₀) ρ(x, y, z)
            c

    because of x = i h, y = j h, and z = k h, with grid spacing h =
    L/n:

        - n² / L²  Δuc(i, j, k) = (1 / ε₀) ρ(i, j, k)

    FFT (see FFTW manual "What FFTW Really Computes"):

    fft_uc(kx, ky, kz) = 1 / [4 π²  ε₀ k²  / L² ] fft_rho(kx, ky, kz)

    with

        k² = kx² + ky² + kz²

    IFFT (see FFTW manual "What FFTW Really Computes"):

    because: IFFT(fft_uc(kx, ky, kz)) = n³ * uc(i, j, k)

    uc(i, j, k) = h³ / L³  * IFFT(fft_uc(kx, ky, kz))
  */

  /* EPSILON0INV = 1 / 4 π ε₀: */
  const real scale = q * EPSILON0INV / M_PI * h3 / (L * L * L);

  /* Loop over local portion of the k-grid */
  {
    int x[3], n[3], i[3], ic[3];
    DAGetCorners (BHD->dc, &x[0], &x[1], &x[2], &n[0], &n[1], &n[2]);

    struct {PetscScalar re, im;} ***work_;
    DAVecGetArray (BHD->dc, work, &work_);

    for (i[2] = x[2]; i[2] < x[2] + n[2]; i[2]++)
      for (i[1] = x[1]; i[1] < x[1] + n[1]; i[1]++)
        for (i[0] = x[0]; i[0] < x[0] + n[0]; i[0]++)
          {
            /* FIXME: what is we  change the complex vectors to remove
               the redundnacy? */
            FOR_DIM
              {
                if (i[dim] <= N[dim] / 2)
                  ic[dim] = i[dim];
                else
                  ic[dim] = i[dim] - N[dim];
              }

            if (ic[0] == 0 && ic[1] == 0 && ic[2] == 0)
              {
                /* The gamma point, k = 0, we cannot divide by 0: */
                work_[i[2]][i[1]][i[0]].re = 0.0;
                work_[i[2]][i[1]][i[0]].im = 0.0;
              }
            else
              {
                const real k2 = (SQR(ic[2]) + SQR(ic[1]) + SQR(ic[0])) / SQR(L);

                const real fac = scale / k2;

                /* Here we compute in place: uc(kx, ky, kz) := scale *
                   rho(kx, ky, kz) / k^2 */
                work_[i[2]][i[1]][i[0]].re *= fac;
                work_[i[2]][i[1]][i[0]].im *= fac;
              }
          }
    DAVecRestoreArray (BHD->dc, work, &work_);
  }

  /* uc := IFFT(uc(kx, ky, kz)) */
  MatMultTranspose (BHD->fft_mat, work, uc);

  VecDestroy (work);
}


#ifdef L_BOUNDARY
/* Returns a  non-negative number,  e.g. mod(-1, 10)  -> 9.   Does not
   work for b <= 0: */
static int mod (int a, int b)
{
  return ((a % b) + b) % b;
}


/* Initialize M-Matrix with appropriate stencil. FIXME: this should be
   probably implemented using matrix free facilities of Petsc. */
void InitializeLaplaceMatrix (const State *BHD, real zpad)
{
  const PetscScalar one = 1.0;

  PetscPrintf (PETSC_COMM_WORLD, "Assembling Matrix...");

  const DA da = BHD->da;
  const ProblemData *PD = BHD->PD;
  const int *N = PD->N;         /* N[3] */
  const real *h = PD->h;        /* h[3] */

  Mat M = BHD->M;
  MatZeroEntries(M);

  const real size = PD->interval[1] - PD->interval[0];
  const int border = 1 + (int) ceil ((size - 2.0 * zpad) / h[0] / 2.0);

  /* This code constructs (a compact  representation of) the N^3 x N^3
     matrix  M.  An identity  or another  diagonal matrix  will always
     have  row == col.   The Laplace  matrix is  sparse as  in "nearly
     diagonal".  col[3] will be used  to hold the coordinated of three
     stencil points in a row. Note that "3" is not the space dimension
     but  rather  the  stencil  size  for  second  derivative  in  one
     dimension.   The  central  point,   in  col[1]  ==  *(col  +  1),
     corresponds to the current grid point with indices i[]. */

  /* Get local portion of the grid */
  int x[3], n[3], i[3];
  DAGetCorners (da, &x[0], &x[1], &x[2], &n[0], &n[1], &n[2]);

  /* Loop over local portion of grid: */
  for (i[2] = x[2]; i[2] < x[2] + n[2]; i[2]++)
    for (i[1] = x[1]; i[1] < x[1] + n[1]; i[1]++)
      for (i[0] = x[0]; i[0] < x[0] + n[0]; i[0]++)
        {
          MatStencil row;
          /* This  is the  point  on the  diagonal  of the  N^3 x  N^3
             matrix: */
          row.i = i[0];
          row.j = i[1];
          row.k = i[2];

          /* Boundary */
          if (i[0] <= border || i[0] >= N[0] - border ||
              i[1] <= border || i[1] >= N[1] - border ||
              i[2] <= border || i[2] >= N[2] - border)
            {
              /* This  sets this  particular diagonal  element  of the
                 matrix to 1.0: */
              MatSetValuesStencil (M, 1, &row, 1, &row, &one, ADD_VALUES);
            }
          else
            {
              MatStencil col[3]; /* Three stencil points in the row. */

              /* Central point of the stencil, same as row: */
              col[1].i = row.i;
              col[1].j = row.j;
              col[1].k = row.k;

              /*
                Other two  points of the  stencil offset by 1  in -dim
                and +dim, respectively are  set in the switch statment
                inside  the loop  over dim.   FIXME: we  might  have a
                problem for parallel runs here as the manual says:

                  The columns  and rows in  the stencil passed  in [to
                  MatSetValuesStencil()] MUST  be contained within the
                  ghost  region  of  the  given process  as  set  with
                  DMDACreateXXX() or MatSetStencil().

                See  call to  DACreate3d() in  bgy3d-fft.c, especially
                the periodicity and stencil options there.
              */
              FOR_DIM
                {
                  switch (dim)
                    {
                    case 0:
                      col[0].i = mod (row.i - 1, N[0]);
                      col[0].j = row.j;
                      col[0].k = row.k;

                      col[2].i = mod (row.i + 1, N[0]);
                      col[2].j = row.j;
                      col[2].k = row.k;
                      break;

                    case 1:
                      col[0].i = row.i;
                      col[0].j = mod (row.j - 1, N[1]);
                      col[0].k = row.k;

                      col[2].i = row.i;
                      col[2].j = mod (row.j + 1, N[1]);
                      col[2].k = row.k;
                      break;

                    case 2:
                      col[0].i = row.i;
                      col[0].j = row.j;
                      col[0].k = mod (row.k - 1, N[2]);

                      col[2].i = row.i;
                      col[2].j = row.j;
                      col[2].k = mod (row.k + 1, N[2]);
                      break;
                    }

                  /* Sanity check: */
                  for (int p = 0; p < 3; p++)
                    {
                      assert (col[p].i >= 0);
                      assert (col[p].j >= 0);
                      assert (col[p].k >= 0);
                      assert (col[p].i < N[0]);
                      assert (col[p].j < N[1]);
                      assert (col[p].k < N[2]);
                    }

                  /* Values to enter for the Laplacian stencil: */
                  const real h2 = SQR (h[dim]);
                  const PetscScalar v[3] = {1.0 / h2, -2.0 / h2, 1.0 / h2};

                  MatSetValuesStencil (M, 1, &row, 3, col, v, ADD_VALUES);
                }
            }
        }

  MatAssemblyBegin (M, MAT_FINAL_ASSEMBLY);
  MatAssemblyEnd (M, MAT_FINAL_ASSEMBLY);

  PetscPrintf (PETSC_COMM_WORLD, "done.\n");
}


void InitializeKSPSolver (Mat M, KSP *ksp)
{
  PC pc;

  /* Create ksp environment */
  KSPCreate (PETSC_COMM_WORLD, ksp);
  KSPGetPC (*ksp, &pc);
  KSPSetTolerances (*ksp, 1.0e-4, 1.0e-4, 1.0e+5, 1000);

  /* Set Matrix */
  //KSPSetOperators (*ksp, M, M, SAME_NONZERO_PATTERN);
  KSPSetOperators (*ksp, M, M, SAME_PRECONDITIONER);

  /* Set preconditioner */
  PCSetType (pc, PCBJACOBI);

  KSPSetInitialGuessNonzero (*ksp, PETSC_TRUE);

  /* runtime options will override default parameters */
  //KSPSetFromOptions(BHD->ksp);
}


static void CopyBoundary (const State *BHD, Vec gfrom, Vec gto, real zpad)
{
  DA da;
  int x[3], n[3], i[3], N[3], border; // ic[3], k;
  PetscScalar ***gfrom_vec, ***gto_vec;

  const ProblemData *PD = BHD->PD;
  da = BHD->da;
  FOR_DIM
    N[dim] = PD->N[dim];

  VecSet(gto, 0.0);

  border = (int) ceil( ((PD->interval[1]-PD->interval[0])-(2.*zpad))/PD->h[0]/2. );

  /* Get local portion of the grid */
  DAGetCorners(da, &x[0], &x[1], &x[2], &n[0], &n[1], &n[2]);

  DAVecGetArray(da, gfrom, &gfrom_vec);
  DAVecGetArray(da, gto, &gto_vec);


/*   FOR_DIM */
/*     { */
/*       ic[0]=dim; */
/*       ic[1]=(dim+1)%3; */
/*       ic[2]=(dim+2)%3; */
/*       i[ic[0]] = 0; */
/*       if( x[ic[0]] == 0 )  */
/*      for( i[ic[1]]=x[ic[1]]; i[ic[1]]<x[ic[1]]+n[ic[1]]; i[ic[1]]++) */
/*        for( i[ic[2]]=x[ic[2]]; i[ic[2]]<x[ic[2]]+n[ic[2]]; i[ic[2]]++) */
/*          gto_vec[i[2]][i[1]][i[0]] = gfrom_vec[i[2]][i[1]][i[0]]; */
/*       i[ic[0]] = N[ic[0]]-1; */
/*       if( x[ic[0]]+n[ic[0]] == N[ic[0]] )  */
/*      for( i[ic[1]]=x[ic[1]]; i[ic[1]]<x[ic[1]]+n[ic[1]]; i[ic[1]]++) */
/*        for( i[ic[2]]=x[ic[2]]; i[ic[2]]<x[ic[2]]+n[ic[2]]; i[ic[2]]++) */
/*          gto_vec[i[2]][i[1]][i[0]] = gfrom_vec[i[2]][i[1]][i[0]]; */
/*     } */

  /* loop over local portion of grid */
  for(i[2]=x[2]; i[2]<x[2]+n[2]; i[2]++)
    for(i[1]=x[1]; i[1]<x[1]+n[1]; i[1]++)
      for(i[0]=x[0]; i[0]<x[0]+n[0]; i[0]++)
        {
          if( ( i[0]<=border+1 || i[0]>=N[0]-1-border) ||
              ( i[1]<=border+1 || i[1]>=N[1]-1-border) ||
              ( i[2]<=border+1 || i[2]>=N[2]-1-border) )
            gto_vec[i[2]][i[1]][i[0]] = gfrom_vec[i[2]][i[1]][i[0]];
        }


  DAVecRestoreArray(da, gfrom, &gfrom_vec);
  DAVecRestoreArray(da, gto, &gto_vec);
}


double ImposeLaplaceBoundary (const State *BHD, Vec g, Vec b, Vec x, real zpad, int *iter)
{
  /* computation time measurement start point */
  MPI_Barrier (PETSC_COMM_WORLD);
  const double mpi_start = MPI_Wtime();

  /* Get boundary of g */
  CopyBoundary (BHD, g, b, zpad);
  //VecSet(x, 0.0);

  /* Solve Laplace */
  KSPSolve (BHD->ksp, b, x);

  if (iter != NULL)
    KSPGetIterationNumber (BHD->ksp, iter);

  /* subtract solution from g */
  VecAXPY(g, -1.0, x);

  /* computation time measurement stop point */
  MPI_Barrier( PETSC_COMM_WORLD);
  const double mpi_stop = MPI_Wtime();

  return mpi_stop - mpi_start;
}
#endif
