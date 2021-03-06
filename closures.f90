module closures
  !
  ! FIXME:  public  functions expect  the  inverse  temperature β  but
  ! internally we operate with potential in units of temperature, βv.
  !
  ! Copyright (c) 2013, 2014 Alexei Matveev
  ! Copyright (c) 2013 Bo Li
  !
  use kinds, only: rk
  implicit none
  private

  ! Elemental functions:
  public :: expm1
  public :: closure, closure1
  public :: closure_rbc
  public :: chempot_form, chempot_form1
  public :: chempot, chempot1

  ! These are bind (c), used from C only, therefore public. Interfaces
  ! in rism.h.
  public :: rism_closure
  public :: rism_chempot_density
  public :: rism_chempot_density1
  ! *** END OF INTERFACE ***

contains

  subroutine rism_closure (method, beta, n, v, t, c) bind (c)
    !
    ! This one is for using from the C-side. Note that Fortran forbids
    ! aliasing between the output c and the input v and t.
    !
    ! Should be consistent with ./rism.h
    !
    use iso_c_binding, only: c_int, c_double
    implicit none
    integer (c_int), intent (in), value :: method, n
    real (c_double), intent (in), value :: beta
    real (c_double), intent (in) :: v(n), t(n)
    real (c_double), intent (out) :: c(n)
    ! *** end of interface ***

    c = closure (method, beta, v, t)
  end subroutine rism_closure


  subroutine rism_closure1 (method, beta, n, v, t, dt, dc) bind (c)
    !
    ! This one is for using from the C-side. Note that Fortran forbids
    ! aliasing between the output c and the input v and t.
    !
    ! Should be consistent with ./rism.h
    !
    use iso_c_binding, only: c_int, c_double
    implicit none
    integer (c_int), intent (in), value :: method, n
    real (c_double), intent (in), value :: beta
    real (c_double), intent (in) :: v(n), t(n), dt(n)
    real (c_double), intent (out) :: dc(n)
    ! *** end of interface ***

    dc = closure1 (method, beta, v, t, dt)
  end subroutine rism_closure1


  subroutine rism_chempot_density (method, n, x, h, c, cl, mu) bind (c)
    !
    ! This one is for using from the C-side. Note that Fortran forbids
    ! aliasing between the output mu and the input x, h, c, cl.
    !
    ! Should be consistent with ./rism.h
    !
    use iso_c_binding, only: c_int, c_double
    implicit none
    integer (c_int), intent (in), value :: method, n
    real (c_double), intent (in) :: x(n), h(n), c(n), cl(n)
    real (c_double), intent (out) :: mu(n)
    ! *** end of interface ***

    ! Elemental  function  form() encodes  the  form  of the  chemical
    ! potential integrand.
    mu = form (method, x, h, c, cl)
  end subroutine rism_chempot_density


  subroutine rism_chempot_density1 (method, n, x, dx, h, dh, c, dc, cl, dm) bind (c)
    !
    ! This one is for using from the C-side. Note that Fortran forbids
    ! aliasing between the output dm and the input.
    !
    ! Should be consistent with ./rism.h
    !
    use iso_c_binding, only: c_int, c_double
    implicit none
    integer (c_int), intent (in), value :: method, n
    real (c_double), intent (in) :: x(n), dx(n), h(n), dh(n), c(n), dc(n), cl(n)
    real (c_double), intent (out) :: dm(n)
    ! *** end of interface ***

    ! Elemental  function  form1()  encodes  the differential  of  the
    ! chemical potential integrand.
    dm = form1 (method, x, dx, h, dh, c, dc, cl)
  end subroutine rism_chempot_density1


  elemental function closure (method, beta, v, t) result (c)
    use foreign, only: HNC => CLOSURE_HNC, KH => CLOSURE_KH, PY => CLOSURE_PY, &
         PSE0 => CLOSURE_PSE0, PSE7 => CLOSURE_PSE7
    implicit none
    integer, intent (in) :: method
    real (rk), intent (in) :: beta, v, t
    real (rk) :: c
    ! *** end of interface ***

    select case (method)
    case (HNC)
       c = closure_hnc (beta * v, t)
    case (KH)
       c = closure_kh (beta * v, t)
    case (PY)
       c = closure_py (beta * v, t)
    case (PSE0:PSE7)
       c = closure_pse (order (method), beta * v, t)
    case default
       c = huge (c)            ! FIXME: cannot abort in pure functions
    end select
  end function closure


  elemental function closure1 (method, beta, v, t, dt) result (dc)
    use foreign, only: HNC => CLOSURE_HNC, KH => CLOSURE_KH, &
         PSE0 => CLOSURE_PSE0, PSE7 => CLOSURE_PSE7
    implicit none
    integer, intent (in) :: method
    real (rk), intent (in) :: beta, v, t, dt
    real (rk) :: dc
    ! *** end of interface ***

    ! FIXME: some are not yet implemented:
    select case (method)
    case (HNC)
       dc = closure_hnc1 (beta * v, t, dt)
    case (KH)
       dc = closure_kh1 (beta * v, t, dt)
    ! case (PY)
    !    dc = closure_py1 (beta * v, t, dt)
    case (PSE0:PSE7)
       dc = closure_pse1 (order (method), beta * v, t, dt)
    case default
       dc = huge (dc)          ! FIXME: cannot abort in pure functions
    end select
  end function closure1


  pure function order (method) result (n)
    use foreign, only: HNC => CLOSURE_HNC, KH => CLOSURE_KH, &
         PSE0 => CLOSURE_PSE0, PSE7 => CLOSURE_PSE7
    implicit none
    integer, intent (in) :: method
    integer :: n
    ! *** end of interface ***

    select case (method)
    case (HNC)
       n = huge (n)             ! infinite order
    case (KH)
       n = 1
    case (PSE0:PSE7)
       n = method - PSE0
    case default
       n = -1                   ! FIXME: what should it be?
    end select
  end function order


  elemental function expm1 (x) result (f)
    !
    ! Elemental version of libc expm1().
    !
    use foreign, only: c_expm1 => expm1
    implicit none
    real (rk), intent (in) :: x
    real (rk) :: f
    ! *** end of interface ***

    f = c_expm1 (x)
  end function expm1


  pure function exps1 (n, x) result (y)
    !
    ! Truncated  exponential  series,  an  expansion for  exp(x)  -  1
    ! employed by PSE-n and KH closures:
    !
    !                    k
    !           n       x       x     n      n!   k-1
    !   f(x) = Σ       ----  = ----  Σ      ---- x
    !           k = 1   k!      n!    k = 1  k!
    !
    ! otherwise. The alternative expression  has the advantage that we
    ! can  start with  the coefficient  of the  highest  power without
    ! having to compute it first.  Will silently accept negative n and
    ! for finite input x will return zero just as as for n = 0.
    !
    implicit none
    integer, intent (in) :: n
    real (rk), intent (in) :: x
    real (rk) :: y
    ! *** end of interface ***

    ! FIXME: specialize for  n = 0, 1, 2  where y = 0, x,  x + x**2/2,
    ! maybe?
    real (rk) :: c
    integer :: k

    ! Horner scheme:
    c = 1.0            ! n!/n!, leading coefficient
    y = 0.0
    do k = n, 1, -1    ! iterate n times
       y =  x * y + c
       c = c * k       ! n!/(k-1)!
       !
       ! At this point in each round:
       !
       ! 1) y = 1
       ! 2) y == x + n, i.e. two terms
       ! 3) y == x(x + n) + n(n-1), i.e. three terms
       !
       ! ...
       !         n-1      n-2
       ! n) y = x    +  nx    +  ...  +  n!, all n terms
    enddo
    ! Here c = n!:
    y = (x / c) * y
  end function exps1


  !
  ! 1)  Hypernetted Chain  (HNC)  closure relation  to compute  direct
  ! correlation function c in real space.  The OZ equation (elsewhere)
  ! is  the second relation  between the  two unknowns.   The indirect
  ! correlation t = h - c is denoted by greek "γ" in other sources. We
  ! will avoid greek identifiers utill better times.
  !
  !   c = exp (-βv + t) - 1 - t
  !
  pure function closure_hnc (v, t) result (c)
    implicit none
    real (rk), intent (in) :: v, t
    real (rk) :: c
    ! *** end of interface ***

    ! c = exp (-beta * v + t) - 1 - t
    c = expm1 (-v + t) - t
  end function closure_hnc


  pure function closure_hnc1 (v, t, dt) result (dc)
    implicit none
    real (rk), intent (in) :: v, t, dt
    real (rk) :: dc
    ! *** end of interface ***

    ! dc = [exp (-beta * v + t) - 1] dt
    dc = expm1 (-v + t) * dt
  end function closure_hnc1


  !
  ! 2)  Kovalenko-Hirata (KH)  closure.   Same as  HNC in  "depletion"
  ! regions but avoids exponential grows:
  !
  !        / exp (-βv + t) - 1 - t, if -βv + t <= 0
  !   c = <
  !        \ -βv, otherwise
  !
  pure function closure_kh (v, t) result (c)
    implicit none
    real (rk), intent (in) :: v, t
    real (rk) :: c
    ! *** end of interface ***

    real (rk) :: x

    x = -v + t

    ! For x  <= 0 use  exp(x) - 1,  but do not grow  exponentially for
    ! positive x:
    if (x <= 0.0) then
       c = expm1 (x) - t
    else
       c = -v
    endif
  end function closure_kh


  pure function closure_kh1 (v, t, dt) result (dc)
    implicit none
    real (rk), intent (in) :: v, t, dt
    real (rk) :: dc
    ! *** end of interface ***

    real (rk) :: x

    x = -v + t

    ! For x  <= 0 use  exp(x) - 1,  but do not grow  exponentially for
    ! positive x:
    if (x <= 0.0) then
       ! dc = [exp (-beta * v + t) - 1] dt
       dc = expm1 (x) * dt
    else
       dc = 0.0
    endif
  end function closure_kh1


  ! 3)  Percus-Yevick  (PY)   closure  relation  between  direct-  and
  ! indirect correlation c and t:
  !
  !   c := exp (-βv) [1 + t] - 1 - t
  pure function closure_py (v, t) result (c)
    implicit none
    real (rk), intent (in) :: v, t
    real (rk) :: c
    ! *** end of interface ***

    c = exp (-v) * (1 + t) - 1 - t
  end function closure_py


  elemental function closure_rbc (method, beta, v, t, expB) result (c)
    use foreign, only: HNC => CLOSURE_HNC
    implicit none
    integer, intent (in) :: method
    real (rk), intent (in) :: beta, v, t, expB
    real (rk) :: c
    ! *** end of interface ***

    select case (method)
    ! RBC only with HNC now
    case (HNC)
       c = closure_hnc_rbc (beta * v, t, expB)
    case default
       c = huge (c)            ! FIXME: cannot abort in pure functions
    end select
  end function closure_rbc

  !
  ! HNC closure with repulsive bridge correction:
  !
  !    c := exp (-βv + t + B) - 1 - t
  !
  pure function closure_hnc_rbc (v, t, expB) result (c)
    implicit none
    real (rk), intent (in) :: v, t, expB
    real (rk) :: c
    ! *** end of interface ***

    c = exp (-v + t) * expB - 1 - t
  end function closure_hnc_rbc


  pure function closure_pse (n, v, t) result (c)
    implicit none
    integer, intent (in) :: n
    real (rk), intent (in) :: v, t ! v in temperature units
    real (rk) :: c
    ! *** end of interface ***

    real (rk) :: x

    x = -v + t

    ! For x < 0 f(x) = exp(x) - 1, but does not grow exponentially for
    ! positive x. E.g. for n = 1, and x >= 0 f(x) = x, so that c = x -
    ! t = -v.  FIXME: should we rather  code c = -v + [f(x) - x] where
    ! the term in brackets is o(x²) for small x?
    c = pse (n, x) - t

  end function closure_pse


  pure function closure_pse1 (n, v, t, dt) result (dc)
    !
    ! Suffix 1 here indicated the differential, not the order.
    !
    implicit none
    integer, intent (in) :: n
    real (rk), intent (in) :: v, t, dt
    real (rk) :: dc
    ! *** end of interface ***

    real (rk) :: x

    x = -v + t

    ! For x <= 0 use [exp(x) -  1] * dt, but do not grow exponentially
    ! for positive x. For n <= 1 and x >= 0 this will return zero:
    dc = pse (n - 1, x) * dt
  end function closure_pse1


  pure function pse (n, x) result (y)
    !
    ! This combination of an  exponential and power series is employed
    ! by PSE-n and KH closures:
    !
    !   f(x) = exp(x) - 1  if x < 0
    !
    ! and
    !                    k
    !           n       x
    !   f(x) = Σ       ----
    !           k = 1   k!
    !
    ! otherwise.  Will silently accept negative n and behaves as for n
    ! = 0.
    !
    implicit none
    integer, intent (in) :: n
    real (rk), intent (in) :: x
    real (rk) :: y
    ! *** end of interface ***

    if (x < 0.0) then
       y = expm1 (x)
    else
       y = exps1 (n, x)
    endif
  end function pse

  !
  ! Chemical Potential (ChemPot).
  !
  ! The next  function, chempot_density(), returns  the scaled density
  ! of the  chemical potential, βμ(r)/ρ.   To get the  excess chemical
  ! potential integrate it over the volume and multiply by ρ/β, cf.:
  !
  !   βμ/ρ = 4π ∫ [½h²(r) - c(r) - ½h(r)c(r)] r²dr
  !
  ! The first h²-term  in the definition of the  chemical potential is
  ! of  short  range  and   should  not  present  any  difficulty  for
  ! integration.
  !
  ! Assuming that  the long-range component of  the direct correlation
  ! c₁₂(r)  of two  sites,  1 and  2,  is proportional  to the  charge
  ! product q₁  and q₂ as  in -βq₁q₂v(r) one  may deduce that  ρ₁c₁₁ +
  ! ρ₂c₂₁ vanishes  identically for  *neutral* systems.  In  this case
  ! the Coulomb tails  of the direct correlation in  the second c-term
  ! do  not contribute  to the  chemical  potential.  This  is a  good
  ! thing, because otherwise an integral 4π∫r²dr/r would diverge.
  !
  ! The third  hc-term is  of the  short range due  to h.  However the
  ! long-range  Coulomb-type  correction  to the  direct  correlation,
  ! since weighted by a pair  specific total correlation h₁₂, does not
  ! vanish in such a sum.
  !
  ! To get an  idea about the order of magnitude  of such a long-range
  ! correction: for SPC/E water with σ(H)  = 1.0 A, ε(H) = 0.0545 kcal
  ! [1], and  using the short-range correlation  with range separation
  ! parameter α  = 1.2  A^-1 gives the  excess chemical potential  μ =
  ! 6.86 kcal (wrong because  positive!).  By including the long range
  ! correlation into the hc-term one obtains -4.19 kcal instead.  Here
  ! N = 4096, L = 80 A, ρ = 0.033427745 A^-3, β = 1.6889 kcal^-1. (You
  ! may  need  to  use   --snes-solver  "trial"  to  get  SPC/E  water
  ! converge).
  !
  ! Note that, contrary to what  is being suggested in the literature,
  ! these   numbers  depend   strongly   on  the   LJ  parameters   of
  ! hydrogens. With σ(H)  = 0.8 A and ε(H) =  0.046 kcal [Leipzig] one
  ! gets μ =  -4.97 kcal and with  σ(H) = 1.1656 A and  ε(H) = 0.01553
  ! kcal [Amber] one gets μ =  -3.66 kcal.  At least one source quotes
  ! yet a  different number -3.41 kcal [1].   The corresponding result
  ! for modified TIP3P water with σ(H)  = 0.4 A, and ε(H) = 0.046 kcal
  ! is -6.35 kcal.
  !
  ! Kast and Kloss [2] generalized the expression for any closure that
  ! can be expressed in the form
  !
  !   h = f(x)
  !
  ! with x = -βv + t.   The quantity x is called renormalized indirect
  ! correlation  t* in  Ref.   [2].   For this  type  of closures  the
  ! expression for chemical potential is
  !
  !          HNC                 x(r)
  !   βμ = βμ   + 4πρ ∫ {h(r) - ∫    [1 + f(y)] dy} r²dr
  !                              0
  !
  ! cp.  Eq.   (12) in Ref.  [2].   Note how in HNC  case the definite
  ! integral of  1 + f(y) =  exp(y) gives exp(x) -  1 = h  so that the
  ! addition is void. The closures PSE series are of the required form
  !
  !   h = f (x)
  !        n
  !
  ! Indeed,  these closures  employ  a power  series approximation  to
  ! exp(x)  -  1  for  positive  x  but  otherwise  are  the  same  as
  ! HNC. Therefore  in the depletion regions  where x(r) <  0 (that is
  ! where h(r) < 0) the integrand of the additional term vanishes just
  ! as in HNC case. Elsewhere the integrand of the additional term is
  !
  !          n+1
  !         x
  !    - ρ ------
  !        (n+1)!
  !
  ! cp. Eq. (16)  in Ref. [2]. Note that 4πr²dr  is the volume element
  ! and is not  part of the integrand here. In the  case of KH closure
  ! (n = 1) the integrand in these regions  with x > 0 (that is h > 0)
  ! can  be  written as  -ρh²/2,  because  by  virtue of  the  closure
  ! relation  h  = x  in  these  regions.   This additional  integrand
  ! cancels  the  h²-term in  the  HNC  expression  everywhere but  in
  ! depletion regions.
  !
  ! For higher  order PSE-n closures  it is impractical to  derive the
  ! value of  the additional  term from the  usual suspects, h  and c,
  ! participating  in   the  HNC  and  KH   expressions  for  chemical
  ! potential.   So that  the  most general  expression  will have  to
  ! include the renormalized indirect correlation x = -βv + t as well.
  !
  ! FIXME: the code assumes that  the long range direct correlation is
  ! strictly proportional to the product of the site charges!
  !
  ! [1] "Comparative Study on Solvation Free Energy Expressions in
  !     Reference Interaction Site Model Integral Equation Theory",
  !     Kazuto Sato, Hiroshi Chuman, and Seiichiro Ten-no, J.  Phys.
  !     Chem.  B, 2005, 109 (36), pp 17290–17295,
  !     http://dx.doi.org/10.1021/jp053259i
  !
  ! [2] "Closed-form expressions of the chemical potential for
  !     integral equation closures with certain bridge functions",
  !     Kast, Stefan M. and Kloss, Thomas, J. Chem. Phys., 2008, 129,
  !     236101, http://dx.doi.org/10.1063/1.3041709

  pure recursive function factorial (n) result (y)
    !
    ! Used  for coefficients in  expresisons involving  PSE-n closures
    ! with  0  <=  n <=  7.   FIXME:  should  we  hardwire them  on  a
    ! case-by-case basis?
    !
    implicit none
    integer, intent (in) :: n
    integer :: y
    ! *** end interface ***

    select case (n)
    case (0)
       y = 1
    case (1)
       y = 1
    case (2)
       y = 1 * 2
    case (3)
       y = 1 * 2 * 3
    case (4)
       y = 1 * 2 * 3 * 4
    case (5)
       y = 1 * 2 * 3 * 4 * 5
    case (6)
       y = 1 * 2 * 3 * 4 * 5 * 6
    case (7)
       y = 1 * 2 * 3 * 4 * 5 * 6 * 7
    case (8)
       y = 1 * 2 * 3 * 4 * 5 * 6 * 7 * 8
    case default
       y = n * factorial (n - 1)
    end select
  end function factorial


  elemental function form (method, x, h, c, cl) result (mu)
    use foreign, only: HNC => CLOSURE_HNC, KH => CLOSURE_KH, PY => CLOSURE_PY, &
         PSE0 => CLOSURE_PSE0, PSE7 => CLOSURE_PSE7
    implicit none
    integer, intent (in) :: method
    real (rk), intent (in) :: x, h, c, cl
    real (rk) :: mu
    ! *** end of interface ***

    select case (method)
    case (HNC)
       mu = - c - h * (c + cl) / 2 + h**2 / 2
    case (KH)
       if (h < 0) then
          mu = - c - h * (c + cl) / 2 + h**2 / 2
       else
          mu = - c - h * (c + cl) / 2
       endif
    case (PY)
       mu = - c - h * (c + cl) / 2
    case (PSE0:PSE7)
       if (h < 0) then
          mu = - c - h * (c + cl) / 2 + h**2 / 2
       else
          block
             integer :: m, mx

             m = order (method) + 1 ! n + 1
             mx = factorial (m)     ! (n + 1)!

             ! Note that  the h**2  and x**(n+1) terms  cancel exactly
             ! for n = 1 and h = x:
             mu = - c - h * (c + cl) / 2 + (h**2 / 2 - x**m / mx)
          end block
       endif
    case default
       mu = huge (mu)          ! FIXME: cannot abort in pure functions
    end select
  end function form


  elemental function form1 (method, x, dx, h, dh, c, dc, cl) result (dm)
    use foreign, only: HNC => CLOSURE_HNC, KH => CLOSURE_KH, PY => CLOSURE_PY, &
         PSE0 => CLOSURE_PSE0, PSE7 => CLOSURE_PSE7
    implicit none
    integer, intent (in) :: method
    real (rk), intent (in) :: x, dx, h, dh, c, dc, cl
    real (rk) :: dm
    ! *** end of interface ***

    select case (method)
    case (HNC)
       dm = - dc - dh * (c + cl) / 2 - h * dc / 2 + h * dh
    case (KH)
       if (h < 0) then
          dm = - dc - dh * (c + cl) / 2 - h * dc / 2 + h * dh
       else
          dm = - dc - dh * (c + cl) / 2 - h * dc / 2
       endif
    case (PY)
       dm = - dc - dh * (c + cl) / 2 - h * dc / 2
    case (PSE0:PSE7)
       if (h < 0) then
          dm = - dc - dh * (c + cl) / 2 - h * dc / 2 + h * dh
       else
          block
             integer :: n, nx

             n = order (method) ! n
             nx = factorial (n) ! n!

             ! Note that the dh**2  and dx**(n+1) terms cancel exactly
             ! for n = 1 and h = x:
             dm = - dc - dh * (c + cl) / 2 - h * dc / 2 + (h * dh - x**n * dx / nx)
          end block
       endif
    case default
       dm = huge (dm)          ! FIXME: cannot abort in pure functions
    end select
  end function form1


  function chempot_density (method, x, h, c, cl) result (mu)
    !
    ! Returns the scaled density of the chemical potential, βμ(r)/ρ.
    !
    implicit none
    integer, intent (in) :: method        ! HNC, KH, or anything else
    real (rk), intent (in) :: x(:, :, :)  ! (n, m, nrad)
    real (rk), intent (in) :: h(:, :, :)  ! (n, m, nrad)
    real (rk), intent (in) :: c(:, :, :)  ! (n, m, nrad)
    real (rk), intent (in) :: cl(:, :, :) ! (n, m, nrad)
    real (rk) :: mu(size (h, 3))
    ! *** end of interface ***

    integer :: i, j, p
    real (rk) :: acc

    do p = 1, size (h, 3)       ! nrad
       acc = 0.0
       do j = 1, size (h, 2)    ! m
          do i = 1, size (h, 1) ! n
             acc = acc + &
                  form (method, x(i, j, p), h(i, j, p), c(i, j, p), cl(i, j, p))
          enddo
       enddo
       mu(p) = acc
    enddo
  end function chempot_density


  function chempot_density1 (method, x, dx, h, dh, c, dc, cl) result (dmu)
    !
    ! Differential of chempot_density().
    !
    implicit none
    integer, intent (in) :: method        ! HNC, KH, or anything else
    real (rk), intent (in) :: x(:, :, :)  ! (n, m, nrad)
    real (rk), intent (in) :: dx(:, :, :) ! (n, m, nrad)
    real (rk), intent (in) :: h(:, :, :)  ! (n, m, nrad)
    real (rk), intent (in) :: dh(:, :, :) ! (n, m, nrad)
    real (rk), intent (in) :: c(:, :, :)  ! (n, m, nrad)
    real (rk), intent (in) :: dc(:, :, :) ! (n, m, nrad)
    real (rk), intent (in) :: cl(:, :, :) ! (n, m, nrad)
    real (rk) :: dmu(size (h, 3))
    ! *** end of interface ***

    integer :: i, j, p
    real (rk) :: acc

    do p = 1, size (h, 3)       ! nrad
       acc = 0.0
       do j = 1, size (h, 2)    ! m
          do i = 1, size (h, 1) ! n
             acc = acc + &
                  form1 (method, &
                  x(i, j, p), dx(i, j, p), &
                  h(i, j, p), dh(i, j, p), &
                  c(i, j, p), dc(i, j, p), &
                  cl(i, j, p))
          enddo
       enddo

       dmu(p) = acc
    enddo
  end function chempot_density1


  function chempot_form (method, x, h, c, cl) result (mu)
    !
    ! Computes the  chemical potential, βμ/ρ, by  integration over the
    ! volume:
    !
    !   βμ/ρ = 4π ∫ [½h²(r) - c(r) - ½h(r)c(r)] r²dr
    !
    ! Here dr == 1, scale the result by dr³ if that is not the case.
    !
    use fft, only: integrate
    implicit none
    integer, intent (in) :: method        ! HNC, KH, or anything else
    real (rk), intent (in) :: x(:, :, :)  ! (n, m, nrad)
    real (rk), intent (in) :: h(:, :, :)  ! (n, m, nrad)
    real (rk), intent (in) :: c(:, :, :)  ! (n, m, nrad)
    real (rk), intent (in) :: cl(:, :, :) ! (n, m, nrad)
    real (rk) :: mu
    ! *** end of interface ***

    ! Inegrate chemical potential  density.  Multiply that by (ρ/β)dr³
    ! and to get the real number:
    mu = integrate (chempot_density (method, x, h, c, cl))
  end function chempot_form


  function chempot_form1 (method, x, dx, h, dh, c, dc, cl) result (dmu)
    !
    ! Differential of chempot_form()
    !
    use fft, only: integrate
    implicit none
    integer, intent (in) :: method        ! HNC, KH, or anything else
    real (rk), intent (in) :: x(:, :, :)  ! (n, m, nrad)
    real (rk), intent (in) :: dx(:, :, :) ! (n, m, nrad)
    real (rk), intent (in) :: h(:, :, :)  ! (n, m, nrad)
    real (rk), intent (in) :: dh(:, :, :) ! (n, m, nrad)
    real (rk), intent (in) :: c(:, :, :)  ! (n, m, nrad)
    real (rk), intent (in) :: dc(:, :, :) ! (n, m, nrad)
    real (rk), intent (in) :: cl(:, :, :) ! (n, m, nrad)
    real (rk) :: dmu
    ! *** end of interface ***

    dmu = integrate (chempot_density1 (method, x, dx, h, dh, c, dc, cl))
  end function chempot_form1


  function chempot (method, rmax, beta, rho, v, vl, t) result (mu)
    !
    ! Computes  the  chemical  potential,  μ(t)  using  the  specified
    ! method. Note  that the  same method is  used to derive  c(t) and
    ! h(t) and to define the functional μ[h, c].
    !
    use fft, only: mkgrid
    implicit none
    integer, intent (in) :: method        ! HNC, KH, or anything else
    real (rk), intent (in) :: rmax, beta, rho
    real (rk), intent (in) :: v(:, :, :)  ! (n, m, nrad)
    real (rk), intent (in) :: vl(:, :, :) ! (n, m, nrad)
    real (rk), intent (in) :: t(:, :, :)  ! (n, m, nrad)
    real (rk) :: mu
    ! *** end of interface ***

    integer :: n, m, nrad

    n = size (t, 1)
    m = size (t, 2)
    nrad = size (t, 3)

    block
      real (rk) :: r(nrad), k(nrad), dr, dk
      real (rk) :: x(n, m, nrad)
      real (rk) :: h(n, m, nrad)
      real (rk) :: c(n, m, nrad)
      real (rk) :: cl(n, m, nrad)

      ! FIXME: only dr is really necessary for integration:
      call mkgrid (rmax, r, dr, k, dk)

      ! Real-space rep of the short range correlation:
      c = closure (method, beta, v, t)

      ! Real-space rep of the long range correlation:
      cl = - beta * vl

      ! Total correlation h = g - 1:
      h = c + t

      ! Renormalized indirect correlation:
      x = - beta * v + t

      ! This   evaluates  method-specific   functional   μ[h,  c]   from
      ! pre-computed h and c:
      mu = chempot_form (method, x, h, c, cl) * (rho * dr**3 / beta)
    end block
  end function chempot


  function chempot1 (method, rmax, beta, rho, v, vl, t, dt) result (dmu)
    !
    ! Differential of chempot()
    !
    use fft, only: mkgrid
    implicit none
    integer, intent (in) :: method        ! HNC, KH, or anything else
    real (rk), intent (in) :: rmax, beta, rho
    real (rk), intent (in) :: v(:, :, :)  ! (n, m, nrad)
    real (rk), intent (in) :: vl(:, :, :) ! (n, m, nrad)
    real (rk), intent (in) :: t(:, :, :)  ! (n, m, nrad)
    real (rk), intent (in) :: dt(:, :, :) ! (n, m, nrad)
    real (rk) :: dmu
    ! *** end of interface ***

    integer :: n, m, nrad

    n = size (t, 1)
    m = size (t, 2)
    nrad = size (t, 3)

    block
      real (rk) :: r(nrad), k(nrad), dr, dk
      real (rk) :: x(n, m, nrad), dx(n, m, nrad)
      real (rk) :: h(n, m, nrad), dh(n, m, nrad)
      real (rk) :: c(n, m, nrad), dc(n, m, nrad)
      real (rk) :: cl(n, m, nrad)

      ! FIXME: only dr is really necessary for integration:
      call mkgrid (rmax, r, dr, k, dk)

      ! Real-space rep of the short range correlation:
      c = closure (method, beta, v, t)
      dc = closure1 (method, beta, v, t, dt)

      ! Real-space rep of the long range correlation:
      cl = - beta * vl

      ! Total correlation h = g - 1:
      h = c + t
      dh = dc + dt

      ! Renormalized indirect correlation:
      x = - beta * v + t
      dx = dt

      ! This   evaluates  method-specific   functional   μ[h,  c]   from
      ! pre-computed h and c:
      dmu = chempot_form1 (method, x, dx, h, dh, c, dc, cl) * (rho * dr**3 / beta)
    end block
  end function chempot1

end module closures
