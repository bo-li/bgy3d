module kinds
  use iso_c_binding, only: c_double
  implicit none
  private

  integer, parameter, public :: rk = c_double
end module kinds


module fft
  use kinds, only: rk
  implicit none
  private

  real (rk), parameter, public :: pi = 4 * atan (1.0_rk)

  !
  ! These should  obey: ab  = (2π)³, a²b  = (2π)³. The  first equality
  ! guarantees  that that the  forward- and  backward FT  are mutually
  ! inverse,  whereas the  second equation  will make  the convolution
  ! theorem factor-less as in FT(f * g) = FT(f) FT(g):
  !
  real (rk), parameter, public :: FT_FW = 1           ! == a
  real (rk), parameter, public :: FT_BW = (2 * pi)**3 ! == b

  public :: fourier             ! x(1:n) -> y(1:n)

  !
  ! *** END OF INTERFACE ***
  !

  !
  ! This is a concrete function, implemented in C:
  !
  interface
     subroutine rism_dst (n, out, in) bind (c)
       !
       ! Performs DST. In FFTW terms this is RODFT11 (or DST-IV) which
       ! is self inverse up to a normalization factor.
       !
       ! void rism_dst (size_t n, double out[n], const double in[n])
       !
       ! See ./rism-dst.c
       !
       use iso_c_binding, only: c_size_t, c_double
       implicit none
       integer (c_size_t), intent (in), value :: n
       real (c_double), intent (out) :: out(n)
       real (c_double), intent (in) :: in(n)
     end subroutine rism_dst
  end interface

contains

  function fourier (f) result (g)
    implicit none
    real (rk), intent (in) :: f(:)
    real (rk) :: g(size (f))
    ! *** end of interface ***

    integer :: i, n

    n = size (f)

    !
    ! We use  RODFT11 (DST-IV) that is  "odd around j =  -0.5 and even
    ! around j  = n - 0.5".   Here we use integer  arithmetics and the
    ! identity (2 * j - 1) / 2 == j - 0.5.
    !
    forall (i = 1:n)
       g(i) = f(i) * (2 * i - 1)
    end forall

    g = 2 * n * dst (g)

    forall (i = 1:n)
       g(i) = g(i) / (2 * i - 1)
    end forall
  end function fourier


  function dst (a) result (b)
    use iso_c_binding, only: c_size_t
    implicit none
    real (rk), intent (in) :: a(:)
    real (rk) :: b(size (a))
    ! *** end of interface ***

    integer (c_size_t) :: n

    ! cast to size_t
    n = size (a)

    call rism_dst (n, b, a)
  end function dst


  function ndst (a) result (b)
    implicit none
    real (rk), intent (in) :: a(:)
    real (rk) :: b(size (a))
    ! *** end of interface ***

    real (rk) :: norm

    norm = 2 * size (b)         ! cast to real
    b = dst (a) / sqrt (norm)
  end function ndst


  subroutine test_dst (n)
    implicit none
    integer, intent (in) :: n
    ! *** end of interface ***

    real (rk) :: a(n)

    call random_number (a)

    ! RODFT11 (DST-IV) is self inverse up to a normalization factor:
    if (maxval (abs (a - dst (dst (a)) / (2 * n))) > 1.0e-10) then
       print *, "diff=", maxval (abs (a - dst (dst (a)) / (2 * n)))
       stop "unnormalized DST does not match"
    endif

    if (maxval (abs (a - ndst (ndst (a)))) > 1.0e-10) then
       print *, "diff=", maxval (abs (a - ndst (ndst (a))))
       stop "normalized DST does not match"
    endif
  end subroutine test_dst


  subroutine test_ft (rmax, n)
    implicit none
    integer, intent (in) :: n
    real (rk), intent (in) :: rmax
    ! *** end of interface ***

    real (rk) :: r(n), k(n), f(n), g(n), h(n)
    real (rk) :: dr, dk

    integer :: i

    !
    ! The 3d analytical unitary FT of the function
    !
    !   f = exp(-r²/2)
    !
    ! is the function
    !
    !   g = exp(-k²/2), FIXME!
    !
    dr = rmax / n
    dk = pi / rmax
    forall (i = 1:n)
       r(i) = (i - 0.5) * dr
       k(i) = (i - 0.5) * dk
    end forall

    ! Gaussian:
    f = exp (-r**2 / 2)

    ! Unit "charge", a "fat" delta function:
    f = f / (sum (r**2 * f) * 4 * pi * dr)

    ! Forward transform:
    g = fourier (f) * (dr**3 / FT_FW)

    ! Backward transform:
    h = fourier (g) * (dk**3 / FT_BW)

    print *, "# norm (f )^2 =", sum ((r * f)**2) * 4 * pi * dr
    print *, "# norm (g )^2 =", sum ((k * g)**2) * 4 * pi * dk
    print *, "# norm (f')^2 =", sum ((r * h)**2) * 4 * pi * dr

    print *, "# |f - f'| =", maxval (abs (f - h))

    print *, "# int (f') =", sum (r**2 * h) * 4 * pi * dr
    print *, "# int (f ) =", sum (r**2 * f) * 4 * pi * dr

    ! This should correspond  to the convolution (f *  f) which should
    ! be again a gaussian, twice as "fat":
    h = g * g
    h = fourier (h) * (dk**3 / FT_BW)

    print *, "# int (h ) =", sum (r**2 * h) * 4 * pi * dr

    ! Compare width as <r^2>:
    print *, "# sigma (f) =", sum (r**4 * f) * 4 * pi * dr
    print *, "# sigma (h) =", sum (r**4 * h) * 4 * pi * dr

    ! print *, "# n=", n
    ! print *, "# r, f, k, g, h = (f*f)"
    ! do i = 1, n
    !    print *, r(i), f(i), k(i), g(i), h(i)
    ! enddo
  end subroutine test_ft
end module fft


module snes
  use kinds, only: rk
  implicit none
  private

  public :: snes_default, snes_picard

  !
  ! *** END OF INTERFACE ***
  !

  !
  ! This defines two  iterator interfaces x -> dx  for use in fixpoint
  ! non-linear problems.  One is  the type of Fortran closures another
  ! is the corresponding type of C closures. Such an iterator function
  ! is supposed to return array of zeros (ok, rather small numbers) at
  ! convergence.
  !
  ! Well, "iterator"  is probably a  bad name.  These  "iterators" are
  ! supoosed  to be pure  functions of  the respective  arguments. The
  ! closure context is supposed to be used read-only (or only to store
  ! intermediate quantities derived from the argument at pre-allocated
  ! positions).  Violation of  these constraints will eventually break
  ! the carefully designed logic of some non-linear solvers.
  !
  abstract interface
     function f_iterator (x) result (dx)
       import rk
       implicit none
       real (rk), intent (in) :: x(:, :, :)
       real (rk) :: dx(size (x, 1), size (x, 2), size (x, 3))
     end function f_iterator

     subroutine c_iterator (ctx, n, x, dx) bind (c)
       use iso_c_binding, only: c_ptr, c_int, c_double
       implicit none
       type (c_ptr), intent (in), value :: ctx
       integer (c_int), intent (in), value :: n
       real (c_double), intent (in), target :: x(n)
       real (c_double), intent (out), target :: dx(n)
     end subroutine c_iterator
  end interface

  !
  ! This is a concrete function, implemented in C:
  !
  interface
     subroutine rism_snes (ctx, f, n, x) bind (c)
       !
       ! void rism_snes (void *ctx, ArrayFunc f,
       !                 int n, real x_[n])
       !
       ! using procedure (c_iterator) or in C-lang ArrayFunc:
       !
       ! typedef void (*ArrayFunc) (void *ctx,
       !                            int n, const real x[n], real r[n]);
       !
       ! See ./bgy3d-snes.c
       !
       use iso_c_binding, only: c_ptr, c_int, c_double
       implicit none
       type (c_ptr), intent (in), value :: ctx
       procedure (c_iterator) :: f
       integer (c_int), intent (in), value :: n
       real (c_double), intent (inout) :: x(n)
     end subroutine rism_snes
  end interface

  !
  ! A pointer to to the structure of this type will serve as a closure
  ! context to be passed to the C-world. Upon callback the Fortran sub
  ! implementing a procedure(c_iterator) can use the procedure pointer
  ! to perform the actual work.  I wish closures could be made simpler
  ! than that.
  !
  type context
     integer :: shape(3)
     procedure (f_iterator), pointer, nopass :: f
  end type context

contains

  subroutine snes_picard (f, x)
    !
    ! Simple Picard iteration
    !
    !   x    = x + α f(x )
    !    n+1    n       n
    !
    implicit none
    procedure (f_iterator) :: f  ! (x) -> dx
    real (rk), intent (inout) :: x(:, :, :)
    ! *** end of interface ***

    real (rk), parameter :: alpha = 0.02
    real (rk) :: dx(size (x, 1), size (x, 2), size (x, 3))
    real (rk) :: diff
    integer :: iter
    logical :: converged

    iter = 0
    converged = .false.
    do while (.not. converged)
       iter = iter + 1

       dx = f (x)

       diff = maxval (abs (dx))
       converged = (diff < 1.0e-12)

       x = x + alpha * dx
       print *, "# iter=", iter, "diff=", diff
    end do
  end subroutine snes_picard


  subroutine snes_default (f, x)
    !
    ! Delegates the actual work to Petsc by way of C-func rism_snes().
    !
    use iso_c_binding, only: c_ptr, c_loc
    implicit none
    procedure (f_iterator) :: f  ! (x) -> dx
    real (rk), intent (inout) :: x(:, :, :)
    ! *** end of interface ***

    type (context), target :: f_ctx
    type (c_ptr) :: ctx

    f_ctx % f => f
    f_ctx % shape = shape (x)
    ctx = c_loc (f_ctx)

    call rism_snes (ctx, iterator, size (x), x)
  end subroutine snes_default


  subroutine iterator (ctx, n, x, dx) bind (c)
    !
    ! Implements  procedure(c_iterator)  and  will  be passed  to  the
    ! rism_snes()   together   with   the   suitable   context.    See
    ! snes_default().
    !
    use iso_c_binding, only: c_f_pointer, c_ptr, c_int
    implicit none
    type (c_ptr), intent (in), value :: ctx
    integer (c_int), intent (in), value :: n
    real (rk), intent (in), target :: x(n)
    real (rk), intent (out), target :: dx(n)
    ! *** end of interface ***

    type (context), pointer :: f_ctx

    ! We  dont  do any  work  ourselves,  just  extract a  pointer  to
    ! procedure(f_iterator) an let it do the rest:
    call c_f_pointer (ctx, f_ctx)

    block
       real (rk), pointer :: y(:, :, :), dy(:, :, :)

       ! F03 way to create aliases:
       associate (n => f_ctx % shape)
         ! F03 pointer association with contiguous array:
         y(1:n(1), 1:n(2), 1:n(3)) => x
         dy(1:n(1), 1:n(2), 1:n(3)) => dx
       end associate

       ! The warning by GF 4.6 and 4.7 is incorrect:
       ! http://gcc.gnu.org/bugzilla/show_bug.cgi?id=55855
       dy = f_ctx % f (y)
    end block
  end subroutine iterator
end module snes


module foreign
  use iso_c_binding, only: c_int, c_double, c_char
  implicit none
  private

  public :: bgy3d_problem_data

  ! Keep this in sync with bgy3d-solutes.h:
  type, public, bind (c) :: site
     character (kind=c_char, len=5) :: name ! atom types. What are they used for?
     real (c_double) :: x(3)                ! coordinates
     real (c_double) :: sigma               ! sigma for LJ
     real (c_double) :: epsilon             ! epsilon for LJ
     real (c_double) :: charge              ! charge
  end type site

  ! Keep this in sync with bgy3d.h:
  type, public, bind (c) :: problem_data
     real (c_double) :: interval(2) ! min and max of the domain: 3d-box
     real (c_double) :: h(3)        ! mesh width
     real (c_double) :: beta        ! inverse temperature, 1/kT
     real (c_double) :: rho         ! solvent density
     integer (c_int) :: N(3), N3    ! global Grid size

     ! Other staff  that was retrieved by the  solvers themselves from
     ! the (Petsc) environment:
     real (c_double) :: lambda   ! Mixing parameter.
     real (c_double) :: damp     ! Scaling factor.
     integer (c_int) :: max_iter ! Maximal number of iterations.
     real (c_double) :: norm_tol ! Convergence threshold.
     real (c_double) :: zpad     ! FIXME: ???
  end type problem_data

  !
  ! These are concrete functions, implemented in C:
  !
  interface
     function bgy3d_problem_data () result (pd) bind (c)
       import problem_data
       implicit none
       type (problem_data) :: pd
     end function bgy3d_problem_data
  end interface
end module foreign


module rism
  use kinds, only: rk
  implicit none
  private

  public :: rism_solvent
  public :: rism_solute
  !
  ! *** END OF INTERFACE ***
  !

  real (rk), parameter :: pi = 4 * atan (1.0_rk)

  !
  ! The interaction energy of two unit charges separated by 1 A is
  !                  -1
  !   E = 1 * 1 / 1 A   = 0.529 au = 332 kcal [/ mol]
  !
  ! The next parameter appears to have the meaning of this interaction
  ! energy of such two unit charges:
  !
  !   EPSILON0INV = 1 / ε₀
  !
  ! and  is  used  to  covert electrostatic  interaction  energies  to
  ! working units.   It has  to be consistent  with other  force field
  ! parameters defined in bgy3d-solvents.h, notably with Lennard-Jones
  ! parameters σ and ε (FIXME: so maybe it was not a good idea to move
  ! it here). These are the original comments:
  !
  !   You have: e^2/4/pi/epsilon0/angstrom, you want: kcal/avogadro/mol
  !
  !   => 331.84164
  !
  ! Again, the code appears to use the IT-calorie to define 1/ε₀. Keep
  ! this in sync with bgy3d.h:
  !
  real (rk), parameter :: EPSILON0INV = 331.84164d0

  !
  ! Inverse range parameter for  separation of the Coulomb into short-
  ! and long range components. The  inverse of this number 1/α has the
  ! dimension of length. FIXME: with the hardwired parameter like this
  ! the  short-range  Coulomb is  effectively  killed alltogether  for
  ! water-like particles  --- a water-like  particle has a  typical LJ
  ! radius σ = 3.16 A. There are no visible changes in the RDF with or
  ! without short range Coulomb and the charges of the order ±1.
  !
  real (rk), parameter :: ALPHA = 1.2

contains

  subroutine rism_solvent (pd, m, solvent) bind (c)
    use iso_c_binding, only: c_int
    use foreign, only: problem_data, site
    implicit none
    type (problem_data), intent (in) :: pd ! no VALUE!
    integer (c_int), intent (in), value :: m
    type (site), intent (in) :: solvent(m)
    ! *** end of interface ***

    integer :: i, nrad
    real (rk) :: rmax
    real (rk) :: rho(m)

    rho = pd % rho              ! all site densities are the same
    rmax = 0.5 * (pd % interval(2) - pd % interval(1))
    nrad = maxval (pd % n)

    print *, "# rho=", pd % rho
    print *, "# beta=", pd % beta
    print *, "# L=", rmax
    print *, "# n=", nrad
    print *, "# Solvent:"
    do i = 1, m
       print *, "#", i, &
            &        pad (solvent(i) % name), &
            &        solvent(i) % sigma, &
            &        solvent(i) % epsilon, &
            &        solvent(i) % charge, &
            &        rho(i)
    enddo

    ! This is applicable to LJ only, and should take reduced
    ! density/temperature:
    ! call print_info (rho = pd % rho, beta = pd % beta)

    call rism_vv (nrad, rmax, pd % beta, rho, solvent)
  end subroutine rism_solvent


  subroutine rism_solute (pd, n, solute, m, solvent) bind (c)
    use iso_c_binding, only: c_int
    use foreign, only: problem_data, site
    implicit none
    type (problem_data), intent (in) :: pd ! no VALUE!
    integer (c_int), intent (in), value :: n, m
    type (site), intent (in) :: solute(n)
    type (site), intent (in) :: solvent(m)
    ! *** end of interface ***

    integer :: i, nrad
    real (rk) :: rmax
    real (rk) :: rho(m)

    rho = pd % rho              ! all site densities are the same
    rmax = 0.5 * (pd % interval(2) - pd % interval(1))
    nrad = maxval (pd % n)

    print *, "# rho=", pd % rho
    print *, "# beta=", pd % beta
    print *, "# L=", rmax
    print *, "# n=", nrad

    print *, "# Solvent:"
    do i = 1, m
       print *, "#", i, &
            &        pad (solvent(i) % name), &
            &        solvent(i) % sigma, &
            &        solvent(i) % epsilon, &
            &        solvent(i) % charge, &
            &        rho(i)
    enddo

    print *, "# Solute:"
    do i = 1, n
       print *, "#", i, &
            &        pad (solute(i) % name), &
            &        solute(i) % sigma, &
            &        solute(i) % epsilon, &
            &        solute(i) % charge
    enddo

    ! This is applicable to LJ only, and should take reduced
    ! density/temperature:
    ! call print_info (rho = pd % rho, beta = pd % beta)

    block
       ! Solvent susceptibility χ = ω + ρh:
       real (rk) :: chi(nrad, m, m)

       call rism_vv (nrad, rmax, pd % beta, rho, solvent, chi)

       call rism_uv (nrad, rmax, pd % beta, rho, solvent, chi, solute)
    end block
  end subroutine rism_solute


  subroutine rism_vv (nrad, rmax, beta, rho, sites, chi)
    use fft, only: fourier, FT_FW, FT_BW
    use snes, only: snes_default
    use foreign, only: site
    implicit none
    integer, intent (in) :: nrad           ! grid size
    real (rk), intent (in) :: rmax         ! cell size
    real (rk), intent (in) :: beta         ! inverse temp
    real (rk), intent (in) :: rho(:)       ! (m)
    type (site), intent (in) :: sites(:)   ! (m)
    real (rk), intent(out) :: chi(:, :, :) ! (nrad, m, m)
    optional :: chi
    ! *** end of interface ***

    real (rk), parameter :: half = 0.5

    ! Pair quantities. FIXME: they are symmetric, one should use that:
    real (rk), dimension (nrad, size (sites), size (sites)) :: &
         v, vk, t, c, g, wk

    ! Radial grids:
    real (rk) :: r(nrad), dr
    real (rk) :: k(nrad), dk

    integer :: i, m

    m = size (sites)

    ! dr * dk = 2π/2n:
    dr = rmax / nrad
    dk = pi / rmax
    forall (i = 1:nrad)
       r(i) = (i - half) * dr
       k(i) = (i - half) * dk
    end forall

    ! Tabulate short-range  pairwise potentials v() on  the r-grid and
    ! long-range pairwise potential vk() on the k-grid:
    call force_field (sites, sites, r, k, v, vk)

    ! Rigid-bond correlations on the k-grid:
    wk = omega_fourier (sites, k)

    ! Intitial guess:
    t = 0.0

    ! Find t such that iterate_t  (t) == 0. FIXME: passing an internal
    ! function as a callback is an F08 feature. GFortran 4.3 on Debian
    ! Lenny does not support that:
    call snes_default (iterate_t, t)

    ! Do not assume c has a meaningfull value, it was overwritten with
    ! c(k):
    c = closure_hnc (beta, v, t)
    g = 1 + c + t

    !
    ! When requested  by the caller return the  susceptibility χ(k) in
    ! Fourier rep:
    !
    if (present (chi)) then
       block
          integer :: i, j
          do i = 1, m
             do j = 1, m
                chi(:, i, j) = wk(:, i, j) + &
                     rho(i) * fourier (c(:, i, j) + t(:, i, j)) * (dr**3 / FT_FW)
             enddo
          enddo
       end block
    endif

    ! Done with it, print results:
    block
       integer :: p, i, j
       real  (rk) :: cl(nrad, m, m)
       real  (rk) :: mu_dens(nrad), mu

       ! Real-space rep of the long-range correlation:
       forall (p = 1:nrad, i = 1:m, j = 1:m)
          cl(p, i, j) = -beta * sites(i) % charge * sites(j) % charge &
               * EPSILON0INV * coulomb_long (r(p), ALPHA)
       end forall

       ! Chemical potential to be integrated:
       mu_dens = chempot_density (rho, c + t, c, cl)
       mu = 4 * pi * sum (r**2 * mu_dens) * dr / beta

       print *, "# rho=", rho, "beta=", beta, "n=", nrad
       print *, "# mu=", mu, "(kcal)"
       print *, "# r, and v, t, c, g, each for m * (m + 1) / 2 pairs, then mu"
       do p = 1, nrad
          write (*, *) r(p), &
               &     ((v(p, i, j), i=1,j), j=1,m), &
               &     ((t(p, i, j), i=1,j), j=1,m), &
               &     ((c(p, i, j), i=1,j), j=1,m), &
               &     ((g(p, i, j), i=1,j), j=1,m), &
               &       4 * pi * r(p)**2 * mu_dens(p)

       enddo
    end block

  contains

    function iterate_t (t) result (dt)
      !
      ! Closure over  host variables: r, k,  dr, dk, v,  c, beta, rho,
      ! ... Implements procedure(f_iterator).
      !
      implicit none
      real (rk), intent (in) :: t(:, :, :) ! (n, m, m)
      real (rk) :: dt(size (t, 1), size (t, 2), size (t, 3))
      ! *** end of interface ***

      integer :: i, j

      c = closure_hnc (beta, v, t)

      ! Forward FT via DST:
      do j = 1, size (c, 3)
         do i = 1, size (c, 2)
            c(:, i, j) = fourier (c(:, i, j)) * (dr**3 / FT_FW)
         enddo
      enddo

      !
      ! The  real-space representation  encodes  only the  short-range
      ! part  of  the  direct   corrlation.  The  (fixed)  long  range
      ! contribution is added here:
      !
      !   C := C  - βV
      !         S     L
      !
      c = c - beta * vk

      !
      ! OZ equation, involves "convolutions", take care of the
      ! normalization here:
      !
      dt = oz_vv_equation_c_t (rho, c, wk)

      !
      ! Since we plugged  in the Fourier transform of  the full direct
      ! correlation including the long range part into the OZ equation
      ! what we get out is the full indirect correlation including the
      ! long-range part.  The menmonic is  C + T is short range.  Take
      ! it out:
      !
      !   T  := T - βV
      !    S          L
      !
      dt = dt - beta * vk

      ! Inverse FT via DST:
      do j = 1, size (dt, 3)
         do i = 1, size (dt, 2)
            dt(:, i, j) = fourier (dt(:, i, j)) * (dk**3 / FT_BW)
         enddo
      enddo

      ! Return the increment that vanishes at convergence:
      dt = dt - t
    end function iterate_t
  end subroutine rism_vv


  subroutine rism_uv (nrad, rmax, beta, rho, solvent, chi, solute)
    use fft, only: fourier, FT_FW, FT_BW
    use snes, only: snes_default
    use foreign, only: site
    implicit none
    integer, intent (in) :: nrad           ! grid size
    real (rk), intent (in) :: rmax         ! cell size
    real (rk), intent (in) :: beta         ! inverse temp
    real (rk), intent (in) :: rho(:)       ! (m)
    type (site), intent (in) :: solvent(:) ! (m)
    real (rk), intent(in) :: chi(:, :, :)  ! (nrad, m, m)
    type (site), intent (in) :: solute(:)  ! (n)
    ! *** end of interface ***

    real (rk), parameter :: half = 0.5

    ! Solute-solvent pair quantities:
    real (rk), dimension (nrad, size (solute), size (solvent)) :: &
         v, vk, t, c, g

    ! Solute-solute pair quantities:
    real (rk), dimension (nrad, size (solute), size (solute)) :: &
         wk

    ! Radial grids:
    real (rk) :: r(nrad), dr
    real (rk) :: k(nrad), dk

    integer :: i, m, n

    n = size (solute)
    m = size (solvent)

    ! dr * dk = 2π/2n:
    dr = rmax / nrad
    dk = pi / rmax
    forall (i = 1:nrad)
       r(i) = (i - half) * dr
       k(i) = (i - half) * dk
    end forall

    ! Tabulate short-range  pairwise potentials v() on  the r-grid and
    ! long-range pairwise potential vk() on the k-grid:
    call force_field (solute, solvent, r, k, v, vk)

    ! Rigid-bond solute-solute correlations on the k-grid:
    wk = omega_fourier (solute, k)

    ! Intitial guess:
    t = 0.0

    ! Find t such that iterate_t  (t) == 0. FIXME: passing an internal
    ! function as a callback is an F08 feature. GFortran 4.3 on Debian
    ! Lenny does not support that:
    call snes_default (iterate_t, t)

    ! Do not assume c has a meaningfull value, it was overwritten with
    ! c(k):
    c = closure_hnc (beta, v, t)
    g = 1 + c + t

    ! Done with it, print results:
    block
       integer :: p, i, j
       real  (rk) :: cl(nrad, n, m)
       real  (rk) :: mu_dens(nrad), mu

       ! Real-space rep of the long-range correlation:
       forall (p = 1:nrad, i = 1:n, j = 1:m)
          cl(p, i, j) = -beta * solute(i) % charge * solvent(j) % charge &
               * EPSILON0INV * coulomb_long (r(p), ALPHA)
       end forall

       ! Chemical potential to be integrated:
       mu_dens = chempot_density (rho, c + t, c, cl)
       mu = 4 * pi * sum (r**2 * mu_dens) * dr / beta

       print *, "# rho=", rho, "beta=", beta, "n=", nrad
       print *, "# mu=", mu, "(kcal)"
       print *, "# r, and v, t, c, g, each for m * n pairs, then mu"
       do p = 1, nrad
          write (*, *) r(p), &
               &     ((v(p, i, j), i=1,n), j=1,m), &
               &     ((t(p, i, j), i=1,n), j=1,m), &
               &     ((c(p, i, j), i=1,n), j=1,m), &
               &     ((g(p, i, j), i=1,n), j=1,m), &
               &       4 * pi * r(p)**2 * mu_dens(p)

       enddo
    end block

  contains

    function iterate_t (t) result (dt)
      !
      ! Closure over  host variables: r, k,  dr, dk, v,  c, beta, rho,
      ! ... Implements procedure(f_iterator).
      !
      implicit none
      real (rk), intent (in) :: t(:, :, :) ! (n, m, m)
      real (rk) :: dt(size (t, 1), size (t, 2), size (t, 3))
      ! *** end of interface ***

      integer :: i, j

      c = closure_hnc (beta, v, t)

      ! Forward FT via DST:
      do j = 1, size (c, 3)
         do i = 1, size (c, 2)
            c(:, i, j) = fourier (c(:, i, j)) * (dr**3 / FT_FW)
         enddo
      enddo

      !
      ! The  real-space representation  encodes  only the  short-range
      ! part  of  the  direct   corrlation.  The  (fixed)  long  range
      ! contribution is added here:
      !
      !   C := C  - βV
      !         S     L
      !
      c = c - beta * vk

      !
      ! OZ equation, involves "convolutions", take care of the
      ! normalization here:
      !
      dt = oz_uv_equation_c_t (c, wk, chi)

      !
      ! Since we plugged  in the Fourier transform of  the full direct
      ! correlation including the long range part into the OZ equation
      ! what we get out is the full indirect correlation including the
      ! long-range part.  The menmonic is  C + T is short range.  Take
      ! it out:
      !
      !   T  := T - βV
      !    S          L
      !
      dt = dt - beta * vk

      ! Inverse FT via DST:
      do j = 1, size (dt, 3)
         do i = 1, size (dt, 2)
            dt(:, i, j) = fourier (dt(:, i, j)) * (dk**3 / FT_BW)
         enddo
      enddo

      ! Return the increment that vanishes at convergence:
      dt = dt - t
    end function iterate_t
  end subroutine rism_uv


  function omega_fourier (sites, k) result (wk)
    !
    ! The  intra-molecular force-field  amounts to  rigid  bonds. This
    ! function computes the Fourier representation
    !
    !   ω(k) = sinc (kR)
    !
    ! of the corresponding δ-like correlation functions:
    !
    !   ω(r) = δ(r - R) / 4πR²
    !
    use foreign, only: site
    implicit none
    type (site), intent (in) :: sites(:)                  ! (m)
    real (rk), intent (in) :: k(:)                        ! (n)
    real (rk) :: wk(size (k), size (sites), size (sites)) ! (n, m, m)
    ! *** end of inteface ***

    real (rk) :: xa(3), xb(3), rab
    integer :: i, j, m

    m = size (sites)

    ! Site-site bond lengths are derived from site coordinates:
    do j = 1, m
       xb = sites(j) % x
       do i = 1, m
          xa = sites(i) % x

          ! Site-site distance vanishes (at least) for i == j, so that
          ! sinc(kr) == 1 in this case. NORM2() is an F08 intrinsic.
          rab = norm2 (xa - xb)

          ! Rigid bond correlation on a k-grid:
          wk(:, i, j) = sinc (k * rab)
       enddo
    enddo

  contains

    elemental function sinc (x) result (f)
      implicit none
      real (rk), intent (in) :: x
      real (rk) :: f
      ! *** end of interface ***

      if (x == 0.0) then
         f = 1.0
      else
         f = sin (x) / x
      endif
    end function sinc
  end function omega_fourier


  subroutine force_field (asites, bsites, r, k, vr, vk)
    !
    ! Force field  is represented by two contributions,  the first one
    ! is (hopefully) of short range and is returned in array vr on the
    ! r-grid. The other term is  then of long range and, naturally, is
    ! represented by array vk on the k-grid.
    !
    use foreign, only: site
    implicit none
    type (site), intent (in) :: asites(:)  ! (m)
    type (site), intent (in) :: bsites(:)  ! (n)
    real (rk), intent (in) :: r(:)         ! (nrad)
    real (rk), intent (in) :: k(:)         ! (nrad)
    real (rk), intent (out) :: vr(:, :, :) ! (nrad, m, n)
    real (rk), intent (out) :: vk(:, :, :) ! (nrad, m, n)
    ! *** end of inteface ***

    real (rk) :: epsilon, sigma, charge
    integer :: i, j
    type (site) :: a, b

    ! LJ potential:
    do j = 1, size (bsites)
       b = bsites(j)
       do i = 1, size (asites)
          a = asites(i)

          epsilon = sqrt (a % epsilon * b % epsilon)
          sigma = (a % sigma + b % sigma) / 2
          charge = a % charge * b % charge

          ! Short range on the r-grid:
          if (sigma /= 0.0) then
             vr(:, i, j) = epsilon * lj (r / sigma) + &
                  EPSILON0INV * charge * coulomb_short (r, ALPHA)
          else
             vr(:, i, j) = &
                  EPSILON0INV * charge * coulomb_short (r, ALPHA)
          endif

          ! Long range on the k-grid:
          vk(:, i, j) = &
               EPSILON0INV * charge * coulomb_long_fourier (k, ALPHA)
       enddo
    enddo

  contains

    elemental function lj (r) result (f)
      !
      ! To be called as in eps * lj (r / sigma)
      !
      implicit none
      real (rk), intent (in) :: r   ! r / sigma, in general
      real (rk) :: f
      ! *** end of interfce ***

      real (rk) :: sr6

      sr6 = 1 / r**6

      f = 4 * sr6 * (sr6 - 1)
    end function lj
  end subroutine force_field


  !
  ! In the most general case
  !
  !   coulomb_long (r, a) = (1/ε₀) erf (a r) / r
  !
  ! The corresponding Fourier transform is
  !
  !   coulomb_long_fourier (k, a) = (4π/ε₀) exp (- k² / 4a²) / k²
  !
  ! Note that the long-range Coulomb is regular in real space:
  !
  !   erf(x) / x = 2 / √π - 2x² / 3√π + O(x⁴)
  !
  ! So that for a typical value of a = 1.2 the long range potential at r
  ! = 0  is 331.84164 * 1.2 *  1.12837916709551 ~ 449 kcal  for two unit
  ! charges. By doing a finite-size FFT of the k-gitter appriximation of
  ! the  above  Fourier representation  you  will  likely get  something
  ! different.
  !
  elemental function coulomb_long_fourier (k, alpha) result (f)
    implicit none
    real (rk), intent (in) :: k, alpha
    real (rk) :: f
    ! *** end of interface ***

    if (k == 0.0) then
       f = 0.0                  ! 1/k² is undefined
    else
       f = 4 * pi * exp (-k**2 / (4 * alpha**2)) / k**2
    endif
  end function coulomb_long_fourier


  elemental function coulomb_long (r, alpha) result (f)
    !
    ! It is unlikely that you  need this function as as the long-range
    ! interactions are  best specified  on the k-grid  and not  on the
    ! r-grid. See coulomb_long_fourier() instead.
    !
    implicit none
    real (rk), intent (in) :: r, alpha
    real (rk) :: f
    ! *** end of interface ***

    ! ERF() is F08 and later:
    if (r == 0.0) then
       f = alpha * 2 / sqrt (pi)
    else
       f = erf (alpha * r) / r
    endif
  end function coulomb_long


  elemental function coulomb_short (r, alpha) result (f)
    implicit none
    real (rk), intent (in) :: r, alpha
    real (rk) :: f
    ! *** end of interface ***

    ! This will return infinity for r = 0. ERFC() is F08 and later:
    f = erfc (alpha * r) / r
  end function coulomb_short


  !
  ! 1)  Hypernetted Chain  (HNC)  closure relation  to compute  direct
  ! correlation function c  in real space.  See OZ  equation below for
  ! the   second  relation   between  two   unknowns.    The  indirect
  ! correlation γ = h - c is denoted by latin "t" in other sources. We
  ! will  use  that to  avoid  greek  identifiers  and confusion  with
  ! distribution functions:
  !
  !   c := exp (-βv + γ) - 1 - γ
  !
  elemental function closure_hnc (beta, v, t) result (c)
    implicit none
    real (rk), intent (in) :: beta, v, t
    real (rk) :: c
    ! *** end of interface ***

    ! exp (-beta * v + t) - 1.0 - t:
    c = exp (-beta * v + t) - 1 - t
  end function closure_hnc


  !
  ! Use the k-representation of Ornstein-Zernike (OZ) equation
  !
  !   h = c + ρ c * h
  !
  ! to compute γ =  h - c form c:
  !
  !                -1                -1   2
  !   γ =  (1 - ρc)   c - c = (1 - ρc)  ρc
  !
  ! If you scale c by h3 beforehand  or pass rho' = rho * h3 and scale
  ! the result  by h3 in addition,  you will compute  exactly what the
  ! older version of the function did:
  !
  function oz_vv_equation_c_t (rho, C, W) result (T)
    implicit none
    real (rk), intent (in) :: rho(:)             ! (m)
    real (rk), intent (in) :: C(:, :, :)         ! (n, m, m)
    real (rk), intent (in) :: W(:, :, :)         ! (n, m, m)
    real (rk) :: T(size (C, 1), size (C, 2), size (C, 3))
    ! *** end of interface ***

    integer :: i

    ! There is  no reason to  handle the 1x1 case  differently, except
    ! clarity.  The MxM branch should be able to handle that case too.
    if (size (rho) == 1) then
       ! FIXME: it  is implied here  that W =  1. See comments  on the
       ! value of ω(k) for i == j in omega_fourier().
       do i = 1, size (C, 1)
          T(i, 1, 1) = oz_vv_equation_c_t_1x1 (rho(1), C(i, 1, 1))
       enddo
    else
       do i = 1, size (C, 1)
          T(i, :, :) = oz_vv_equation_c_t_MxM (rho(:), C(i, :, :), W(i, :, :))
       enddo
    endif
  end function oz_vv_equation_c_t


  elemental function oz_vv_equation_c_t_1x1 (rho, c) result (t)
    implicit none
    real (rk), intent (in) :: rho, c
    real (rk) :: t
    ! *** end of interface ***

    !
    ! The actual (matrix) expression
    !
    !                  -1
    !   t = (1 - ρ * c)  * c - c
    !
    ! simplifies in the 1x1 case to this:
    !
    t = rho * (c * c) / (1 - rho * c)
  end function oz_vv_equation_c_t_1x1


  function oz_vv_equation_c_t_MxM (rho, C, W) result (T)
    !
    ! So far  rho is the same for  all sites, we may  have mixed left-
    ! and right-side multiplies.
    !
    ! RISM equation, here for h and c:
    !
    !   h = ω * c * ω + ρ ω * c * h
    !
    ! or
    !                    -1
    !   h = (1 - ρ ω * c)   * ω * c * ω
    !
    ! To use  this code for  mixtures of otherwise  uncorrelated sites
    ! supply  unity matrix  for  ω. A  mixture  of molecular  solvents
    ! should  be represented  by  an ω-matrix  with  a suitable  block
    ! structure.
    !
    implicit none
    real (rk), intent (in) :: rho(:)  ! (m)
    real (rk), intent (in) :: C(:, :) ! (m, m)
    real (rk), intent (in) :: W(:, :) ! (m, m)
    real (rk) :: T(size (rho), size (rho)) ! (m, m)
    ! *** end of interface ***

    real (rk), dimension (size (rho), size (rho)) :: H
    integer :: i, j, m

    m = size (rho)

    ! H := WC, temporarily:
    H = matmul (W, C)

    ! T := 1  - ρWC. The output matrix  T is used here as  a free work
    ! array:
    forall (i = 1:m, j = 1:m)
       T(i, j) = delta (i, j) - rho(i) * H(i, j)
    end forall

    ! H := WCW.  Still temporarily --- it will be overwritten with the
    ! real H after solving the linear equations.
    H = matmul (H, W)

    !
    ! Solving the linear equation makes  H have the literal meaning of
    ! the total correlation matrix (input T is destroyed):
    !
    !       -1                 -1
    ! H := T   * H == (1 - ρWC)   * WCW
    !
    call sles (m, T, H)         ! FIXME: copy in/out.

    !
    ! The  same  effect  is  achieved  in  1x1  version  of  the  code
    ! differently:
    !
    ! T := H - C
    !
    T = H - C

  contains

    pure function delta (i, j) result (d)
      implicit none
      integer, intent (in) :: i, j
      integer :: d
      ! *** end of interface ***

      if (i == j) then
         d = 1
      else
         d = 0
      endif
    end function delta

    subroutine sles (m, a, b)
      !
      ! Solve linear equations  A X = B. As in LAPACK  the matrix A is
      ! destroyed and the result is returned in B.
      !
      implicit none
      integer, intent (in) :: m
      real (rk), intent (inout) :: a(m, m), b(m, m)
      ! *** end of interface ***

      integer :: ipiv(m), info

      ! B will  be overwriten with  the result, A will  be overwritten
      ! with its factorization:
      call dgesv (m, m, a, m, ipiv, b, m, info)

      if (info /= 0) then
         block
            integer :: i
            print *, "a="
            do i = 1, m
               print *, a(i, :)
            enddo
            print *, "b="
            do i = 1, m
               print *, b(i, :)
            enddo
            print *, "info=", info
         end block
         stop "dgesv failed, see tty"
      endif
    end subroutine sles
  end function oz_vv_equation_c_t_MxM


  function oz_uv_equation_c_t (cuv, wuu, xvv) result (tuv)
    implicit none
    real (rk), intent (in) :: cuv(:, :, :)         ! (nrad, n, m)
    real (rk), intent (in) :: wuu(:, :, :)         ! (nrad, n, n)
    real (rk), intent (in) :: xvv(:, :, :)         ! (nrad, m, m)
    real (rk) :: tuv(size (cuv, 1), size (cuv, 2), size (cuv, 3))
    ! *** end of interface ***

    integer :: p

    ! Many associative matrix multiplies: NxN * (NxM * MxM)
    do p = 1, size (cuv, 1)
       tuv(p, :, :) = matmul (wuu(p, :, :), matmul (cuv(p, :, :), xvv(p, :, :))) - cuv(p, :, :)
    enddo
  end function oz_uv_equation_c_t


  subroutine print_info (rho, beta)
    !
    ! van der Hoef (Ref. [6] Eqs. 25 and 26):
    !
    !          -1/4                          2         3         4         5
    ! ρ      =β    [0.92302-0.09218β+0.62381β -0.82672β +0.49124β -0.10847β ]
    !  solid
    !          -1/4                          2         3         4         5
    ! ρ      =β    [0.91070-0.25124β+0.85861β -1.08918β +0.63932β -0.14433β ]
    !  liquid
    !
    ! Mastny and de Pablo (Ref [7] Eqs. 20 and 21):
    !
    !          -1/4                             2          3          4          5
    ! ρ      =β    [0.908629-0.041510β+0.514632β -0.708590β +0.428351β -0.095229β ]
    !  solid
    !          -1/4                          2         3         4         5
    ! ρ      =β    [0.90735-0.27120β+0.91784β -1.16270β +0.68012β -0.15284β ]
    !  liquid
    !
    implicit none
    real (rk), intent (in) :: rho, beta
    ! *** end of interface ***

    real (rk), parameter :: &
         psol_hoef(6) = [0.92302d0, -0.09218d0, +0.62381d0, -0.82672d0, +0.49124d0, -0.10847d0], &
         pliq_hoef(6) = [0.91070d0, -0.25124d0, +0.85861d0, -1.08918d0, +0.63932d0, -0.14433d0], &
         psol_mast(6) = [0.908629d0, -0.041510d0, +0.514632d0, -0.708590d0, +0.428351d0, -0.095229d0], &
         pliq_mast(6) = [0.90735d0, -0.27120d0, +0.91784d0, -1.16270d0, +0.68012d0, -0.15284d0]

    print *, "# rho =", rho, "rs =", (4 * pi * rho / 3)**(-1d0/3d0)
    print *, "# beta =", beta, "T =", 1 / beta
    print *, "#"
    print *, "# At this temperature ..."
    print *, "#"
    print *, "# According to Hoef"
    print *, "# rho solid  =", beta**(-0.25d0) * poly (psol_hoef, beta)
    print *, "# rho liquid =", beta**(-0.25d0) * poly (pliq_hoef, beta)
    print *, "#"
    print *, "# According to Mastny and de Pablo"
    print *, "# rho solid  =", beta**(-0.25d0) * poly (psol_mast, beta)
    print *, "# rho liquid =", beta**(-0.25d0) * poly (pliq_mast, beta)
    print *, "#"

  contains

    function poly (p, x) result (y)
      implicit none
      real (rk), intent (in) :: p(0:), x
      real (rk) :: y
      ! *** end of interface ***

      integer :: n

      y = 0.0
      do n = 0, size (p) - 1
         y = y + p(n) * x**n
      enddo
    end function poly
  end subroutine print_info

  function pad (s) result (t)
    use iso_c_binding, only: c_null_char
    implicit none
    character (len=*), intent (in) :: s
    character (len=len (s)) :: t
    ! *** end of interface ***

    integer :: i

    t = s
    do i = 1, len (t)
       if (t(i:i) /= c_null_char) cycle
       t(i:) = " "
       exit
    enddo
  end function pad

  function chempot_density (rho, h, cs, cl) result (mu)
    !
    ! Returns the β-scaled "density" of the chemical potential, βμ(r).
    ! To  get the  excess  chemical potential  integrate  it over  the
    ! volume and divide by β, cf.:
    !
    !   βμ = 4πρ ∫ [½h²(r) - c(r) - ½h(r)c(r)] r²dr
    !
    ! The first h²-term in the definition of the chemical potential is
    ! of  short  range  and  should  not present  any  difficulty  for
    ! integration.
    !
    ! Assuming that the long-range component of the direct correlation
    ! c₁₂(r)  of two sites,  1 and  2, is  proportional to  the charge
    ! product q₁ and  q₂ as in -βq₁q₂v(r) one may  deduce that ρ₁c₁₁ +
    ! ρ₂c₂₁ vanishes identically for  *neutral* systems.  In this case
    ! the Coulomb tails of the direct correlation in the second c-term
    ! do not  contribute to  the chemical potential.   This is  a good
    ! thing, because otherwise an integral 4π∫r²dr/r would diverge.
    !
    ! The third  hc-term is of the  short range due to  h. However the
    ! long-range  Coulomb-type correction  to the  direct correlation,
    ! since weighted  by a pair  specific total correlation  h₁₂, does
    ! not vanish in such a sum.
    !
    ! To get an idea about the order of magnitude of such a long-range
    ! correction: for  SPC/E water  with σ(H) =  1.0 A, ε(H)  = 0.0545
    ! kcal  [1],  and using  the  short-range  correlation with  range
    ! separation  parameter α  = 1.2  A^-1 gives  the  excess chemical
    ! potential μ = 6.86 kcal (wrong because positive!).  By including
    ! the long  range correlation into  the hc-term one  obtains -4.19
    ! kcal instead.  Here N = 4096, L  = 80 A, ρ = 0.033427745 A^-3, β
    ! = 1.6889 kcal^-1.
    !
    ! Note  that,   contrary  to  what  is  being   suggested  in  the
    ! literature, these  numbers depend strongly on  the LJ parameters
    ! of hydrogens. With σ(H) = 0.8  A and ε(H) = 0.046 kcal [Leipzig]
    ! one gets  μ = -4.97  kcal and  with σ(H) =  1.1656 A and  ε(H) =
    ! 0.01553  kcal [Amber] one  gets μ  = -3.66  kcal.  At  least one
    ! source  quotes  yet a  different  number  -3.41  kcal [1].   The
    ! corresponding result for modified TIP3P water with σ(H) = 0.4 A,
    ! and ε(H) = 0.046 kcal is -6.35 kcal.
    !
    ! FIXME: what do we do for charged systems?
    !
    ! [1] "Comparative  Study on Solvation Free  Energy Expressions in
    !     Reference Interaction Site  Model Integral Equation Theory",
    !     Kazuto   Sato,  Hiroshi   Chuman,   and  Seiichiro   Ten-no,
    !     J.  Phys.   Chem.  B,   2005,  109  (36),   pp  17290–17295,
    !     http://dx.doi.org/10.1021/jp053259i
    !
    implicit none
    real (rk), intent (in) :: rho(:)      ! (m)
    real (rk), intent (in) :: h(:, :, :)  ! (nrad, n, m)
    real (rk), intent (in) :: cs(:, :, :) ! (nrad, n, m)
    real (rk), intent (in) :: cl(:, :, :) ! (nrad, n, m)
    real (rk) :: mu(size (h, 1))
    ! *** end of interface ***

    integer :: p, i, j
    real (rk) :: muH, muS, muL

    do p = 1, size (h, 1)       ! nrad
       muH = 0.0
       muS = 0.0
       muL = 0.0
       do j = 1, size (h, 3)    ! m
          do i = 1, size (h, 2) ! n
             muH = muH + rho(j) * h(p, i, j)**2 / 2

             muS = muS + rho(j) * (-cs(p, i, j) - h(p, i, j) * cs(p, i, j) / 2)
             muL = muL + rho(j) * (             - h(p, i, j) * cl(p, i, j) / 2)
          enddo
       enddo

       mu(p) = muH + muS + muL
    enddo
  end function chempot_density
end module rism
