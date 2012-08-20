void Compute_dg_Pair_inter(BGY3dDiatomicABData BDD, Vec f1[3], real sign1,
			   Vec g1a, Vec g1b,
			   Vec f2[3], real sign2,
			   Vec g21, Vec g2b, Vec dg, Vec g_help);
void Compute_dg_Pair_intra(BGY3dDiatomicABData BDD, Vec f[3], Vec g1, Vec g2,
			   Vec dg, Vec dg_help);
void Compute_dg_Pair_normalization(BGY3dDiatomicABData BDD, Vec g1, Vec g2,
				   Vec dg, Vec dg_help);
Vec BGY3d_solve_DiatomicAB(ProblemData *PD, Vec g_ini, int vdim);
void ComputeDiatomicAB_g(Vec g, Vec g0, Vec dg);
fftw_complex *ComputeFFTfromVec_fftw(DA da, fftwnd_mpi_plan fft_plan, Vec g,
				fftw_complex *g_fft, fftw_complex *work,
				real c);
void ComputeVecfromFFT_fftw(DA da, fftwnd_mpi_plan fft_plan, Vec g,
			    fftw_complex *g_fft, fftw_complex *work,
			    int x[3], int n[3], real c);
