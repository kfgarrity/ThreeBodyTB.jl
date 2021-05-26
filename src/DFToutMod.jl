#include("Crystal.jl")


"""
    module DFToutMod

Deal with energy, force, stress, band structure, etc, from a DFT calculation

Generic to different DFT codes.
"""
module DFToutMod

#using LinearAlgebra
using ..CrystalMod:crystal
using ..CrystalMod:makecrys
using ..CrystalMod:orbital_index
using Printf


using ..ThreeBodyTB:convert_energy
using ..ThreeBodyTB:convert_force
using ..ThreeBodyTB:convert_stress
using ..ThreeBodyTB:global_energy_units

##using Formatting

export dftout
export makedftout
#export test
export test2
#export crystal
#export makecrys
#export generate_supercell
#export generate_random
#export write_poscar
#export write_efs



#holds data
"""
    mutable struct bandstructure

Band structure. Has

- `nbnd::Int` Number of bands
- `nks::Int` Number of k-points
- `nelec::Float64` Number of electrons
- `efermi::Float64` Fermi energy
- `kpts::Array{Float64,2}` List of k-points, `nks × 3` array in BZ crystal units.
- `kweights::Array{Float64,1}` Weights of k-points (`nks`).
- `kgrid::Array{Int,1}` Equivalent gamma centered Monkhorst-Pack k-grid dimensions, if applies.
- `eigs::Array{Float64,2}` Eigenvalues. `nks × nbnd`

"""
mutable struct bandstructure
    nbnd::Int
    nks::Int
    nelec::Float64
    efermi::Float64
    kpts::Array{Float64,2}
    kweights::Array{Float64,1}
    kgrid::Array{Int,1}
    eigs::Array{Float64,2}
end

"""
    mutable struct dftout

DFT output struct. Has

- `crys::crystal`  crystal structure
- `energy::Float64` the actual DFT energy, depends on pseudopotentials.
- `energy_smear::Float64` smearing energy
- `forces::Array{Float64,2}` forces Ryd / a.u.
- `stress::Array{Float64,2}` stress  Ryd / (a.u.)^3
- `bandstruct::bandstructure` See bandstructure struct
- `hasband::Bool` does this object have a band structure, usually `true`
- `hasham::Bool` not used, always `false`
- `prefix::String`  A string has a name used to find output files.
- `outdir::String` Directly loaded from
- `tot_charge::Float64` If charge of unit cell is nonzero
- `atomize_energy::Float64` Atomization energy, relative to non-spin-polarized atoms.
"""
mutable struct dftout

    crys::crystal
    energy::Float64
    energy_smear::Float64
    forces::Array{Float64,2}
    stress::Array{Float64,2}
    bandstruct::bandstructure
    hasband::Bool
    hasham::Bool    
    prefix::String
    outdir::String
    tot_charge::Float64
    atomize_energy::Float64

end

"""
    function get_atomize_energy(d::dftout)

Return atomization energy in current energy units
"""
function get_atomize_energy(d::dftout)

    return convert_energy(d.atomize_energy)

end

#printing
Base.show(io::IO, d::dftout) = begin
#    println(io)
#    for i in 1:3
#        @printf(io, "A%.1i=     % .5f  % .5f  % .5f\n", i, d.crys.A[i,1],  d.crys.A[i,2],  d.crys.A[i,3])
#    end
    println(io, d.crys)


    println(io)
    println("Energy (direct from dft) ", d.energy, " Ryd")
    println(io)    
    println(io,"STRUCTURE =====================| FORCES =================")
    println(io)

    forces = convert_force(d.forces)
    
    for i in 1:d.crys.nat
        @printf(io, "%-3s  % .5f  % .5f  % .5f | % .5f % .5f % .5f\n", d.crys.types[i], d.crys.coords[i,1], d.crys.coords[i,2], d.crys.coords[i,3], forces[i,1], forces[i,2], forces[i,3])
    end
    println(io,)
    println(io,"=========================================================")
    println(io)
    println(io,"STRESS ==================")

    stress = convert_stress(d.stress)
    
    @printf(io, "\n")
    for i in 1:3
        @printf(io, "% .5f  % .5f  % .5f\n", stress[i,1], stress[i,2], stress[i,3])        
    end
    println(io,)
    println(io, "Atomization energy (no spin): ", convert_energy(d.atomize_energy), " $global_energy_units ")
    println(io,"=========================")
    println(io,"Has bandstructure: ", d.hasband,"; Has hamiltonian: ", d.hasham)
    println(io)
    
end   

#print bandstructure
Base.show(io::IO, d::bandstructure) = begin
    println(io,"nbnd = ", d.nbnd, "; nkpts = ", d.nks)
    println(io,"nelec = ", d.nelec, "; efermi = ", d.efermi)

    println(io)

#    pst = "{:d} {: f} {: f} {: f} , {: f},  "
#    pst = "%-3s % .5f % .5f % .5f , % .5f, "
#    println(pst)

    for i = 1:min(d.nks, 200)
        t = @sprintf("%-3s", i)
        k = @sprintf(" [ % .5f % .5f % .5f ]", d.kpts[i,1],d.kpts[i,2],d.kpts[i,3]  )
        kw = @sprintf(" % .5f ",  d.kweights[i])
        v = " "
        for j = 1:d.nbnd
            v = v * @sprintf(" % .5f",d.eigs[i,j]) 
        end
        println(io,t,kw,k,v)

    end
    if d.nks > 200
        println(io, "... [truncated]")
    end
    println(io)
    
end   

"""
    function makebs(nelec::Number, efermi::Number,  kpoints, kweights,kgrid, vals)

Constructor for `bandstructure`.
"""
function makebs(nelec::Number, efermi::Number,  kpoints, kweights,kgrid, vals)
    try
        kpoints = convert(Array{Float64,2},kpoints)
        kweights = convert(Array{Float64,1}, kweights)
        vals = convert(Array{Float64,2}, vals)
    catch
        println(typeof(kpoints), typeof(kweights), typeof(vals))
        error("error make bs type conversion")
    end
    nks = size(kpoints,1)
    if nks != size(kweights,1) || nks != size(vals,1)
        error("kpoints kweights eigs don't match")
    end
    nbnd = size(vals,2)

    K2 = zeros(Float64,size(kpoints))
    for i in 1:nks
        K2[i,:] = Int64.(round.(kpoints[i,:] * 100000000))/100000000
    end


    return bandstructure(nbnd, nks, nelec, efermi, K2, kweights, kgrid, vals)

end

function make_empty_bs()
    
    return bandstructure(1, 1, 1, 0.0, zeros(1,3), zeros(3), [1, 1, 1], zeros(1,1))

end

"""
    function makedftout(crys::crystal, energy::Number, energy_smear::Number,  forces, stress, bandstruct=missing; prefix="PREFIX", outdir="TMPDIR", tot_charge=0.0)

Constructor for dftout. Usually called by function that loads DFT output files, not called directly.
"""
function makedftout(crys::crystal, energy::Number, energy_smear::Number,  forces, stress, bandstruct=missing; prefix="PREFIX", outdir="TMPDIR", tot_charge=0.0)
"""
Creates a struct with the desired data
"""
    try
        forces = convert(Array{Float64,2}, forces)
        stress = convert(Array{Float64,2}, stress)
        energy = convert(Float64, energy)
        energy_smear = convert(Float64, energy_smear)
    catch
        println(typeof(energy), typeof(forces), typeof(stress))
        error("Error converting types")
        return
    end
        
    nat = crys.nat
    if (nat,3) != size(forces)
        println( forces)
        error("Error forces")

        return
    end
    if size(stress) != (3,3)
        println( stress)
        error("Error stress", size(stress))
        return
    end

    ind2orb, orb2ind, etotal_atoms, nval =  orbital_index(crys)
    atomize_energy = energy - etotal_atoms
    
                
    
    if ismissing(bandstruct)
        return dftout(crys, energy, energy_smear, forces, stress, make_empty_bs() , false, false, prefix, outdir, tot_charge, atomize_energy) #, missing, False, False)
    else
        return dftout(crys, energy, energy_smear,forces, stress, bandstruct, true, false, prefix, outdir, tot_charge, atomize_energy) #, missing, False, False)
    end    
end

#alterate version, will make the crys for you.
"""
    function makedftout(A, pos, types, energy::Number,energy_smear::Number,  forces, stress, bandstruct=missing; prefix="PREFIX", outdir="TMPDIR", tot_charge=0.0)
"""
function makedftout(A, pos, types, energy::Number,energy_smear::Number,  forces, stress, bandstruct=missing; prefix="PREFIX", outdir="TMPDIR", tot_charge=0.0)
    c = makecrys(A,pos,types, units="Bohr")
    if ismissing(bandstruct)
        return makedftout(c, energy, energy_smear, forces,stress, prefix=prefix, outdir=outdir, tot_charge=0.0)
    else
        return makedftout(c, energy, energy_smear, forces,stress, bandstruct,prefix=prefix, outdir=outdir, tot_charge=0.0)
    end
end


end #end module


#using .DFToutMod
#Base.:(==)(x::dftout, y::dftout) = (x.crys == y.crys && x.energy == y.energy && x.forces == y.forces && x.stress ==y.stress)
