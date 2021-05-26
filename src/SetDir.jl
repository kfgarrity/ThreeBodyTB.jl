#directory info

SRCDIR = dirname(pathof(ThreeBodyTB))
EXAMPLESDIR = joinpath(dirname(pathof(ThreeBodyTB)), "..", "examples")
TESTDIR = joinpath(dirname(pathof(ThreeBodyTB)), "..", "test")
TEMPLATEDIR = joinpath(dirname(pathof(ThreeBodyTB)), "..", "template_inputs")
STRUCTDIR = joinpath(dirname(pathof(ThreeBodyTB)), "..", "reference_structures")

DATSDIR1 = joinpath(dirname(pathof(ThreeBodyTB)), "..", "dats", "pbesol", "v1.2")

#DATSDIR1 = joinpath(dirname(pathof(ThreeBodyTB)), "..", "dats", "pbesol", "v0.9")

#DATSDIR1 = joinpath(dirname(pathof(ThreeBodyTB)), "..", "dats", "pbesol", "v0.4")

DATSDIR2 = joinpath(dirname(pathof(ThreeBodyTB)), "..", "dats", "pbesol", "v1.0")

DOCSDIR = joinpath(dirname(pathof(ThreeBodyTB)), "..", "docs")


#DATSDIR1 = "/home/kfg/codes/TB_fit/fit_dimer/datab_2/"
#DATSDIR2 = ""

#DATSDIR2 = "/home/kfg/codes/TB_fit/binary_v10/datab/"
