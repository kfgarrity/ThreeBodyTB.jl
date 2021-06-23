# Fitting tight-binding coefficients from Quantum Espresso.

ThreeBodyTB has a set of prefit coefficients that are sufficient for
running elemental or binary sytems without doing your own fitting. If
you still want to do the fitting yourself, read on...

Currently, ThreeBodyTB is set up to fit coefficients from [Quantum
Espresso](https://www.quantum-espresso.org/) DFT calculations using
the projwfc.x to get atomic wavefunction projected band structures.

A brief overview of the steps:

0) Setup src/Atomdata.jl with non-spin-polarized atomic calculations
for the EXC functional and pseudopotentails and plane-wave convergence
parameters you are using. The version in the code is set up for
the slightly modifed [GBRV](https://www.physics.rutgers.edu/gbrv/)
pseudopotentials available in this distribution.

1) Run self-consistent-field (SCF) non-spin-polarized DFT total energy
calculations.

2) Run `ThreeBodyTB.AtomicProj.projwfx_workf` to get k-space tight-binding models for each
SCF calculation. This runs a non-scf DFT calculation with `pw.x` and atomic projections with `projwfc.x`, and then calculates the TB model.

3) Run the fitting code `TightlyBound.FitTB.do_fitting_recursive`

## Preliminaries



