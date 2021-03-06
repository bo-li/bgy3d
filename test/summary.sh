#!/bin/bash

# receive file name from input
file=$1

# Get charge
grep "integrated charge" $file | tail -1

grep "charge of solvent medium" $file | tail -1
grep "charge of solute charge density" $file | tail -1

# Get dipoles
grep "dipole moment of solute cores" $file | tail -1
grep "dipole moment of solute charge density" $file | tail -1

grep "dipole moment of solvent medium" $file | tail -1

# Get energy.  Interaction between point nuclei with solvent potential
grep "with solute point nuclei" $file | tail -1

# Interaction between diffuse solute charge density with solvent
# potential
grep "diffuse charge density" $file | tail -1

# Interaction between solvent charge density with solute electrostatic
# potential
grep "with long-range electrostatic" $file | tail -1

# Energy from PG
grep -A1 "Total energy of solute with solvent" $file | tail -2

# Excess chemical potential in RISM/HNC3D calculations:
grep "mu =" $file

# This is to satisfy GNU Make:
exit 0
