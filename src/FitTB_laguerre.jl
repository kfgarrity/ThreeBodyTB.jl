module FitTB
"""
Fit tight binding using Laguere polynomials times decaying exponentials
"""

#using PyPlot
using Plots
#using JLD
using LinearAlgebra
#using Statistics
using Optim
using Random
#using Calculus
using DelimitedFiles
using ..TB:calc_energy
using ..TB:calc_energy_fft
#using ..TB:orbital_index
using ..CrystalMod:orbital_index
using ..TB:Hk
using ..BandTools:band_energy
using ..BandTools:gaussian
using ..BandTools:smearing_energy
using ..BandTools:calc_fermi

using ..CrystalMod:get_grid
using ..TB:myfft
using ..TB:myfft_R_to_K
using ..TB:calc_energy_fft
using ..TB:trim

using ..TB:make_tb
using ..TB:make_tb_crys
using ..TB:tb_crys
using ..TB:tb_crys_kspace
using ..TB:ewald_energy
using ..TB:types_energy
using ..TB:get_h1
using ..TB:get_dq

#using ..CalcTB:calc_tb_prepare
using ..CalcTB:calc_tb_prepare_fast
using ..CalcTB:calc_frontier
using ..CalcTB:calc_frontier_list
#using ..CalcTB:calc_tb
using ..CalcTB:calc_tb_fast
using ..CalcTB:make_coefs
using ..CalcTB:coefs
using ..TB:tb_indexes


#using ..CrystalMod:orbital_index

#using ..TB:get_grid

#include("Atomdata.jl")

#=
function do_fitting_renorm(list_of_tbcs; kpoints = [0 0 0; 0 0 0.5; 0 0.5 0.5; 0.5 0.5 0.5], atoms_to_fit=missing, fit_threebody=false , do_plot=true)

    println("AAAAAAAAAAAAAAAAA - START S")
    database = do_fitting(list_of_tbcs; kpoints=kpoints ,  atoms_to_fit=missing, fit_threebody=false, do_plot=false)
    println("AAAAAAAAAAAAAAAAA - START R")
    tbc_renorm = []
    for tbc in list_of_tbcs
        tbc_calc =  calc_tb(tbc.crys, database, use_threebody=false)
        tbc_r = convert_H_S(tbc, tbc_calc)
        push!(tbc_renorm, tbc_r)
    end
    println("AAAAAAAAAAAAAAAAA - START FINAL")

    database = do_fitting(tbc_renorm; kpoints=kpoints ,  atoms_to_fit=missing, fit_threebody=fit_threebody, do_plot=do_plot)
    return tbc_renorm, database
    
end
=#

"""
    function do_fitting(list_of_tbcs; kpoints = missing,  atoms_to_fit=missing, fit_threebody=true, fit_threebody_onsite=true, do_plot = true)

Used for simple linear fitting of coefficients. Interface for more complicated fitting.

- `list_of_tbcs` - List of `tbc_crys` or tbc_crys_k` objects to fit to.
- `dft_list` - for kspace fitting, use 
- `fit_threebody=true` - Fit threebody coefficients. Sometimes `false` for testing, but `true` for production.
- `fit_threebody_onsite=true` - Fit threebody onsite coefficients. See above.
- `do_plot=true` - show simple plot comparing coefficients to tbc reference.
"""
function do_fitting(list_of_tbcs; fit_threebody=true, fit_threebody_onsite=true, do_plot = true)

    ret = do_fitting_linear(list_of_tbcs; fit_threebody=fit_threebody, fit_threebody_onsite = fit_threebody_onsite, do_plot = do_plot)
    return ret[1]

end

"""
    function prepare_for_fitting(list_of_tbcs; kpoints = missing, dft_list = missing, fit_threebody=false, fit_threebody_onsite=false, starting_database=missing, refit_database=missing)

Make lots of preperations for fitting. Moves things around, put stuff in materices, etc.
"""
function prepare_for_fitting(list_of_tbcs; kpoints = missing, dft_list = missing, fit_threebody=false, fit_threebody_onsite=false, starting_database=missing, refit_database=missing)


    tbc_list = []
    tbc_list_real = []
    for (c, tbc) in enumerate(list_of_tbcs)
        println(typeof(tbc))
        if ismissing(tbc) || typeof(tbc) == tb_crys_kspace{Float64}
            println("calc fake tbc")
            tbc_fake = calc_tb_fast(dft_list[c].crys)
            push!(tbc_list, tbc_fake)
            push!(tbc_list_real, false)
        else
            push!(tbc_list, tbc)
            push!(tbc_list_real, true)            
        end
    end
    
    ARR2 = []
    ARR3 = []
    HVEC = []
    SVEC = []
    HIND = Dict()
    SIND = Dict()
    KEYS = []
    RIND = []

    RVEC = []
    INDVEC = []

    HON = []

    hnum = 0
    snum = 0

    rows = 0

    IND_convert = []
    DMIN_TYPES = Dict()
    DMIN_TYPES3 = Dict()

    threebody_inds = Int64[]

    keepind = Int64[]
    println("doing calc_tb_prepare_fast")

    real_tbc = []

    for (counter, tbc) in enumerate(tbc_list)
        
        #rearrange info for fitting.
        @time twobody_arrays, threebody_arrays, hvec, svec, Rvec, INDvec, h_onsite, ind_convert, dmin_types, dmin_types3 =  calc_tb_prepare_fast(tbc, use_threebody=fit_threebody, use_threebody_onsite=fit_threebody_onsite)

        #take into account prefit information
        if !ismissing(starting_database)
            goodmin=true
            for key in keys(dmin_types)
                for key2 in keys(starting_database)
                    if Set(key2) == key
                        if dmin_types[key] < starting_database[key2].min_dist * 0.995 && length(key2) == 2
                            goodmin = false
                            println("WARNING, skipping fit structure due to distance shorter than starting_database $counter , two-body")
                            println(key, " " , key2, " ", dmin_types[key] , " < " , starting_database[key2].min_dist)
                            println(tbc.crys)
                            println()
                            break
                        end
                    end
                end
            end


            if goodmin == true
                violation_list, vio_bool = calc_frontier(tbc.crys, starting_database, test_frontier=true, verbose=false)
                if vio_bool == false
                    println("calc_frontier failed, skip $counter") 
                    println(tbc.crys)
                    goodmin = false
                end
            end


            if goodmin == false
                println("goodmin == false")
                continue
            end
            println("goodmin == true")
            keepind = [keepind;counter]
            println(keepind)
        else
            keepind = [keepind;counter]
        end



        for key in keys(dmin_types)
            if !(key in keys(DMIN_TYPES))
                DMIN_TYPES[key] = dmin_types[key]
            else
                DMIN_TYPES[key] = min(DMIN_TYPES[key], dmin_types[key])
            end
        end

        for key in keys(dmin_types3)
            if !(key in keys(DMIN_TYPES3))
                DMIN_TYPES3[key] = dmin_types3[key]
            else
                DMIN_TYPES3[key] = min(DMIN_TYPES3[key], dmin_types3[key])
            end
        end


        push!(ARR2, twobody_arrays)
        if fit_threebody || fit_threebody_onsite
            push!(ARR3, threebody_arrays)
        else
            push!(ARR3, Dict())
        end
            

        push!(HVEC, hvec)
        push!(SVEC, svec)
        
        push!(RIND, rows+1:rows+size(hvec)[1])

        push!(RVEC, Rvec)
        push!(INDVEC, INDvec)

        push!(HON, h_onsite)

        push!(IND_convert, ind_convert)

        rows += size(hvec)[1]

        for key in keys(twobody_arrays)
            if !( (key,2) in KEYS)
                push!(KEYS, (key,2))
                
                HIND[(key,2)] = 1+hnum:hnum+twobody_arrays[key][3].sizeH
#                println("HIND ", (key,2), " ", 1+hnum:hnum+twobody_arrays[key][3].sizeH)
                SIND[(key,2)] = 1+snum:snum+twobody_arrays[key][3].sizeS

                hnum += twobody_arrays[key][3].sizeH
                snum += twobody_arrays[key][3].sizeS
            end
        end

#        println("KEYS 3 " , keys(threebody_arrays))
        
        if fit_threebody || fit_threebody_onsite
            for key in keys(threebody_arrays)
                if !((key,3) in KEYS)
                    push!(KEYS, (key,3))
                    
                    HIND[(key,3)] = 1+hnum:hnum+threebody_arrays[key][2].sizeH
                    println("HIND ", (key,3), " ", 1+hnum:hnum+threebody_arrays[key][2].sizeH)

                    SIND[(key,3)] = []

                    for iii in 1+hnum:hnum+threebody_arrays[key][2].sizeH
                        threebody_inds = [threebody_inds;iii]
                    end


                    hnum += threebody_arrays[key][2].sizeH
                    snum += 0


                end
            end
        end
    end

    for key in KEYS
        println("key: ", key)
    end

    println("hnum $hnum snum $snum rows $rows")
#####################################

    toupdate_inds = Int64[]
    keep_inds = Int64[]

    toupdate_inds_S = Int64[]
    keep_inds_S = Int64[]

    ch_keep = Float64[]
    cs_keep = Float64[]



    if !ismissing(starting_database )

        
        nh=hnum
        ns=snum
        println("using starting database, $nh $ns")

        #get starting info arranged.
        ch_start, cs_start = extract_database(starting_database, nh, ns, KEYS, HIND, SIND)

        ch_lin = zeros(hnum)
        cs_lin = zeros(snum)
        #merge h
        for i = 1:nh
            if abs(ch_start[i] + 999999.0) < 1e-7
                ch_start[i] = ch_lin[i]
#                ch_lin[i] = ch_start[i]
                push!(toupdate_inds, i)
            else
                push!(keep_inds, i)
            end
        end
        
        
        #merge s
        for i = 1:ns
            if abs(cs_start[i] + 999999.0) < 1e-7
                cs_start[i] = cs_lin[i]
#                cs_lin[i] = cs_start[i]
                push!(toupdate_inds_S, i)
            else
                push!(keep_inds_S, i)
            end
        end

        ch_keep = ch_start[keep_inds]
        cs_keep = cs_start[keep_inds_S]
        

        cs = deepcopy(cs_start)
        ch = deepcopy(ch_start)

        println("after using starting database, " ,length(ch), " ", length(cs))

#        if update_all == true
#            toupdate_inds = 1:length(ch_lin) #all
#            keep_inds = Int64[]
        #        end        
    else

        println("NO starting database")
        ch_lin = zeros(hnum)
        cs_lin = zeros(snum)

        toupdate_inds = 1:length(ch_lin) #all
        keep_inds = Int64[]

        toupdate_inds_S = 1:length(cs_lin) #all
        keep_inds_S = Int64[]

        cs = cs_lin
        ch = ch_lin
    end

    if !ismissing(refit_database)
        nh=hnum
        ns=snum
        println("using starting database, $nh $ns")
        
        ch_r, cs_r = extract_database(refit_database, nh, ns, KEYS, HIND, SIND)

        ch_refit = zeros(hnum)
        #merge h
        for i = 1:nh
            if abs(ch_r[i] + 999999.0) < 1e-7
                ch_refit[i] = ch_r[i]
            end
        end
        ch_refit = ch_refit[toupdate_inds]
    else
        ch_refit = missing
    end



    keepdata = Any[ch_keep, keep_inds, toupdate_inds, cs_keep, keep_inds_S, toupdate_inds_S]
    
    hnum_new = length(toupdate_inds)
    snum_new = length(toupdate_inds_S)

#####################################
    if ismissing(kpoints)
        X_H = zeros(rows, hnum_new)
        X_S = zeros(rows, snum_new)
    
        Y_H = zeros(rows)
        Y_S = zeros(rows)

    else
        X_H = missing
        X_S = missing
        Y_H = missing
        Y_S = missing
    end

#    X_Hnew_BIG = zeros(0,hnum)
#    X_Snew_BIG = zeros(0, snum)

    X_Hnew_BIG_list = []
    X_Snew_BIG_list = []

#    X_HnewOrth_BIG = zeros(0, hnum)

    Y_Hnew_BIG = Float64[]
    Y_Snew_BIG = Float64[]

    Xc_Hnew_BIG = Float64[]
    Xc_Snew_BIG = Float64[]

#    Y_HnewOrth_BIG = Float64[]

    ind_BIG = zeros(Int64, size(INDVEC)[1], 4)

    println("setup matricies")


    #reformat the data into matrices, fourier transform the real-space fitting data to k-space if using kspace
    c=0
    for (arr2, arr3, hvec, svec, rind, Rvec, INDvec, h_on, ind_convert, tbc_real, tbc) in zip(ARR2,ARR3, HVEC, SVEC, RIND, RVEC, INDVEC, HON, IND_convert, tbc_list_real, list_of_tbcs[keepind])
        c+=1
        println("first part")

        X_H_temp = zeros(size(hvec)[1], hnum) #old sizes
        X_S_temp = zeros(size(svec)[1], snum) #old sizes

        X_H_new = zeros(size(hvec)[1], hnum_new) #new sizes
        X_S_new = zeros(size(svec)[1], snum_new) #new sizes

        Xsc = zeros(size(svec)[1], 1)
        Xhc = zeros(size(hvec)[1], 1)

#        for i = 1:length(svec)
#            if abs(svec[i]) > 0.001
#                println("SVECS  ", Rvec[i,:], " " ,   INDvec[i,:], " ", svec[i])
#            end
#        end


        @time if true

#            if tbc_real
            if !ismissing(Y_H)
                Y_H[rind] = hvec[:]
                Y_S[rind] = svec[:]
            end
#            end

            for key in keys(arr2)
                hind = HIND[(key,2)]
                sind = SIND[(key,2)]
                #            println(key, " cols: ", minimum(hind), " ",  maximum(hind))

#                X_H[rind,hind] = arr2[key][1]
#                X_S[rind,sind] = arr2[key][2]
                X_H_temp[:,hind] = arr2[key][1]
                X_S_temp[:,sind] = arr2[key][2]

            end
            
            

            if fit_threebody || fit_threebody_onsite
                for key in keys(arr3)
                    hind = HIND[(key,3)]
                    #                println(key, " cols: ", minimum(hind), " ",  maximum(hind))
                    X_H_temp[:,hind] = arr3[key][1]
                end
            end

            Xhc[:,1] = X_H_temp * ch
            Xsc[:,1] = X_S_temp * cs


#            if tbc_real


            if ismissing(kpoints)
                Y_H[rind] -= Xhc
                Y_S[rind] -= Xsc

                X_H[rind,:] = X_H_temp[:,toupdate_inds]
                X_S[rind,:] = X_S_temp[:,toupdate_inds_S]
            end

#            end

            X_H_new[:,:] = X_H_temp[:,toupdate_inds]
            X_S_new[:,:] = X_S_temp[:,toupdate_inds_S]

            nw = maximum(INDvec)
        end



        if !ismissing(kpoints)

            println("fourier space")
            #            @time X_Hnew, X_Snew, Y_Hnew, Y_Snew =  fourierspace(kpoints[c], X_H, X_S, Y_H, Y_S, rind, Rvec, INDvec, h_on, ind_convert)
#            @time X_Hnew, X_Snew, Y_Hnew, Y_Snew, Xhc_Hnew, Xsc_Hnew =  fourierspace(tbc, kpoints[c], X_H_new, X_S_new, Y_H, Y_S, Xhc, Xsc, 1:size(rind)[1], Rvec, INDvec, h_on, ind_convert)  #get kspace
            @time X_Hnew, X_Snew, Y_Hnew, Y_Snew, Xhc_Hnew, Xsc_Snew =  fourierspace(tbc, kpoints[keepind[c]], X_H_new, X_S_new, hvec, svec, Xhc, Xsc, 1:size(rind)[1], Rvec, INDvec, h_on, ind_convert)  #get kspace
            #            @time X_Hnew, X_Snew, Y_Hnew, Y_Snew =  fourierspace(kpoints[c], X_H, X_S, Y_H, Y_S, rind, Rvec, INDvec, h_on, ind_convert)

#            ind_BIG[c, 1] = size(X_Hnew_BIG)[1] + 1
            ind_BIG[c, 1] = size(Xc_Hnew_BIG)[1] + 1

#            X_Hnew_BIG = vcat(X_Hnew_BIG, X_Hnew)
#            X_Snew_BIG = vcat(X_Snew_BIG, X_Snew)
            push!(X_Hnew_BIG_list, X_Hnew)
            push!(X_Snew_BIG_list, X_Snew)
            
            Xc_Hnew_BIG = vcat(Xc_Hnew_BIG, Xhc_Hnew)
            Xc_Snew_BIG = vcat(Xc_Snew_BIG, Xsc_Snew)


#            X_HnewOrth_BIG = vcat(X_HnewOrth_BIG, X_HnewOrth)

            Y_Hnew_BIG = vcat(Y_Hnew_BIG, Y_Hnew)
            Y_Snew_BIG = vcat(Y_Snew_BIG, Y_Snew)

#            Y_HnewOrth_BIG = vcat(Y_HnewOrth_BIG, Y_HnewOrth)

#            ind_BIG[c, 2] = size(X_Hnew_BIG)[1] 
            ind_BIG[c, 2] = size(Xc_Hnew_BIG)[1] 
            ind_BIG[c, 3] = nw

            nk = size(kpoints[keepind[c]])[1]
            ind_BIG[c, 4] = nk            

        end

    end

#    @time ch2 = X_H \ Y_H
#    @time cs2 = X_S \ Y_S

#    println("A error H: ", sum((X_H[:, :] * ch2  - Y_H[:]).^2))
#    println("A error S: ", sum((X_S[:, :] * cs2  - Y_S[:]).^2))

    #make big fitting matrices.
    
    println("assign memory S ", size(Xc_Hnew_BIG))
    @time X_Snew_BIG = zeros(Float32, size(Xc_Hnew_BIG)[1], snum_new)
    @time for (c,S) in enumerate(X_Snew_BIG_list)
        X_Snew_BIG[ind_BIG[c, 1]:ind_BIG[c, 2],:] = Float32.(S)
        S = []
    end

    X_Snew_BIG_list = []
    println("calc cs")
    @time cs = X_Snew_BIG \ Float32.(Y_Snew_BIG  - Xc_Snew_BIG)
    YS_new = X_Snew_BIG * cs
    println("error fit S cs , ", sum( (YS_new  - (Y_Snew_BIG  - Xc_Snew_BIG)).^2))

    X_Snew_BIG = []


    println("assign memory H")
    @time X_Hnew_BIG = zeros(Float32, size(Xc_Hnew_BIG)[1],hnum_new)
    @time for (c,H) in enumerate(X_Hnew_BIG_list)
        X_Hnew_BIG[ind_BIG[c, 1]:ind_BIG[c, 2],:] = Float32.(H)
        H = []
    end
    X_Hnew_BIG_list = []
    println("done assign memory")
    

#    if false
#        if !ismissing(kpoints)
#            X_H = vcat(X_H, X_Hnew_BIG)
#            X_S = vcat(X_S, X_Snew_BIG)
#            
#            Y_H = vcat(Y_H, Y_Hnew_BIG)
#            Y_S = vcat(Y_S, Y_Snew_BIG)
#        end
#    end#

    

    return  X_Hnew_BIG, Y_Hnew_BIG, X_H, X_S, X_Snew_BIG, Y_Hnew_BIG, Y_Snew_BIG, Y_H, Y_S, Xc_Hnew_BIG, Xc_Snew_BIG,  HON, ind_BIG, KEYS, HIND, SIND, DMIN_TYPES, DMIN_TYPES3, keepind, keepdata, YS_new, cs, ch_refit
    
end

"""
    function do_fitting_linear(list_of_tbcs; kpoints = missing, dft_list = missing,  fit_threebody=true, fit_threebody_onsite=true, do_plot = true, starting_database=missing, mode=:kspace, return_database=true, NLIM=100, refit_database=missing)

Linear fitting (not recursive). Used as starting point of recursive fitting.

# Arguments.

- `list_of_tbcs` The main data to fit to. Consists of a list of `tb_crys` or `tb_crys_kspace` objects.
- `kpoints = missing` Kpoints to do fitting to in k-space. Usually, this is not used, see below.
- `dft_list = missing` List of `dftout` objects. Normally, we get symmetry reduced k-grids from these objects.
- `fit_threebody=true` Fit three body coefficients. Yes for production runs.
- `fit_threebody_onsite=true` Fit 3body onsite coefficients. Yes for production runs.
- `do_plot = true` Make a plot to assess fitting. 
- `starting_database=missing` Use a database dict with some of the coefficents already fit and fixed.
- `mode=:kspace` Fit in either `:kspace` or `:rspace`. Can only use r-space if using only `tbc_crys` real-space objects to fit to. `:kspace` is normal.
- `return_database=true` Return the final database. For use when called by other functions.
- `NLIM=100` Largest number of k-points per structure. Set to smaller numbers to make code go faster / reduce memory, but may be less accurate.
- `refit_database=missing` starting point for coefficients we are fitting. Usually not used, as it doesn't always speed things up in practice. Something may not work about this option.
"""
function do_fitting_linear(list_of_tbcs; kpoints = missing, dft_list = missing,  fit_threebody=true, fit_threebody_onsite=true, do_plot = true, starting_database=missing, mode=:kspace, return_database=true, NLIM=100, refit_database=missing)

    if ismissing(kpoints) && !ismissing(dft_list)
        kpoints, KWEIGHTS, nk_max = get_k(dft_list, length(dft_list), list_of_tbcs, NLIM=NLIM)
    end
    if ismissing(kpoints)
        mode=:rspace
    end

    scf = false
    for m in list_of_tbcs
        if !ismissing(m)
            scf = m.scf
            break
        end
    end


    X_Hnew_BIG, Y_Hnew_BIG, X_H, X_S, X_Snew_BIG, Y_Hnew_BIG, Y_Snew_BIG,  Y_H, Y_S, Xc_Hnew_BIG, Xc_Snew_BIG, HON, ind_BIG, KEYS, HIND, SIND, DMIN_TYPES, DMIN_TYPES3, keepind, keepdata, YS_new, cs, ch_refit  = prepare_for_fitting(list_of_tbcs; kpoints = kpoints,dft_list=dft_list, fit_threebody=fit_threebody, fit_threebody_onsite=fit_threebody_onsite, starting_database=starting_database, refit_database=refit_database)
    
    println("done setup matricies")
    println("lsq fitting")

    println("fit mode  $mode")

    if mode == :rspace

        if ismissing(Y_H)
            println("something wrong Y_H ", Y_H)
        end
        @time ch = X_H \ Y_H
        @time cs = X_S \ Y_S

        println("rspace !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
        xc = X_H*ch
        for i = 1:min(length(Y_H), 300)
            println(i, " " , xc[i]," " , Y_H[i])
        end
        println("--")

    elseif mode == :kspace
        

        l = length(Y_Hnew_BIG) #randomly sample Hk to keep size reasonable
        
        if l > 3e6
            frac = 3e6 / l
            println("randsubseq $frac")
            rind = randsubseq( 1:l, frac)
        else
            rind = 1:l
        end


        @time ch = X_Hnew_BIG[rind,:] \ Float32.(Y_Hnew_BIG - Xc_Hnew_BIG)[rind]
#        @time cs = X_Snew_BIG \ (Y_Snew_BIG  - Xc_Snew_BIG)

#        println("sum Xc ", sum(abs.(Xc_Hnew_BIG)), " " , sum(abs.(Xc_Snew_BIG)))

        println("kspace lsq ")
#        println("sum " , sum(abs.(X_S)) ,  " ", sum(abs.(Y_Snew_BIG)))
#        println("sumH " , sum(abs.(X_H)) ,  " ", sum(abs.(Y_Hnew_BIG)))

    else
        println("mode error, using :kspace")
        @time ch = X_Hnew_BIG \ (Y_Hnew_BIG - Xc_Hnew_BIG)
#        @time cs = X_Snew_BIG \ (Y_Snew_BIG - Xc_Snew_BIG)
    end

#    YSf = X_S * cs
#    for i = 1:size(Y_S)[1]
#        if abs(Y_S[i]) > 0.01
#            println("i ", Y_S[i],  " ", YSf[i])
#        end
#    end
#    println("asdf")
#    println("xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx")
#    QQ = X_Snew_BIG * cs
#    for i = 1:size(QQ)[1]
#        if abs(QQ[i]) > 0.01 || abs(Y_Snew_BIG[i]) > 0.01
#            println("$i kspace ", QQ[i], "   ", Y_Snew_BIG[i])
#        end
#    end
#    println("xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx")
    

    (ch_keep, keep_inds, toupdate_inds, cs_keep, keep_inds_S, toupdate_inds_S) = keepdata

    ch_big = zeros(length(keep_inds) + length(toupdate_inds))
    ch_big[toupdate_inds] = ch[:]
    ch_big[keep_inds] = ch_keep[:]
    chX2 = ch_big

    cs_big = zeros(length(keep_inds_S) + length(toupdate_inds_S))
    cs_big[toupdate_inds_S] = cs[:]
    cs_big[keep_inds_S] = cs_keep[:]
    csX2 = cs_big

    

#    @save "a.jld" X_H Y_H X_S Y_S

    println("done lsq fitting")


    
    if return_database
        database = make_database(chX2, csX2,  KEYS, HIND, SIND,DMIN_TYPES,DMIN_TYPES3, scf=scf, tbc_list = list_of_tbcs[keepind] )
    else
        database = Dict()
    end


    
    if do_plot == true

        
        if mode == :rspace
            rows = size(X_H)[1]
            scatter(X_H[1:rows, :] * ch, Y_H[1:rows], color="green", MarkerSize=8)
            scatter!(X_S[1:rows, :] * cs, Y_S[1:rows], MarkerSize=4, color="orange")
        else
            rows1 = size(X_Hnew_BIG)[1]
            scatter(X_Hnew_BIG[1:rows1, :] * ch + Xc_Hnew_BIG , Y_Hnew_BIG[1:rows1] , color="green", MarkerSize=4)
            scatter!(Ys_new + Xc_Snew_BIG, Y_Snew_BIG  , MarkerSize=6, color="orange")
#            plot(Xc_Snew_BIG, Y_Snew_BIG , "k.")
        end

    end

    if mode == :rspace
        rows = size(X_H)[1]
        println("error r H: ", sum((X_H[1:rows, :] * ch  - Y_H[1:rows]).^2))
        println("error r S: ", sum((X_S[1:rows, :] * cs  - Y_S[1:rows]).^2))
    else
        println("pass")
#        println("error k H: ", sum((X_Hnew_BIG[1:rows1, :] * ch + Xc_Hnew_BIG[1:rows1,1] - Y_Hnew_BIG[1:rows1]).^2))

#        println("error k S: ", sum((X_Snew_BIG[1:rows1, :] * cs + Xc_Snew_BIG[1:rows1,1] - Y_Snew_BIG[1:rows1]).^2))
    end

    return database, ch, cs, X_Hnew_BIG, Xc_Hnew_BIG, Xc_Snew_BIG, X_H, X_Snew_BIG, Y_H, Y_S, HON, ind_BIG, KEYS, HIND, SIND, DMIN_TYPES, DMIN_TYPES3, keepind, keepdata, Y_Hnew_BIG, Y_Snew_BIG, YS_new, cs , ch_refit
           

end

#=
function change_S(YS_old, YS_new, YH, YH_new, ncalc, ind_BIG)

    try 
        for calc = 1:ncalc
            
            row1, rowN, nw, nk = ind_BIG[calc, 1:4]
            N = hermetian_indpt(nw)
        
            S_new = zeros(Complex{Float64}, nw, nw)
            S_old = zeros(Complex{Float64}, nw, nw)


            
            H_old = zeros(Complex{Float64}, nw, nw)
            H_new = zeros(Complex{Float64}, nw, nw)                            
            
            for k = 1:nk
                for i = 1:nw
                    for j = 1:nw
                        if i <= j
                            ind = hermetian_index(i,j, nw)
                            S_old[i,j] = YS_old[row1-1 + (k-1)*N + ind] + im*YS_old[row1-1 + (k-1)*N + ind +  nk*N]
                            S_old[j,i] = YS_old[row1-1 + (k-1)*N + ind] - im*YS_old[row1-1 + (k-1)*N + ind +  nk*N]
                            
                            S_new[i,j] = YS_new[row1-1 + (k-1)*N + ind] + im*YS_new[row1-1 + (k-1)*N + ind +  nk*N]
                            S_new[j,i] = YS_new[row1-1 + (k-1)*N + ind] - im*YS_new[row1-1 + (k-1)*N + ind +  nk*N]

                            H_old[i,j] = YH[row1-1 + (k-1)*N + ind] + im*YH[row1-1 + (k-1)*N + ind +  nk*N]
                            H_old[j,i] = YH[row1-1 + (k-1)*N + ind] - im*YH[row1-1 + (k-1)*N + ind +  nk*N]
                            
                        end
                    end
                end
 
                S_new = S_new + I
                S_old = S_old + I                

                S_new = (S_new + S_new')/2.0
                S_old = (S_old + S_old')/2.0
                
              
                try
                    vals_old = eigvals(S_old)
                    vals_new = eigvals(S_new)
                    
                    S_old = inv(sqrt(S_old))
                    S_new = sqrt(S_new)
                    
                    if minimum(vals_new) < 0.2
                        println("ERRRRRRRRRRRROR $calc $k v ")
                        println(vals_new)
                        println(vals_old)
                        return false
                    end
                
                catch##

                    println("unknown error $calc $k")
                    println(S_new)
                    return false
                end
                

                
                
                H_new = S_new * S_old * H_old * S_old * S_new

                for i = 1:nw
                    for j = 1:nw
                        if i <= j
                            ind = hermetian_index(i,j, nw)
                            YH_new[row1-1 + (k-1)*N + ind] = real(H_new[i,j])
                            YH_new[row1-1 + (k-1)*N + ind + nk*N] = imag(H_new[i,j])                        
                            
                        end
                    end
                end
                
                
            end
        end                    
        return true
    catch
        return false
    end
    
end
=#

#=
function do_optim_S(list_of_tbcs, dft_list ,  atoms_to_fit=missing, fit_threebody=false, fit_threebody_onsite=false)

    ncalc = length(list_of_tbcs)
    
    KPOINTS, KWEIGHTS, nk_max = get_k(dft_list, ncalc)

    X_Hnew_BIG, Y_Hnew_BIG, X_H, X_S, Y_H, Y_S, Xc_Hnew_BIG, Xc_Snew_BIG, HON, ind_BIG, KEYS, HIND, SIND,DMIN_TYPES,DMIN_TYPES3,keepind, keepdata =  prepare_for_fitting(list_of_tbcs; kpoints = KPOINTS, fit_threebody=fit_threebody, fit_threebody_onsite=fit_threebody_onsite)


#    println("Y_S")
#    println(Y_S)
#    println()

#    println("Y_Snew_BIG")
#    println(Y_Snew_BIG)
#    println()
    
#    println("done setup matricies")

#    println("first lsq fitting")

#    @time ch = X_H \ Y_H
    @time cs = X_S \ Y_S

#    @time cs = X_Snew_BIG \ Y_Snew_BIG
    
    println("done lsq fitting")


    @time ch = X_Hnew_BIG \  Y_Hnew_BIG
    
    error = sum((X_Hnew_BIG * ch .- Y_Hnew_BIG).^2)
    println("initial error $error")

    
    YH_new = zeros(size(Y_Hnew_BIG))

    YS_new = X_Snew_BIG * cs

    clf()
    plot(YS_new, Y_Snew_BIG, "b.", MarkerSize=3.0)
    
    
    #    converged = change_S(Y_Hnew_BIG, YS_new, Y_Hnew_BIG, YH_new, ncalc, ind_BIG)

    converged = change_S(Y_Snew_BIG, YS_new, Y_Hnew_BIG, YH_new, ncalc, ind_BIG)    
    
#    plot(YH_new, Y_Hnew_BIG, "r.", MarkerSize=3.0)
    
    
#    @time ch = X_Hnew_BIG \  YH_new#
#
#    error = sum((X_Hnew_BIG * ch .- YH_new).^2)
#    println("final error $error")
    
#    return 0

    
    function f(x)

        YS_new = X_Snew_BIG * x
        
        converged = change_S(Y_Snew_BIG, YS_new, Y_Hnew_BIG, YH_new, ncalc, ind_BIG)

        if converged
        
            ch = X_Hnew_BIG \ YH_new
            error = sum((X_Hnew_BIG * ch .- YH_new).^2)
            println("f $error")
            return error
        else
            println("f failed to run")
            return 1000.0
        end
            
    end

    opts = Optim.Options(g_tol = 1e-3,f_tol = 1e-3, x_tol = 1e-3,
                         iterations = 5,
                         store_trace = true,
                         show_trace = false)


    println("START MINIMIZATION RESULTS")
    
    #    res = optimize(f, cs, NelderMead(), opts)
    res = optimize(f, cs, LBFGS(), opts)
    
    println("MINIMIZATION RESULTS")
    println(res)

    minvec = Optim.minimizer(res)    


    rows = size(X_H)[1]

    ch = X_H \ Y_H

    database = make_database(ch, minvec,  KEYS, HIND, SIND,DMIN_TYPES, scf=list_of_tbcs[1].scf )
    
    
    return minvec, database

    
end
=#

"""
    function make_database(ch, cs,  KEYS, HIND, SIND, DMIN_TYPES, DMIN_TYPES3; scf=false, starting_database=missing, tbc_list=missing)

Construct the `coefs` and database from final results of fitting.
"""
function make_database(ch, cs,  KEYS, HIND, SIND, DMIN_TYPES, DMIN_TYPES3; scf=false, starting_database=missing, tbc_list=missing)
    println("make_database")
    if ismissing(starting_database)
        database = Dict()
    else
        database = deepcopy(starting_database)
    end

    database["scf"] = scf
    database["SCF"] = scf

    if ismissing(tbc_list)
        frontier = Dict()
    else
        println("calc frontier")
        frontier = calc_frontier_list(tbc_list)
    end

    function add(AT_ARRS, coef)
        for KEY in AT_ARRS
            database[KEY] = coef
#            if haskey(frontier, KEY)
#                database[KEY].dist_frontier =  frontier[KEY]
#            end
        end
    end


    for key in KEYS



        hind = HIND[key]
        sind = SIND[key]

        at_arr = [i for i in key[1]]
        atomkey = key[1]
        dim = key[2]

        if dim == 2
            dmin = DMIN_TYPES[atomkey]
        elseif dim == 3
            dmin = DMIN_TYPES3[atomkey]   
        end

        

        coef = make_coefs(atomkey,dim, datH=ch[hind], datS=cs[sind], min_dist=dmin, dist_frontier = frontier)

        #here, we store "extra" copies of the data, not taking into account permutation symmetries
        if dim == 2

            if length(at_arr) == 2
                if (at_arr[1], at_arr[2]) in keys(database)
                    continue
                end

                add([(at_arr[1], at_arr[2]), (at_arr[2], at_arr[1])] , coef)

#                database[(at_arr[2], at_arr[1])] = deepcopy(coef)

            else
                if (at_arr[1], at_arr[1]) in keys(database)
                    continue
                end

                add([(at_arr[1], at_arr[1])] , coef)

#                for key in [(at_arr[1], at_arr[1])]
#                    database[key] = deepcopy(coef); 
#                    if haskey(frontier, key)
#                        database[key] = frontier[key]
#                    end
#                end
#                database[(at_arr[1], at_arr[1])] = deepcopy(coef)
            end
        elseif dim == 3

            if length(at_arr) == 1
                if (at_arr[1], at_arr[1], at_arr[1]) in keys(database)
                    continue
                end
                
#                database[(at_arr[1], at_arr[1], at_arr[1])] = deepcopy(coef)
                add([(at_arr[1], at_arr[1], at_arr[1])] , coef)


            elseif length(at_arr) == 2
                if (at_arr[1], at_arr[1], at_arr[2]) in keys(database)
                    continue
                end

                add([(at_arr[1], at_arr[1], at_arr[2]),(at_arr[1], at_arr[2], at_arr[1]),(at_arr[2], at_arr[1], at_arr[1]),(at_arr[2], at_arr[2], at_arr[1]), (at_arr[2], at_arr[1], at_arr[2]), (at_arr[1], at_arr[2], at_arr[2])] , coef)

#                database[(at_arr[1], at_arr[1], at_arr[2])] = deepcopy(coef)
#                database[(at_arr[1], at_arr[2], at_arr[1])] = deepcopy(coef)
#                database[(at_arr[2], at_arr[1], at_arr[1])] = deepcopy(coef)
#                database[(at_arr[2], at_arr[2], at_arr[1])] = deepcopy(coef)
#                database[(at_arr[2], at_arr[1], at_arr[2])] = deepcopy(coef)
#                database[(at_arr[1], at_arr[2], at_arr[2])] = deepcopy(coef)
            elseif length(at_arr) == 3
                if (at_arr[1], at_arr[2], at_arr[3]) in keys(database)
                    continue
                end

                add([(at_arr[1], at_arr[2], at_arr[3]), (at_arr[1], at_arr[3], at_arr[2]), (at_arr[2], at_arr[1], at_arr[3]), (at_arr[2], at_arr[3], at_arr[1]), (at_arr[3], at_arr[1], at_arr[2]), (at_arr[3], at_arr[2], at_arr[1])], coef)

#                database[(at_arr[1], at_arr[2], at_arr[3])] = deepcopy(coef)
#                database[(at_arr[1], at_arr[3], at_arr[2])] = deepcopy(coef)
#                database[(at_arr[2], at_arr[1], at_arr[3])] = deepcopy(coef)
#                database[(at_arr[2], at_arr[3], at_arr[1])] = deepcopy(coef)
#                database[(at_arr[3], at_arr[1], at_arr[2])] = deepcopy(coef)
#                database[(at_arr[3], at_arr[2], at_arr[1])] = deepcopy(coef)
            end            
        
        end

            
    end
    if !(ismissing(tbc_list))
        println("setting maxmin")
        for tbc in tbc_list
            tbc_temp = calc_tb_fast(tbc.crys, database, set_maxmin=true)
        end
        for key1 in keys(database)
            if typeof(database[key1]) == coefs
                for key2 in keys(database[key1].maxmin_val_train)
                    (maxval, minval) = database[key1].maxmin_val_train[key2]
                    maxval = max(1e-4, maxval)
                    minval = min(-1e-4, minval)
                    database[key1].maxmin_val_train[key2] = (maxval, minval)
                end
            end
        end


         if !ismissing(starting_database)
             for key in keys(starting_database)
                 database[key] = starting_database[key]
             end
         end

    end

    return database
end

"""
    function extract_database(database_old,nh,ns, KEYS, HIND, SIND)

If we are using fixed prefit coefficients, we have to get them in the same form as our current fitting.
"""
function extract_database(database_old,nh,ns, KEYS, HIND, SIND)
    ch = zeros(nh) .- 999999.0
    cs = zeros(ns) .- 999999.0


    
    for key in KEYS
#        println("key ", key)
        hind = HIND[key]
        sind = SIND[key]

        at_arr = [i for i in key[1]]
        at_arr = tuple(at_arr...)
        
        atomkey = key[1]
        dim = key[2]

        t = []
        if dim == 2
            if length(at_arr) == 1
                t = (at_arr[1], at_arr[1])
            else
                t = at_arr
            end
        elseif dim == 3
            if length(at_arr) == 1
                t = (at_arr[1], at_arr[1], at_arr[1])
            elseif length(at_arr) == 2
                t = (at_arr[1], at_arr[1], at_arr[2])
            else
                t = at_arr
            end
        end
                

        
#        println("t ", t)
        if t in keys(database_old)
            println("YES found key ", t)
            coef = database_old[t]
            ch[hind] = coef.datH[:]
            cs[sind] = coef.datS[:]            
        else
            println("        NO  found key ", t)
        end
            #        coef = make_coefs(atomkey,dim, datH=ch[hind], datS=cs[sind])
    end
    return ch, cs
end


"""
    function fourierspace(tbc, kpoints, X_H, X_S, Y_H, Y_S, Xhc, Xsc, rind, Rvec, INDVec, h_on, ind_convert)

Do analytic fourier transform of real space fitting matrices into kspace.
"""
function fourierspace(tbc, kpoints, X_H, X_S, Y_H, Y_S, Xhc, Xsc, rind, Rvec, INDVec, h_on, ind_convert)

#    for i = 1:length(Y_S)
#        if abs(Y_S[i]) > 0.001
#            println("SVECF  ", Rvec[i,:], " " ,   INDVec[i,:], " ", Y_S[i])
#        end
#    end

    nw = tbc.tb.nwan

#    nw = maximum(INDVec)
    nk = size(kpoints)[1]

    println("fs prepare $nw $nk")
        
    colh = size(X_H)[2]
    cols = size(X_S)[2]


#    println("fourierspace x")
#    println(tbc.crys)
#    println(tbc.tb.grid)

#    println(kpoints[1:min(5,nk),:])
#    println(tbc.tb.K[1:min(5,nk),:])
#    println("-----")



#        X_HnewOrth = zeros(nk*nw*nw * 2, colh)
#        Y_HnewOrth = zeros(nk*nw*nw * 2)


    twopi_i = 2.0 * pi * im
    k=zeros(3)
        
    nr = size(Rvec)[1]

    rk = zeros(nr)
    real_expirk = zeros(Float64, nr)
    imag_expirk = zeros(Float64, nr)

        
    S = zeros(Complex{Float64},nw,nw)
    Sold = zeros(Complex{Float64},nw,nw)

    Horth = zeros(Complex{Float64},nw,nw)
#    Hk = zeros(Complex{Float64},nw,nw)

    
    X_H_t = X_H' #better memory access
    X_S_t = X_S'


    N = hermetian_indpt(nw)
    
    Y_Hnew = zeros(nk*N * 2)
    Y_Snew = zeros(nk*N * 2)

    Xhc_Hnew = zeros(nk*N * 2)
    Xsc_Snew = zeros(nk*N * 2)

    
#    X_Hnew = zeros(colh, nk*nw*nw * 2)
#    X_Snew = zeros(cols, nk*nw*nw * 2)

    X_Hnew = zeros(colh, nk*N * 2)
    X_Snew = zeros(cols, nk*N * 2)
    
    
    for kind in 1:nk

        k = kpoints[kind, :]
        rk[:] = k[1] * Rvec[:,1]
        rk   += k[2] * Rvec[:,2]
        rk   += k[3] * Rvec[:,3]
        
        real_expirk[:] = real(exp.(-twopi_i * rk))
        imag_expirk[:] = imag(exp.(-twopi_i * rk))

        for i in 1:nr

            o1 = INDVec[i,1]
            o2 = INDVec[i,2]

            if o1 > o2
                continue
            end
            
            i_convert = ind_convert[i]
            ri = rind[i_convert]
                
#            indr = (kind-1)*nw*nw + (o1-1)*nw + o2
#            indi = (kind-1)*nw*nw + (o1-1)*nw + o2 + nk*nw*nw

            indr = (kind-1)*N + hermetian_index(o1,o2, nw)
            indi = (kind-1)*N + hermetian_index(o1,o2, nw) + nk*N
            
            for ii in 1:colh
                X_Hnew[ii,indr] += X_H_t[ii,ri] * real_expirk[i]
            end
            for ii in 1:colh
                X_Hnew[ii,indi] += X_H_t[ii,ri] * imag_expirk[i]
            end
            
            for ii in 1:cols
                X_Snew[ii,indr] += X_S_t[ii,ri] * real_expirk[i]
            end
            for ii in 1:cols
                X_Snew[ii,indi] += X_S_t[ii,ri] * imag_expirk[i]
            end

#            X_Hnew[(kind-1)*nw*nw + (o1-1)*nw + o2, :] += X_H[rind[i], :] .* real_expirk[i]
#            X_Hnew[(kind-1)*nw*nw + (o1-1)*nw + o2 + nk*nw*nw, :] += X_H[rind[i], :] .* imag_expirk[i]


#            X_Snew[(kind-1)*nw*nw + (o1-1)*nw + o2, :] += X_S[rind[i], :] .* real_expirk[i]
#            X_Snew[(kind-1)*nw*nw + (o1-1)*nw + o2 + nk*nw*nw, :] += X_S[rind[i], :] .* imag_expirk[i]


            if typeof(tbc) != tb_crys_kspace{Float64}
                Y_Hnew[indr] += Y_H[ri] .* real_expirk[i]
                Y_Snew[indr] += Y_S[ri] .* real_expirk[i]

                Y_Hnew[indi] += Y_H[ri] .* imag_expirk[i]
                Y_Snew[indi] += Y_S[ri] .* imag_expirk[i]


#                if abs(Y_S[ri]) > 0.001 && kind == 1
#                    println("SXXXX $i $o1 $o2 ", Rvec[i,:], " " , Y_S[ri], " " , ri)
#                    println("HXXXX $o1 $o2 ", Rvec[i,:], " " , Y_H[ri])
#                end

#                if abs(Rvec[i,1]) +  abs(Rvec[i,2]) + abs(Rvec[i,3]) < 1e-5 && o1 == o2
#                    Y_Snew[indr] += 1.0
#                end

            end

            Xhc_Hnew[indr] += Xhc[ri] .* real_expirk[i]
            Xsc_Snew[indr] += Xsc[ri] .* real_expirk[i]
            
            Xhc_Hnew[indi] += Xhc[ri] .* imag_expirk[i]
            Xsc_Snew[indi] += Xsc[ri] .* imag_expirk[i]


        end

        if typeof(tbc) == tb_crys_kspace{Float64}
#            println("typeof(tbc) == tb_crys_kspace !!!!!!!!!!!!!!!!!!!!")
            vects, vals, hk, sk, vals0 = Hk(tbc, kpoints[kind,:], scf=false)
#            if kind == 1
#                println("SX")
#                println(real(sk))
#            end

            for o1 = 1:nw
                for o2 = 1:nw

                    if o1 > o2
                        continue
                    end

                    indr = (kind-1)*N + hermetian_index(o1,o2, nw)
                    indi = (kind-1)*N + hermetian_index(o1,o2, nw) + nk*N

                    Y_Hnew[indr] = real(hk[o1,o2])
                    Y_Snew[indr] = real(sk[o1,o2])

                    if o1 == o2 
                        Y_Snew[indr] -= 1.0
                        Y_Hnew[indr] -= h_on[o1, o2]
                    end

#                    if abs(Y_Snew[indr]) > 0.001 && kind == 1
#                        println("SXXXX $kind $o1 $o2 ", Y_Snew[indr])
#                    end


                    Y_Hnew[indi] = imag(hk[o1,o2])
                    Y_Snew[indi] = imag(sk[o1,o2])
                

                end
            end
        end
    end

    return X_Hnew', X_Snew', Y_Hnew, Y_Snew, Xhc_Hnew, Xsc_Snew
end

#=
function convert_H_S(tbc_old, tbc_newS, grid=missing)
    #renormalizes the Hamiltonian of tbc_oldA with the overlap matrix (S) of tbc_newSA
    #also ensures the energy is correct and the distances cutoff is correct.
    #the goal is to make a hamiltonian we can fit to.


#    tbc_old = trim_dist(tbc_oldA)
#    tbc_newS = trim_dist(tbc_newSA)

    hamK3, SK3 = myfft_R_to_K(tbc_old, grid)

    energy_calc = calc_energy_fft(hamK3, SK3, tbc_old.nelec)
    
    shift = (tbc_old.dftenergy - energy_calc) / tbc_old.nelec


    thetype = typeof(real(hamK3[1,1,1,1,1]))
    grid = size(SK3)[3:5]

    hamK3_new, SK3_new = myfft_R_to_K(tbc_newS, grid)


    nwan = tbc_old.tb.nwan

    c = 0
    sk_new = zeros(Complex{thetype}, nwan, nwan)
    sk_old = zeros(Complex{thetype}, nwan, nwan)

    sk_old_inv_sqrt = zeros(Complex{thetype}, nwan, nwan)
    sk_new_sqrt = zeros(Complex{thetype}, nwan, nwan)

    h_orthog = zeros(Complex{thetype}, nwan, nwan)
    h_nono = zeros(Complex{thetype}, nwan, nwan)
    hamK3_shifted = zeros(Complex{thetype}, size(hamK3))

    shifteye = shift * I(nwan)

    for k1 = 1:grid[1]
        for k2 = 1:grid[2]
            for k3 = 1:grid[3]
                c += 1
                sk_new[:,:] = SK3_new[:,:, k1, k2, k3]
                sk_new[:,:] = (sk_new+sk_new')/2.0
                sk_old[:,:] = SK3[:,:, k1, k2, k3]
                sk_old[:,:] = (sk_old + sk_old')/2.0

                sk_old_inv_sqrt[:,:] = inv(sqrt(sk_old))
                sk_new_sqrt[:,:] = sqrt(sk_new)

                h_orthog[:,:] = sk_old_inv_sqrt * hamK3[:,:,k1,k2,k3] * sk_old_inv_sqrt
                
                h_orthog += shifteye

                h_nono[:,:] = sk_new_sqrt * h_orthog * sk_new_sqrt

                hamK3_shifted[:,:,k1,k2,k3] = 0.5*(h_nono + h_nono')
            end
        end
    end

    ham_r, S_r, r_dict, ind_arr = myfft(tbc_old.crys, true, grid, missing , hamK3_shifted, SK3_new)
    tb = make_tb(ham_r, ind_arr, r_dict, S_r )        
    tbc_renorm = make_tb_crys(tb, tbc_old.crys, tbc_old.nelec, tbc_old.dftenergy)

#    tbc_renorm = trim_dist(tbc_renorm)
    trim(tbc_renorm.tb, 0.0001)
    
    return tbc_renorm
                
end
=#

#=
function do_fitting_nonlinear(list_of_tbcs; dft_list=missing, kpoints = [0 0 0; 0 0 0.5; 0 0.5 0.5; 0.5 0.5 0.5],  atoms_to_fit=missing, fit_threebody=true, do_plot = false)
    
    if ismissing(dft_list)
        KPOINTS = []
        KWEIGHTS = []
        nk_max = size(kpoints)[1]
        kweights = ones(Float64, nk)/nk * 2.0
        for n = 1:length(list_of_tbcs)
            push!(KPOINTS, kpoints)
            push!(KWEIGHTS, kweights)

        end
    else
        KPOINTS = []
        KWEIGHTS = []
        nk_max = 1
        for n = 1:length(list_of_tbcs)
            push!(KPOINTS, dft_list[n].bandstruct.kpts)
            nk_max = max(size(dft_list[n].bandstruct.kpts)[1], nk_max)
            push!(KWEIGHTS, dft_list[n].bandstruct.kweights)

        end
    end        


    println("DO LINEAR FITTING")

    database, ch, cs, X_Hnew_BIG, Y_Hnew_BIG, X_H, X_Snew_BIG, Y_H, h_on, ind_BIG, KEYS, HIND, SIND = do_fitting_linear(list_of_tbcs; kpoints = KPOINTS,  atoms_to_fit=atoms_to_fit, fit_threebody=fit_threebody,fit_threebody_onsite=fit_threebody,  do_plot = false)

    println("NOW, DO NON-LINEAR FITTING")
    
    NWAN_MAX = maximum(ind_BIG[:,3])


#    nk = size(kpoints)[1]
    ncalc = length(list_of_tbcs)

    VALS     = zeros(ncalc, nk_max, NWAN_MAX)
    OCCS     = zeros(ncalc, nk_max, NWAN_MAX)
    WEIGHTS     = zeros(ncalc, nk_max, NWAN_MAX)
    ENERGIES = zeros(ncalc)
    

    #PREPARE REFERENCE ENERGIES / EIGENVALUES
    c=0
    for (tbc, kpoints, kweights) in zip(list_of_tbcs, KPOINTS, KWEIGHTS)
        c+=1
        nw = ind_BIG[c, 3]
        nk = size(kpoints)[1]
        for k in 1:nk
            vects, vals, hk, sk = Hk(tbc.tb, kpoints[k,:])
            VALS[c,k,1:nw] = vals
        end

        
        ENERGIES[c], occs = band_energy(VALS[c,1:nk,1:nw], kweights, tbc.nelec, 0.01, returnocc=true)
        OCCS[c,1:nk,1:nw] = occs

        etmp, occs = band_energy(VALS[c,1:nk,1:nw], kweights, tbc.nelec+0.25, 0.05, returnocc=true)
        WEIGHTS[c,1:nk,1:nw] = occs
#        WEIGHTS[c,1:nk,1:nw] .= 1.0

    end

    Ys = X_Snew_BIG * cs

    VALS_working = zeros(size(VALS))
    ENERGIES_working = zeros(size(ENERGIES))
    OCCS_working = zeros(size(OCCS))

    WEIGHTS = WEIGHTS .+ 0.1

    verbose=0

    function tomin(c)
        error2_rs = sum((X_H * c .- Y_H).^2)

        Xc = X_Hnew_BIG * c
        
        error2_eig = 0.0
        
        
        for calc = 1:ncalc
            row1, rowN, nw = ind_BIG[calc, 1:3]
            vals = ones(nw) * 100.0
            H = zeros(Complex{Float64}, nw, nw)
            S = zeros(Complex{Float64}, nw, nw)
            nk = size(KPOINTS[calc])[1]

            for k = 1:nk
                for i = 1:nw
                    for j = 1:nw
                        H[i,j] = Xc[row1-1 + (k-1)*nw*nw + (i-1)*nw + j] + im*Xc[row1-1 + (k-1)*nw*nw + (i-1)*nw + j + nk*nw*nw]  + h_on[calc][i, j]
                        S[i,j] = Ys[row1-1 + (k-1)*nw*nw + (i-1)*nw + j] + im*Ys[row1-1 + (k-1)*nw*nw + (i-1)*nw + j + nk*nw*nw]
                    end
                    S[i,i] += 1.0 #onsite
                end
                H = (H+H')/2.0
                S = (S+S')/2.0
                
                try
                    vals = real(eigvals(H, S))
                catch
                    vals[:] = ones(nw) * 100.0
                end
                VALS_working[calc,k,1:nw] = vals
            end
#            kweights = ones(Float64, nk)/nk * 2.0
            kweights = KWEIGHTS[calc]
            ENERGIES_working[calc], occs = band_energy(VALS_working[calc,1:nk,1:nw], kweights, list_of_tbcs[calc].nelec, 0.01, returnocc=true)
#            OCCS_working[calc,1:,1:nw] = occs

            error2_eig += sum(WEIGHTS[calc,1:nk,1:nw].*(VALS_working[calc,1:nk,1:nw] .- VALS[calc,1:nk,1:nw]).^2 )
        end

        error2_toten = sum((ENERGIES_working .- ENERGIES).^2)

        if verbose == 2
            println("ENERGIES_working", ENERGIES_working)
            println("ENERGIES        ", ENERGIES)
            println("error2_rs $error2_rs")
            println("error2_eig $error2_eig")
            println("error2_toten $error2_toten")
#        elseif verbose == 1
#            println( "$error2_rs $error2_eig $error2_toten")
        end

        return 0.1 * error2_rs + error2_eig + error2_toten * 100000.0
#        return 0.01 * error2_rs + error2_eig 
    end

    
    verbose = 2
    @time ret = tomin(ch)
    verbose = 1
    println("starting ret $ret")
    results = optimize(tomin, ch, LBFGS(), Optim.Options(iterations = 50))
    println("results ")
    println(results)
    println()
    ch_final = Optim.minimizer(results)
    verbose = 2
    @time ret = tomin(ch_final)
    verbose = false
    println("final ret $ret")
    println()
    database = make_database(ch_final, cs,  KEYS, HIND, SIND, scf=list_of_tbcs[1].scf)
    
    return database
end
=#
#########################################################################################################################################

function hermetian_indpt(nwan::Int64)
    return nwan*(nwan+1)÷2
end


"""
    function hermetian_index(i::Int64,j::Int64,nwan::Int64)

This is used to reduce memory by only keeping track of independet coefficients of Hermetian matrices, which is nearly a factor of 2 reduction.
"""
function hermetian_index(i::Int64,j::Int64,nwan::Int64)
    if i <= j
        return nwan * (i-1) + j - (i-1)*(i)÷2
    else
        return nwan * (j-1) + i - (j-1)*(j)÷2
    end
end



"""
    function get_k(dft_list, ncalc; NLIM = 100)

Decide which k-points to include in fitting, as we limit the total number to `NLIM` or less per structure

Uses some randomness, but puts high symmetry points at front of line.
"""
function get_k(dft_list, ncalc, list_of_tbcs; NLIM = 100)

    if ismissing(dft_list)
        println("using entered kpoints instead of DFT list!!!!!!!!!!!")
        KPOINTS = []
        KWEIGHTS = []
        nk_max = size(kpoints)[1]
        nk = size(kpoints)[1]
        kweights = ones(Float64, nk)/nk * 2.0
        for n = 1:length(list_of_tbcs)
            push!(KPOINTS, kpoints)
            push!(KWEIGHTS, kweights)

        end
    else
        println("using dft list NLIM $NLIM")
        KPOINTS = []
        KWEIGHTS = []
        nk_max = 1

#        NLIM = 100
        for n = 1:ncalc

            kpts = dft_list[n].bandstruct.kpts
            wghts = dft_list[n].bandstruct.kweights

#            println("get k $n ", typeof(list_of_tbcs[n]), " " , typeof(list_of_tbcs[n]) == tb_crys_kspace{Float64})
            if typeof(list_of_tbcs[n]) == tb_crys_kspace{Float64} #superceeding
#                println("modk qqqqqqqqqqqqqqqqqqqqqqqqqqqqwq")
                kpts = list_of_tbcs[n].tb.K
                wghts = list_of_tbcs[n].tb.kweights
            end

#randomly downselect kpoints of number kpoints > 150            
            if size(kpts)[1] > NLIM
                println("limit kpoints to $NLIM, from ",  size(kpts)[1])
                ind = reverse(sortperm(wghts)) #largest weights first
                
#                keepN = 30 #keep this many from beginning of weighted list
                keepN = min(min(20, length(ind)), NLIM)
                ind1 = ind[1:keepN]
                if size(kpts)[1]-keepN > 0
                    N = randperm(size(kpts)[1]-keepN) .+ keepN #randomly sample the rest
                    ind2 = [ind1;ind[N]]
                end

#                kpts = kpts[N[1:NLIM],:]
#                wghts = wghts[N[1:NLIM]]

                kpts = kpts[ind2[1:NLIM],:]
                wghts = wghts[ind2[1:NLIM]]
                sw = sum(wghts)
                wghts = wghts * (2.0/sw)
            end

            push!(KPOINTS, kpts)
            push!(KWEIGHTS, wghts)
            
#            push!(KPOINTS, dft_list[n].bandstruct.kpts)
#            push!(KWEIGHTS, dft_list[n].bandstruct.kweights)
            nk_max = max(size(dft_list[n].bandstruct.kpts)[1], nk_max)

        end

#=
        NLIM = 100
        for n = 1:ncalc

            kpts = dft_list[n].bandstruct.kpts
            wghts = dft_list[n].bandstruct.kweights

#randomly downselect kpoints of number kpoints > 150            
            if size(kpts)[1] > NLIM
                println("limit kpoints to $NLIM, from ",  size(kpts)[1])
                N = randperm(size(kpts)[1])
                kpts = kpts[N[1:NLIM],:]
                wghts = wghts[N[1:NLIM]]
                sw = sum(wghts)
                wghts = wghts * (2.0/sw)
            end

            push!(KPOINTS, kpts)
            push!(KWEIGHTS, wghts)
            
#            push!(KPOINTS, dft_list[n].bandstruct.kpts)
#            push!(KWEIGHTS, dft_list[n].bandstruct.kweights)
            nk_max = max(size(dft_list[n].bandstruct.kpts)[1], nk_max)

        end
=#

    end        

    return KPOINTS, KWEIGHTS, nk_max

end

"""
    function do_fitting_recursive(list_of_tbcs ; weights_list = missing, dft_list=missing, X_cv = missing, kpoints = [0 0 0; 0 0 0.5; 0 0.5 0.5; 0.5 0.5 0.5], starting_database = missing,  update_all = false, fit_threebody=true, fit_threebody_onsite=true, do_plot = false, energy_weight = missing, rs_weight=missing,ks_weight=missing, niters=50, lambda=0.0, leave_one_out=false, prepare_data = missing, RW_PARAM=0.0, NLIM = 100, refit_database = missing, start_small = false)

This is the primary function for fitting. Uses the self-consistent linear fitting algorithm.

# Arguments
- `list_of_tbcs` List of `tbc_crys` or `tbc_crys_kspace` object to fit to.
- `weights_list = missing` relative weights of different tbc objects in fitting code.
- `dft_list=missing` List of `dftout` objects used to get symmetry-reduced kpoint lists / weights to use in kspace fitting.
- `kpoints = [0 0 0; 0 0 0.5; 0 0.5 0.5; 0.5 0.5 0.5]` alternate way of setting k-points, not usually used.
- `starting_database = missing` If using already fit coefficents for some of the atoms, from another calculation, include that database dict here.
- `update_all = false` If update_all is true, then we refit the starting coefficients from `starting_database`. Normally `false` except for testing.
- `fit_threebody=true` Fit 3body intersite coefficents. `true` for production runs.
- `fit_threebody_onsite=true` Fit 3body onsite coefficents. `true` for production runs.
- `do_plot = false` make plot for the linear fit.
- `energy_weight = missing` Weighting for the total energy terms in the fit.
- `rs_weight=missing` Real space hamiltonian matrix els weighting. zero for pure k-space fit.
- `ks_weight=missing`  K-space hamiltonian matrix els weighting. Set to zero to ignore hamiltonian matrix els and only fit to band structure.
- `niters=50` Maximum number of iterations.
- `lambda=0.0`  If greater than zero, include a simple ridge regression with this lambda value. Usually zero.
- `leave_one_out=false`  Leave-one-out cross-validation. Too slow to be very useful.
- `prepare_data = missing` Rarely used option to reuse previous linear fitting.
- `RW_PARAM=0.0` Weighting of non-occupied bands in fit.
- `NLIM = 100` Maximum k-points per structure. Smaller for faster but less accurate fit that uses less memory.
- `refit_database = missing` Option to include starting data. Rarely used.
- `start_small = false` When fitting only 3body data, setting this to true will start the 3body terms with very small values, which can improve convergence. Not useful if also fitting 2body terms.

"""
function do_fitting_recursive(list_of_tbcs ; weights_list = missing, dft_list=missing, kpoints = [0 0 0; 0 0 0.5; 0 0.5 0.5; 0.5 0.5 0.5], starting_database = missing,  update_all = false, fit_threebody=true, fit_threebody_onsite=true, do_plot = false, energy_weight = missing, rs_weight=missing,ks_weight=missing, niters=50, lambda=0.0, leave_one_out=false, prepare_data = missing, RW_PARAM=0.0, NLIM = 100, refit_database = missing, start_small = false)

    
    
    KPOINTS, KWEIGHTS, nk_max = get_k(dft_list, length(dft_list), list_of_tbcs, NLIM=NLIM)

    
    if ismissing(prepare_data)
        println("DO LINEAR FITTING")

        if update_all == true
            starting_database_t = missing #keep all
        else
            starting_database_t = starting_database
        end

        pd = do_fitting_linear(list_of_tbcs; kpoints = KPOINTS, dft_list = dft_list,  fit_threebody=fit_threebody, fit_threebody_onsite=fit_threebody_onsite, do_plot = false, starting_database=starting_database_t, return_database=false, NLIM=NLIM, refit_database=refit_database)
    else
        println("SKIP LINEAR MISSING")
        pd = prepare_data
#        database_linear, ch_lin, cs_lin, X_Hnew_BIG, Y_Hnew_BIG, X_H, X_Snew_BIG, Y_H, h_on, ind_BIG, KEYS, HIND, SIND, DMIN_TYPES, DMIN_TYPES3 = prepare_data
    end

    return do_fitting_recursive_main(list_of_tbcs, pd; weights_list = weights_list, dft_list=dft_list, kpoints = kpoints, starting_database = starting_database,  update_all = update_all, fit_threebody=fit_threebody, fit_threebody_onsite=fit_threebody_onsite, do_plot = do_plot, energy_weight = energy_weight, rs_weight=rs_weight,ks_weight = ks_weight, niters=niters, lambda=lambda, leave_one_out=leave_one_out, RW_PARAM=RW_PARAM, KPOINTS=KPOINTS, KWEIGHTS=KWEIGHTS, nk_max=nk_max,  start_small = start_small )

end

function do_fitting_recursive_main(list_of_tbcs, prepare_data; weights_list=missing, dft_list=missing, kpoints = [0 0 0; 0 0 0.5; 0 0.5 0.5; 0.5 0.5 0.5], starting_database = missing,  update_all = false, fit_threebody=true, fit_threebody_onsite=true, do_plot = false, energy_weight = missing, rs_weight=missing, ks_weight = missing, niters=50, lambda=0.0, leave_one_out=false, RW_PARAM=0.0001, KPOINTS=missing, KWEIGHTS=missing, nk_max=0, start_small=false)


#    database_linear, ch_lin, cs_lin, X_Hnew_BIG, Y_Hnew_BIG,               X_H,               X_Snew_BIG, Y_H, h_on,              ind_BIG, KEYS, HIND, SIND, DMIN_TYPES, DMIN_TYPES3,keepind, keepdata = prepare_data
    
    database_linear, ch_lin, cs_lin, X_Hnew_BIG, Xc_Hnew_BIG, Xc_Snew_BIG, X_H, X_Snew_BIG, Y_H, Y_S, h_on, ind_BIG, KEYS, HIND, SIND, DMIN_TYPES, DMIN_TYPES3, keepind, keepdata, Y_Hnew_BIG, Y_Snew_BIG, Ys_new, cs, ch_refit  = prepare_data

    println("keepind " , length(keepind), " " , sum(keepind))
    println(keepind)

    (ch_keep, keep_inds, toupdate_inds, cs_keep, keep_inds_S, toupdate_inds_S) = keepdata



    list_of_tbcs = list_of_tbcs[keepind]
    dft_list = dft_list[keepind]
    KPOINTS = KPOINTS[keepind]
    KWEIGHTS = KWEIGHTS[keepind]

    println("niters $niters")
    
    #SCF MODE
    scf = false
    for m in list_of_tbcs
        if !ismissing(m)
            scf = m.scf
            break
        end
    end
#    if list_of_tbcs[1].scf == true
#        scf = true
#    end
    println("SCF is $scf")
    
    if ismissing(energy_weight)
        energy_weight = 20.0
    end
    if ismissing(rs_weight)
        rs_weight = 0.0
    end
    if ismissing(ks_weight)
        ks_weight = 0.05
    end


    if ismissing(weights_list)
        weights_list = ones(Float64, length(list_of_tbcs))
    else
        weights_list = weights_list[keepind]
    end

#    KPOINTS, KWEIGHTS, nk_max = get_k(dft_list, length(list_of_tbcs))

#    toupdate_inds = Int64[]
#    keep_inds = Int64[]

#    println("redo lsq")
#    @time ch = X_H \ Y_H 

#=    
    if !ismissing(starting_database )

        
        nh=size(ch_lin)[1]
        ns=size(cs_lin)[1]
        println("using starting database, $nh $ns")
        
        ch_start, cs_start = extract_database(starting_database, nh, ns, KEYS, HIND, SIND)

        
        #merge h
        for i = 1:nh
            if abs(ch_start[i] + 999999.0) < 1e-7
                ch_start[i] = ch_lin[i]
                push!(toupdate_inds, i)
            else
                push!(keep_inds, i)
            end
        end
        
        
        #merge s
        for i = 1:ns
            if abs(cs_start[i] + 999999.0) < 1e-7
                cs_start[i] = cs_lin[i]
            end
        end
        
        cs = cs_start
        ch = ch_start

        if update_all == true
            toupdate_inds = 1:length(ch_lin) #all
            keep_inds = Int64[]
        end        
    else

        println("NO starting database")

        update_all = true
        toupdate_inds = 1:length(ch_lin) #all
        cs = cs_lin
        ch = ch_lin
    end
=#
    println("update_all $update_all")
    
    println("TOUPDATE_INDS ", length(toupdate_inds))

    #    cs = cs_lin
    #    ch = ch_lin
    
    println("NOW, DO RECURSIVE FITTING")
    
    NWAN_MAX = maximum(ind_BIG[:,3])
    NAT_MAX = 0
    for dft in dft_list
        NAT_MAX = max(NAT_MAX, dft.crys.nat)
    end

#    nk = size(kpoints)[1]
    NCALC = length(list_of_tbcs)

    VALS     = zeros(NCALC, nk_max, NWAN_MAX)
#    VECTS_MIX     = zeros(Complex{Float64}, NCALC, nk_max, NWAN_MAX, NWAN_MAX)
    VALS0     = zeros(NCALC, nk_max, NWAN_MAX)

    E_DEN     = zeros(NCALC, NWAN_MAX)
    H1     = zeros(NCALC, NWAN_MAX, NWAN_MAX)
    DQ     = zeros(NCALC, NAT_MAX)

    ENERGY_SMEAR = zeros(NCALC)

    OCCS     = zeros(NCALC, nk_max, NWAN_MAX)
    WEIGHTS     = zeros(NCALC, nk_max, NWAN_MAX)
    ENERGIES = zeros(NCALC)

    Ys = Ys_new + Xc_Snew_BIG
    X_Snew_BIG = nothing
    Xc_Snew_BIG = nothing

    NCOLS_orig = size(X_Hnew_BIG)[2]
    NCOLS = size(X_Hnew_BIG)[2]

#    println("redo lsq")
#    @time ch = X_H \ Y_H 
 
    ch=deepcopy(ch_lin)
    
    if !ismissing(ch_refit)
        println("using refit")
        for i = 1:length(ch)
            if abs(ch_refit[i]) > 1e-5
                ch[i] = ch_refit[i]
            end
        end
    end



    if start_small
        ch = ch / 10.0
    end
   
    keep_bool = true

#=
    if length(keep_inds) > 0 && update_all == false
        println("shrinking problem")
        
        X_Hnew_BIG_keep = X_Hnew_BIG[:,keep_inds]
        ch_keep = ch[keep_inds]
        Xc_keep = X_Hnew_BIG_keep * ch_keep

        Y_H = Y_H - X_H[:,keep_inds] * ch_keep
        X_H = X_H[:,toupdate_inds]

        println("redo lsq")
        @time ch = X_H \ Y_H 
        
        keep_bool = true

        X_Hnew_BIG = X_Hnew_BIG[:,toupdate_inds]
        NCOLS = size(X_Hnew_BIG)[2]

    else
        println("not shrinking problem")
        Xc_keep = zeros(size(X_Hnew_BIG)[1],1)
        ch_keep = []
        X_Hnew_BIG_keep = []

        keep_bool = false
        NCOLS = size(X_Hnew_BIG)[2]

        
    end
=#

    println("NCOLS $NCOLS")
    


    function get_electron_density(tbc, kpoints, kweights, vects, occ, S)

        nk = size(kpoints)[1]
        nw = size(S)[3]
        TEMP = zeros(Complex{Float64}, nw, nw)
        denmat = zeros(Float64, nw, nw)
        for k in 1:nk
            for a = 1:nw
                for i = 1:nw
                    for j = 1:nw
                        TEMP[i,j] = vects[k,i,a]' * S[k,i,j] * vects[k,j,a]
                    end
                end
                TEMP = TEMP + conj(TEMP)
                denmat += 0.5 * occ[k,a] * real.(TEMP) * kweights[k]
            end
        end
        electron_den = sum(denmat, dims=1) / sum(kweights)

#        println("size ", size(electron_den))
        h1, dq = get_h1(tbc, electron_den[:])
#        println("electron_den $electron_den")
#        println("dq ", dq)
#        h1a, dqa = get_h1(tbc, tbc.eden)
#        println("dqa ", dqa)
        
        return electron_den, h1, dq
        
    end

    #PREPARE REFERENCE ENERGIES / EIGENVALUES
#    println("prepare reference eigs")
    c=0
    NVAL = zeros(Float64, length(list_of_tbcs))
    NAT = zeros(Int64, length(list_of_tbcs))
    @time for (tbc, kpoints, kweights, d ) in zip(list_of_tbcs, KPOINTS, KWEIGHTS, dft_list)
        c+=1

        NAT[c] = tbc.crys.nat

        nw = ind_BIG[c, 3]
        nk = size(kpoints)[1]

        row1, rowN, nw = ind_BIG[c, 1:3]

        vmat     = zeros(Complex{Float64}, nk, nw, nw)
        smat     = zeros(Complex{Float64}, nk, nw, nw)


        wan, semicore, nwan, nsemi, wan_atom, atom_wan = tb_indexes(d)
        ind2orb, orb2ind, etotal_atoms, nval =  orbital_index(d.crys)

        NVAL[c] = nval

        band_en = band_energy(d.bandstruct.eigs[:,nsemi+1:end], d.bandstruct.kweights, nval)
        etypes = types_energy(d.crys)
        etot_dft = d.energy
        e_smear = d.energy_smear
        atomization_energy = etot_dft - etotal_atoms - etypes  - e_smear
        band_en = band_en 
        shift = (atomization_energy - band_en  )/nval

#        println("c atomization $atomization_energy $etot_dft $etotal_atoms $etypes $e_smear ")

        for k in 1:nk

            if !ismissing(tbc) 
                vects, vals, hk, sk, vals0 = Hk(tbc, kpoints[k,:])  #reference
                VALS[c,k,1:nw] = vals                           #reference
                VALS0[c,k,1:nw] = vals0                          #reference
                vmat[k, :,:] = vects
                smat[k, :,:] = sk
                
#            elseif !ismissing(tbc) && typeof(tbc) == tb_crys_kspace
#                println("tb_crys_kspace")
#                vects, vals, hk, sk, vals0 = Hk(tbc, kpoints[k,:])  #reference
#                VALS[c,k,1:nw] = vals                           #reference
 #               VALS0[c,k,1:nw] = vals0                          #reference
#                vmat[k, :,:] = vects
#                smat[k, :,:] = sk#

            else
                
#                println("missing tbc $c")
                for k2 in 1:d.bandstruct.nks
                    if sum(abs.(d.bandstruct.kpts[k2,:] - kpoints[k,:]) ) < 1e-5
                        VALS[c,k,:] .= 100.0
                        VALS0[c,k,:] .= 100.0

                        n = min(d.bandstruct.nbnd - nsemi, nw)
                        VALS[c,k,1:n] = d.bandstruct.eigs[k2,nsemi+1:nsemi+n] .+ shift
                        VALS0[c,k,1:n] = d.bandstruct.eigs[k2,nsemi+1:nsemi+n] .+ shift
                        

#                        println("$c DFT_val ",  d.bandstruct.eigs[k2,nsemi+1:end] .+ shift)
                    end
                end
            end

#            VECTS_MIX[c,k, 1:nw, 1:nw] = vects

            
        end

        

        energy_tmp,  efermi = band_energy(VALS[c,1:nk,1:nw], kweights, nval, 0.01, returnef=true) 

        occs = gaussian.(VALS[c,1:nk,1:nw].-efermi, 0.01)

        energy_smear = smearing_energy(VALS[c,1:nk,1:nw], kweights, efermi, 0.01)


        if !ismissing(tbc) && typeof(tbc) == tb_crys{Float64}
            eden, h1, dq = get_electron_density(tbc, kpoints, kweights, vmat, occs, smat)        
            E_DEN[c,1:nw] = eden
            H1[c,1:nw, 1:nw] = tbc.tb.h1
            DQ[c,1:tbc.crys.nat] = get_dq(tbc)
        end
        if !ismissing(tbc) && typeof(tbc) == tb_crys_kspace{Float64}
            eden, h1, dq = get_electron_density(tbc, kpoints, kweights, vmat, occs, smat)        
            E_DEN[c,1:nw] = eden
            H1[c,1:nw, 1:nw] = tbc.tb.h1
            DQ[c,1:tbc.crys.nat] = get_dq(tbc)
        end


        
#        H1[c,1:nw, 1:nw] = h1
#        DQ[c,1:tbc.crys.nat] = dq

        #        energy_band, occs = band_energy(VALS0[c,1:nk,1:nw], kweights, tbc.nelec, 0.01, returnocc=true)

        if !ismissing(tbc)
            s1 = sum(occs .* VALS0[c,1:nk,1:nw], dims=2)
            energy_band = sum(s1 .* kweights)
            if scf
                energy_charge, pot = ewald_energy(tbc, dq)
            else
                energy_charge = 0.0
            end
            etypes = types_energy(tbc)
            println(min(Int64(ceil(nval/2.0-1e-5)) + 1, nw)," $c CALC ENERGIES $etypes $energy_charge $energy_band $energy_smear = ", etypes + energy_charge + energy_band + energy_smear)
            ENERGIES[c] = etypes + energy_charge + energy_band + energy_smear
        else
            ENERGIES[c] = etot_dft - etotal_atoms
        end


        #ENERGIES[c] = tbc.dftenergy

        #        println("en $energy_band $energy_charge $etypes $energy_smear x $efermi " , ENERGIES[c])
        
        OCCS[c,1:nk,1:nw] = occs

#        etmp, occs = band_energy(VALS[c,1:nk,1:nw], kweights, tbc.nelec+.05, 0.05, returnocc=true)
#        etmp, occs2 = band_energy(VALS[c,1:nk,1:nw], kweights, tbc.nelec+0.99, 0.1, returnocc=true)


        if true

            nweight = min(Int64(ceil(nval/2.0-1e-5)) + 1, nw)
            occs2 = zeros(size(occs))
            occs2[:,1:nweight] .= 0.5
            occs2[:,nweight] .= 0.5
            occs2[:,1] .= 0.5
#            occs2[1,1] = 5.0

            if !ismissing(tbc)
                etmp, occs3 = band_energy(VALS[c,1:nk,1:nw], kweights, nval+0.25, 0.1, returnocc=true)
            else
                etmp, occs3 = band_energy(VALS[c,1:nk,1:nw], kweights, nval+0.25, 0.1, returnocc=true)
            end
           
            WEIGHTS[c,1:nk,1:nw] = (occs + occs2 + occs3)/3.0


        else

            nweight = min(Int64(ceil(nval/2.0-1e-5)) + 1, nw)
            occs2 = zeros(size(occs))
            occs2[:,1:nweight] .= 0.3
            occs2[:,nweight] .= 0.1
            occs2[:,1] .= 0.5
            if !ismissing(tbc)
                etmp, occs3 = band_energy(VALS[c,1:nk,1:nw], kweights, nval+0.95, 0.1, returnocc=true)
            else
                etmp, occs3 = band_energy(VALS[c,1:nk,1:nw], kweights, nval+0.25, 0.1, returnocc=true)
            end
           
            WEIGHTS[c,1:nk,1:nw] = (occs + occs2 + occs3)/3.0

        end


        if !ismissing(tbc)
            WEIGHTS[c,:,:] .+= RW_PARAM
        end

#double check
        for k = 1:nk
            for i = 1:nw
                if VALS[c,k,i] > 99.0 
                    WEIGHTS[c,k,i] = 0.0
                end
            end
        end

        if ismissing(tbc)
            tbc_fake = calc_tb_fast(d.crys)
            tbc = tbc_fake
        end


#        WEIGHTS[c,1,1:nw] = WEIGHTS[c,1,1:nw] * 100

    end

    
#        ENERGIES[c], occs = band_energy(VALS[c,1:nk,1:nw], kweights, tbc.nelec, 0.01, returnocc=true)
#        OCCS[c,1:nk,1:nw] = occs

#        etmp, occs = band_energy(VALS[c,1:nk,1:nw], kweights, tbc.nelec+.05, 0.05, returnocc=true)
#        WEIGHTS[c,1:nk,1:nw] = occs#

#    end

#    return ENERGIES


#=
    #DFT ONLY
    @time for d in dftonly_list:

        c+=1

        ind2orb, orb2ind, etotal_atoms, nval =  orbital_index(d.crys)
        band_en = band_energy(d.bandstruct.eigs[:,nsemi+1:end], d.bandstruct.kweights, nval)
        etypes = types_energy(d.crys)
        etot_dft = d.energy
        shift_energy = etot_dft - etotal_atoms - etypes
        shift = (atomization_energy - band_en  )/nval

        shifted_eigs = d.bs.eigs[nsemi+1:end] .+ shift
        
        s = size(shifted_eigs, 1)

        VALS[c,k,1:nw] = shifted_eigs
        
        etmp, occs = band_energy(VALS[c,1:nk,1:nw], kweights, tbc.nelec+.05, 0.05, returnocc=true)
        WEIGHTS[c,1:nk,1:nw] = occs
 
=#
        

    println("EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE")
    println("REFERENCE ENERGIES ")

    for c = 1:NCALC
        println(ENERGIES[c], "  $c   ", DQ[c,:])
    end
    println("EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE")

    
    VALS_working = zeros(size(VALS))
    ENERGIES_working = zeros(size(ENERGIES))
    OCCS_working = zeros(size(OCCS))


    verbose=0

    function construct_fitted(ch, solve_self_consistently = false)

        Xc = (X_Hnew_BIG * ch) + Xc_Hnew_BIG

#        VECTS_FITTED     = zeros(Complex{Float64}, NCALC, nk_max, NWAN_MAX, NWAN_MAX)
        VECTS_FITTED = Dict{Int64, Array{Complex{Float64},3} }()
        VALS_FITTED     = zeros(NCALC, nk_max, NWAN_MAX)
        VALS0_FITTED     = zeros(NCALC, nk_max, NWAN_MAX)
        OCCS_FITTED     = zeros(NCALC, nk_max, NWAN_MAX)
        ENERGIES_FITTED = zeros(NCALC)
        c=0

        ERROR = zeros(Int64, NCALC)

        if solve_self_consistently == true
            println("SCF SOLUTIONS")
            niter_scf = 150
        else
            niter_scf = 0
        end
        
        for (tbc, kpoints, kweights, dft) in zip(list_of_tbcs, KPOINTS, KWEIGHTS, dft_list)
            c+=1

            nval = NVAL[c]

            etypes = types_energy(dft.crys)

            nw = ind_BIG[c, 3]
            nk = size(kpoints)[1]

            row1, rowN, nw = ind_BIG[c, 1:3]

            H0 = zeros(Complex{Float64}, nw, nw)
            H = zeros(Complex{Float64}, nw, nw)
            S = zeros(Complex{Float64}, nw, nw)

            Smat = zeros(Complex{Float64}, nk, nw, nw)
            H0mat = zeros(Complex{Float64}, nk, nw, nw)

            N = hermetian_indpt(nw)

            SS = zeros(Complex{Float64}, nw, nw)


            for k in 1:nk 
                
                #fitted eigenvectors / vals
                for i = 1:nw
                    for j = 1:nw
                        if i <= j
                            ind = hermetian_index(i,j, nw)
                            H0[i,j] = Xc[row1-1 + (k-1)*N + ind] + im*Xc[row1-1 + (k-1)*N + ind + nk * N]  + h_on[c][i, j]
                            S[i,j] = Ys[row1-1 + (k-1)*N + ind] + im*Ys[row1-1 + (k-1)*N + ind + nk * N]

                            H0[j,i] = Xc[row1-1 + (k-1)*N + ind] - im*Xc[row1-1 + (k-1)*N + ind + nk * N]  + h_on[c][j, i]
                            S[j,i] = Ys[row1-1 + (k-1)*N + ind] - im*Ys[row1-1 + (k-1)*N + ind + nk * N]
                            
                            SS[i,j] = Y_Snew_BIG[row1-1 + (k-1)*N + ind] + im*Y_Snew_BIG[row1-1 + (k-1)*N + ind + nk * N]
                            SS[j,i] = Y_Snew_BIG[row1-1 + (k-1)*N + ind] - im*Y_Snew_BIG[row1-1 + (k-1)*N + ind + nk * N]

                            #                            H0[i,j] = Xc[row1-1 + (k-1)*nw*nw + (i-1)*nw + j] + im*Xc[row1-1 + (k-1)*nw*nw + (i-1)*nw + j + nk*nw*nw]  + h_on[c][i, j]
#                            S[ i,j] = Ys[row1-1 + (k-1)*nw*nw + (i-1)*nw + j] + im*Ys[row1-1 + (k-1)*nw*nw + (i-1)*nw + j + nk*nw*nw]
                        end
                    end
                    S[ i,i] += 1.0 #onsite
                end
                H0 = (H0+H0')/2.0
                S = (S+S')/2.0


                Smat[k,:,:] = S
                H0mat[k,:,:] = H0
            end

            if scf
                h1 = deepcopy(H1[c,1:nw,1:nw])
                dq = deepcopy(DQ[c,1:dft.crys.nat])
            else
                h1 = zeros(Float64, nw, nw)
                dq = zeros(dft.crys.nat)
            end

#            println("STARTING DQ")
#            println(dq)
#            println("STARTING H1")
#            println(h1)
#            println()
            function get_eigen(h1_in)
                vals = zeros(Float64, nw)
                vects = zeros(Complex{Float64}, nw, nw)
                VECTS = zeros(Complex{Float64}, nk, nw, nw)
                for k in 1:nk 
                    
                    H0 = H0mat[k,:,:]
                    S  = Smat[k,:,:]
                    if scf
                        H = H0 + h1_in .* S
                    else
                        H[:,:] = H0[:,:]
                    end

                    try
                        vals, vects = eigen(H, S)
                    catch

                        ERROR[c] = 1
                        vals = zeros(Float64, nw)
                        vects = zeros(Complex{Float64}, nw, nw)
                        println("WARNING, S has negative eigenvalues $c $k")
                        
#                        println("H $c $k")
#                        println(H)
#                        println("S")
#                        println(S)
#                        v,vv = eigen(S)
#                        println(v)
#                        throw(UndefVarError(:xxqxqxqxxqqx))
                    end

#                    VECTS_FITTED[c,k,1:nw,1:nw] = vects
                    VECTS[k,1:nw,1:nw] = vects
                    VALS_FITTED[c,k,1:nw] = real(vals)
#                    VALS_FITTED[c,k,1:nw] = real.(diag(vects'*H*vects))

                    VALS0_FITTED[c,k,1:nw] =  real.(diag(vects'*H0*vects))
                    
#                    if k == 1
#                        println("VALS ", VALS_FITTED[c,k,1:nw])
#                        println("VALS0", VALS0_FITTED[c,k,1:nw])
#                    end
                end #kpoints loop
                VECTS_FITTED[c] = deepcopy(VECTS)

            end
                
            
            energy_old = 1000.0
            conv = false

            for c_scf = 1:niter_scf
                
                get_eigen(h1)
                
#                if c_scf == 1
#                    println("$c VALS_FITTED k0 ", VALS_FITTED[c,1,1:nw])
#                    println("$c VALS0_FITTED k0 ", VALS0_FITTED[c,1,1:nw])
#                end

                if solve_self_consistently == true

                    mix = 0.7 * 0.92^c_scf  #start aggressive, reduce mixing slowly if we need most iterations

                    
#                    energy_tmp,efermi   = band_energy(VALS_FITTED[c,1:nk,1:nw], kweights, tbc.nelec, 0.01, returnef=true) 

                    efermi = calc_fermi(VALS_FITTED[c,1:nk,1:nw], kweights, nval, 0.01)
                    occs = gaussian.(VALS_FITTED[c,1:nk,1:nw].-efermi, 0.01)
                    
                    energy_smear = smearing_energy(VALS_FITTED[c,1:nk,1:nw], kweights, efermi, 0.01)

#                    eden, h1_new, dq_new = get_electron_density(tbc, kpoints, kweights, VECTS_FITTED[c,:,1:nw,1:nw], occs, Smat)         #updated h1
                    eden, h1_new, dq_new = get_electron_density(tbc, kpoints, kweights, VECTS_FITTED[c], occs, Smat)         #updated h1

                    s1 = sum(occs .* VALS0_FITTED[c,1:nk,1:nw], dims=2)
                    energy_band = sum(s1 .* kweights)

                    if maximum(abs.(dq - dq_new)) > 0.1
                        mix = 0.01
                    end

                    h1 = h1*(1-mix) + h1_new * mix
                    dq = dq*(1-mix) + dq_new * mix

                    
                    energy_charge, pot = ewald_energy(tbc, dq)
                    
                    energy_new = energy_charge + energy_band + energy_smear

#                    println( " scf $c_scf $c ", energy_new+etypes, "    $dq   $energy_charge $energy_band $energy_smear")

                    if abs(energy_new  - energy_old) < 1e-5
#                        println("scf converged  $c ", energy_new+etypes, "    $dq " )
                        conv = true
                        break
                    end
                    energy_old = energy_new
                    
                end
                
            end #scf loop

            if scf && conv
#                h1 = (h1 + H1[c,1:nw,1:nw]) / 2.0   #mixing
#                dq = (dq + DQ[c,1:tbc.crys.nat]) / 2.0

                H1[c,1:nw,1:nw] =  h1 
                DQ[c,1:tbc.crys.nat] = dq

            elseif scf

                h1 = (h1 + H1[c,1:nw,1:nw]) / 2.0   #mixing
                dq = (dq + DQ[c,1:tbc.crys.nat]) / 2.0

                H1[c,1:nw,1:nw] =  h1 
                DQ[c,1:tbc.crys.nat] = dq


            end


            get_eigen(h1)
            
            efermi = calc_fermi(VALS_FITTED[c,1:nk,1:nw], kweights, nval, 0.01)
            occs = gaussian.(VALS_FITTED[c,1:nk,1:nw].-efermi, 0.01)
            OCCS_FITTED[c,1:nk,1:nw] = occs

#            energy_tmp, occs_fitted = band_energy(VALS_FITTED[c,1:nk,1:nw], kweights, tbc.nelec, 0.01, returnocc=true)
#            OCCS_FITTED[c,1:nk,1:nw] = occs_fitted
            
            energy_smear = smearing_energy(VALS_FITTED[c,1:nk,1:nw], kweights, efermi, 0.01)
            ENERGY_SMEAR[c] = energy_smear

#            println("$c smear $energy_smear")

            
#            if scf
#                energy_charge, pot = ewald_energy(tbc, dq)
#            else
#                energy_charge = 0.0
            #            end
#            
#            etypes = types_energy(tbc)

            s1 = sum(occs .* VALS0_FITTED[c,1:nk,1:nw], dims=2)
            energy_band = sum(s1 .* kweights)

            if scf
                energy_charge, pot = ewald_energy(tbc, dq)
            else
                energy_charge = 0.0
            end


            
            ENERGIES_FITTED[c] = etypes + energy_charge + energy_band + energy_smear
            println("scf $conv $c ", ENERGIES_FITTED[c], " d  ", ENERGIES_FITTED[c] - ENERGIES[c], "    $dq " )


        end

        return ENERGIES_FITTED, VECTS_FITTED, VALS_FITTED, OCCS_FITTED, VALS0_FITTED, ERROR

    end


    if lambda > 1e-10
        NLAM = NCOLS
#        println("alt lambda ", NLAM, " " , NCOLS)
    else
        NLAM  = 0
    end
    NLAM = Int64(NLAM)


    
#    function construct_newXY(VECTS_FITTED::Array{Complex{Float64},4}, OCCS_FITTED::Array{Float64,3}, ncalc::Int64, ncols::Int64, nlam::Int64, ERROR::Array{Int64,1}; leave_out=-1)
    function construct_newXY(VECTS_FITTED, OCCS_FITTED::Array{Float64,3}, ncalc::Int64, ncols::Int64, nlam::Int64, ERROR::Array{Int64,1}; leave_out=-1)


#        nlam = 0

#        NEWX = zeros(ncalc*nk_max*NWAN_MAX + ncalc + nlam, ncols)
#        NEWY = zeros(ncalc*nk_max*NWAN_MAX + ncalc + nlam)

        counter = 0

        temp = 0.0+0.0*im
        
        nonzero_ind = Int64[]
        #count nonzero ahead of time
        for calc = 1:ncalc
            if calc == leave_out #skip this one
                continue
            end
            if ERROR[calc] == 1
                continue
            end
            row1, rowN, nw = ind_BIG[calc, 1:3]
            N = hermetian_indpt(nw)
            vals = ones(nw) * 100.0
            nk = size(KPOINTS[calc])[1]
            for k = 1:nk
                for i = 1:nw
                    counter += 1
                    push!(nonzero_ind, counter)
                end
            end
            counter += 1
            push!(nonzero_ind, counter)
        end

        NEWX = zeros(counter + nlam, ncols)
        NEWY = zeros(counter + nlam)
        
        counter = 0

        for calc = 1:ncalc

            if calc == leave_out #skip this one
                continue
            end
            if ERROR[calc] == 1
                continue
            end

            row1, rowN, nw = ind_BIG[calc, 1:3]
            N = hermetian_indpt(nw)

            vals = ones(nw) * 100.0
            #            H = zeros(Complex{Float64}, nw, nw, ncols)
            #            H = zeros(Complex{Float64}, nw, nw)
            H_cols = zeros(Complex{Float64}, nw, nw, ncols)
            
            H_fixed = zeros(Complex{Float64}, nw, nw)
            
            
            #            H_cols = H_COLS[calc]
            
            VECTS = zeros(Complex{Float64}, nw, nw)
            #            S = zeros(Complex{Float64}, nw, nw)
            nk = size(KPOINTS[calc])[1]
            
            X_TOTEN = zeros(ncols)
            Y_TOTEN = ENERGIES[calc]
            
            if scf
                nat = dft_list[calc].crys.nat
                energy_charge, pot = ewald_energy(list_of_tbcs[calc], DQ[calc,1:nat])
            else
                energy_charge = 0.0
            end
            etypes = types_energy(dft_list[calc].crys)
            
            energy_smear = ENERGY_SMEAR[calc]

            Y_TOTEN -= energy_charge + etypes + energy_smear
            
            VECTS = zeros(Complex{Float64}, nw, nw)
            VECTS_p = zeros(Complex{Float64}, nw, nw)

            vals_test_other = zeros(nw, ncols)
            vals_test_on = zeros(nw)
            
            for k = 1:nk
                for i = 1:nw
                    for j = 1:nw
                        if i <= j
                            #                            H_cols[i,j,:] = X_Hnew_BIG[row1-1 + (k-1)*nw*nw + (i-1)*nw + j,:] + im*X_Hnew_BIG[row1-1 + (k-1)*nw*nw + (i-1)*nw + j + nk*nw*nw,:]
                            ind = hermetian_index(i,j, nw)
                            H_cols[i,j,:] = X_Hnew_BIG[row1-1 + (k-1)*N + ind,:] + im*X_Hnew_BIG[row1-1 + (k-1)*N + ind +  nk*N,:]
                            H_cols[j,i,:] = X_Hnew_BIG[row1-1 + (k-1)*N + ind,:] - im*X_Hnew_BIG[row1-1 + (k-1)*N + ind +  nk*N,:]                            
                        end
                        
                    end
                end
                for i = 1:nw
                    for j = 1:nw
                        if keep_bool
                            if i <= j
                                ind = hermetian_index(i,j, nw)
                                H_fixed[i,j] = Xc_Hnew_BIG[row1-1 + (k-1)*N + ind] + im*Xc_Hnew_BIG[row1-1 + (k-1)*N + ind +  nk*N]
                                H_fixed[j,i] = Xc_Hnew_BIG[row1-1 + (k-1)*N + ind] - im*Xc_Hnew_BIG[row1-1 + (k-1)*N + ind +  nk*N]
                                
                            end
#                            H_fixed[i,j] = Xc_keep[row1-1 + (k-1)*nw*nw + (i-1)*nw + j] + im*Xc_keep[row1-1 + (k-1)*nw*nw + (i-1)*nw + j + nk*nw*nw]
                        end
                    end
                end


#                VECTS[:,:] = VECTS_FITTED[calc,k,1:nw,1:nw]
                VECTS[:,:] = VECTS_FITTED[calc][k,1:nw,1:nw]
                VECTS_p[:,:] = VECTS'

                if keep_bool
                    vals_test_on[:] = real(diag(VECTS_p * (h_on[calc] + H_fixed) * VECTS)) 
                else
                    vals_test_on[:] = real(diag(VECTS_p * (h_on[calc] ) * VECTS)) 
                end
                
                vals_test_other[:,:] .= 0.0

#                @time for i = 1:nw
#                    for j = 1:nw
#                        for kk = 1:nw
#                            for ii = 1:ncols
#                                vals_test_other[i,ii] += real(VECTS_p[i,j] .* H_cols[ j,kk,ii]  .* VECTS[kk,i])
#                            end
#                        end
#                    end
#                end

                for ii = 1:ncols
                    for i = 1:nw
                        temp = 0.0+0.0im
                        for kk = 1:nw
                            for j = 1:nw
                                temp += VECTS_p[i,j] * H_cols[ j,kk,ii]  * VECTS[kk,i]
                            end
                        end
                        vals_test_other[i,ii] += real(temp)
                    end
                end
                
                for i = 1:nw
                    counter += 1


                    NEWX[counter, :] = vals_test_other[i,:] .* WEIGHTS[calc, k, i]
                    X_TOTEN[:] +=   vals_test_other[i,:] .* (KWEIGHTS[calc][k] * OCCS_FITTED[calc,k,i])

                    NEWY[counter] =  (VALS0[calc,k,i] - vals_test_on[i]) .* WEIGHTS[calc, k, i]
                    Y_TOTEN += -1.0 * vals_test_on[i] * (KWEIGHTS[calc][k] * OCCS_FITTED[calc,k,i])

                    push!(nonzero_ind, counter)

                       ###println("$calc $k $i : ",  vals_test[i], "\t" , VALS_FITTED[calc,k,i],"\t", vals_test_on[i] + vals_test_other[i,:]'*ch)
                end
                
                
            end
            counter += 1
            NEWX[counter, :] = X_TOTEN[:] * energy_weight * weights_list[calc]
            NEWY[counter] = Y_TOTEN * energy_weight * weights_list[calc]
            push!(nonzero_ind, counter)

        end

        if lambda > 1e-10
            for ind3 = 1:nlam
                counter += 1
                NEWX[counter,ind3] = lambda
                push!(nonzero_ind, counter)

            end
        end

#        println("len nonzero_ind ", length(nonzero_ind))
#        println("size NEWX old ", size(NEWX))
#        NEWX = NEWX[nonzero_ind,:]
#        NEWY = NEWY[nonzero_ind]
#        println("size NEWX new ", size(NEWX))
#        println("size NEWY new ", size(NEWY))

        return NEWX, NEWY

    end

    solve_scf_mode = false



    function do_iters(chX, NITERS; leave_out=-1)

        err_old_en = 1.0e6

        mix = 0.01



        
        for iters = 1:NITERS #inner loop

            if iters > 5
                mix = 0.1
            end

            if scf
                if iters == 1 println("TURNING ON SCF SOLVE!!!!!!!!!!!!!!!!!!!!!!! ") end
                println()
                solve_scf_mode = true
            end

            println("DOING ITER $iters -------------------------------------------------------------")

            #        println("construct_fitted")
            @time ENERGIES_working, VECTS_FITTED, VALS_FITTED, OCCS_FITTED, VALS0_FITTED, ERROR = construct_fitted(chX, solve_scf_mode)

            
            #, VALS0_FITTED #, solve_scf_mode
            println("energies_working")
            println(ENERGIES_working)

            println("construct_newXY")
            println(typeof(chX))
            println(typeof(VECTS_FITTED))
            println(typeof(OCCS_FITTED))
            println(typeof(NCALC))
            println(typeof(NCOLS))
            println(typeof(NLAM))
            println(typeof(leave_out))
                    
            @time NEWX, NEWY = construct_newXY(VECTS_FITTED, OCCS_FITTED, NCALC, NCOLS, NLAM, ERROR, leave_out=leave_out)

            VECTS_FITTED = Dict()
#            VECTS_FITTED = []
#            OCCS_FITTED = []
#            VALS_FITTED = []
#            VALS0_FITTED = []
            
            
#            println("rs")

            println("size NEWX ", size(NEWX))
            println("size NEWY ", size(NEWY))

            println("size X_Hnew_BIG ", size(X_Hnew_BIG))
            println("size Y_Hnew_BIG ", size(Y_Hnew_BIG))

            TOTX = NEWX
            TOTY = NEWY

            if rs_weight > 1e-5
                TOTX = [X_H*rs_weight;TOTX]
                TOTY = [Y_H*rs_weight;TOTY]
            end            
            if ks_weight > 1e-5

                l = length(Y_Hnew_BIG) #randomly sample Hk to keep size reasonable
                if l > 5e5
                    frac = 5e5 / l
                    println("randsubseq $frac")
                    rind = randsubseq( 1:l, frac)
                else
                    rind = 1:l
                end

                TOTX = [X_Hnew_BIG[rind,:]*ks_weight;TOTX]
                TOTY = [Y_Hnew_BIG[rind]*ks_weight;TOTY]
            end            


#            if lambda > 1e-10
#                XX = zeros(length(threebody_inds), NCOLS)
#                YY = zeros(length(threebody_inds))
#                for (ii, ind3) in enumerate(threebody_inds)
#                    XX[ii,ind3] = lambda
#                end

#                TOTX = [TOTX; XX]
#                TOTY = [TOTY; YY]
                
#                TOTX = [TOTX; lambda*collect(I(NCOLS))]
#                TOTY = [TOTY; zeros(NCOLS)]

#            end
            println("errors")
            @time if true
#                error_old_rs  = sum((X_H * chX .- Y_H).^2)
                error_old_energy  = sum((NEWX * chX .- NEWY).^2)
#                error_old = error_old_rs + error_old_energy
            end
            
            ch_old = deepcopy(chX)
            println("lsq")

            println("size TOTX ", size(TOTX))
            println("size TOTY ", size(TOTY))


            @time ch_new = TOTX \ TOTY
            println("new errors")
            @time if true
                chX = (ch_old * (1-mix) + ch_new * (mix) )
                
#                error_new_rs  = sum((X_H * chX .- Y_H).^2)
                error_new_energy  = sum((NEWX * chX .- NEWY).^2)
                
#                error_new = error_new_rs + error_new_energy
                
#                println("errors rs     new $error_new_rs old $error_old_rs")
                println("errors energy new $error_new_energy old $error_old_energy")
#                println("errors tot    new $error_new old $error_old")
                println()
            end

            if abs(error_new_energy - err_old_en) < 5e-3 && iters >= 6
                println("break")
                break
            else
                err_old_en = error_new_energy
            end

            if error_new_energy > (err_old_en + 1e-5) &&  iters > 3
                mix = max(mix * 0.9, 0.05)
                println("energy increased, reduce mixing $mix")
            end
#            err_old_en = error_new_energy
            
            
        end

        #remerge the indexs we are updating with the other indexes

        ch_big = zeros(length(keep_inds) + length(toupdate_inds))
        #println(length(keep_inds), " " , length(toupdate_inds))

        ch_big[toupdate_inds] = chX[:]
        ch_big[keep_inds] = ch_keep[:]
        chX2 = ch_big
        
        cs_big = zeros(length(keep_inds_S) + length(toupdate_inds_S))
        cs_big[toupdate_inds_S] = cs_lin[:]
        cs_big[keep_inds_S] = cs_keep[:]
        csX2 = cs_big

#        else
#            chX2 = deepcopy(chX)
#            csX2 = deepcopy(cs_lin)
#        end

        

        good =  (abs.(ENERGIES - ENERGIES_working) ./ NAT) .< 0.05

        println("good")
        println(good)
        println("make database")

        database = make_database(chX2, csX2,  KEYS, HIND, SIND,DMIN_TYPES,DMIN_TYPES3, scf=scf, starting_database=starting_database, tbc_list = list_of_tbcs[good])

        return database, chX

    end

    if rs_weight < 1e-5
        X_H = nothing
        Y_H = nothing
    end
#    if ks_weight < 1e-5
#        X_Hnew_BIG = nothing
#        Y_Hnew_BIG = nothing
#    end            

    
    if leave_one_out == false
        database, ch =  do_iters(ch, niters)
        println("return")
        return database
    else
        database, ch =  do_iters(ch, niters)
        D = []
        for leave = 1:NCALC
            dat, ch_temp = do_iters(deepcopy(ch), 5, leave_out=leave)
            push!(D,deepcopy(dat))
        end
        return D
    end

#    return database

end

#----------------------------------------------------------------------------------------------------------------------------------------------------------------------
#=
function do_fitting_recursive_all(list_of_tbcs; dft_list=missing,X_cv = missing, kpoints = [0 0 0; 0 0 0.5; 0 0.5 0.5; 0.5 0.5 0.5],  atoms_to_fit=missing, fit_threebody=true, fit_threebody_onsite=true, do_plot = false, energy_weight = missing, rs_weight=missing)

    
    #SCF MODE
    scf = false
    if list_of_tbcs[1].scf == true
        scf = true
    end
    println("SCF is $scf")
    
    if ismissing(energy_weight)
        energy_weight = 100.0
    end
    if ismissing(rs_weight)
        rs_weight = 0.0
    end

    if ismissing(dft_list)
        println("using entered kpoints instead of DFT list!!!!!!!!!!!")
        KPOINTS = []
        KWEIGHTS = []
        nk_max = size(kpoints)[1]
        nk = size(kpoints)[1]
        kweights = ones(Float64, nk)/nk * 2.0
        for n = 1:length(list_of_tbcs)
            push!(KPOINTS, kpoints)
            push!(KWEIGHTS, kweights)

        end
    else
        println("using dft list")
        KPOINTS = []
        KWEIGHTS = []
        nk_max = 1
        for n = 1:length(list_of_tbcs)

            kpts = dft_list[n].bandstruct.kpts
            wghts = dft_list[n].bandstruct.kweights

#randomly downselect kpoints of number kpoints > 150            
            if size(kpts)[1] > 150
                println("limit kpoints to 150, from ",  size(kpts)[1])
                N = randperm(size(kpts)[1])
                kpts = kpts[N[1:150],:]
                wghts = wghts[N[1:150]]
                sw = sum(wghts)
                wghts = wghts * (2.0/sw)
            end

            push!(KPOINTS, kpts)
            push!(KWEIGHTS, wghts)
            
#            push!(KPOINTS, dft_list[n].bandstruct.kpts)
#            push!(KWEIGHTS, dft_list[n].bandstruct.kweights)
            nk_max = max(size(dft_list[n].bandstruct.kpts)[1], nk_max)

        end
    end        


    println("DO LINEAR FITTING")

    database, ch, cs, X_Hnew_BIG, Y_Hnew_BIG, X_H, X_Snew_BIG, Y_H, h_on, ind_BIG, KEYS, HIND, SIND = do_fitting_linear(list_of_tbcs; kpoints = KPOINTS,  atoms_to_fit=atoms_to_fit, fit_threebody=fit_threebody, fit_threebody_onsite=fit_threebody_onsite, do_plot = false)

    println("NOW, DO RECURSIVE FITTING")
    
    NWAN_MAX = maximum(ind_BIG[:,3])
    NAT_MAX = 0
    for tbc in list_of_tbcs
        NAT_MAX = max(NAT_MAX, tbc.crys.nat)
    end

#    nk = size(kpoints)[1]
    ncalc = length(list_of_tbcs)

    VALS     = zeros(ncalc, nk_max, NWAN_MAX)
#    VECTS_MIX     = zeros(Complex{Float64}, ncalc, nk_max, NWAN_MAX, NWAN_MAX)
    VALS0     = zeros(ncalc, nk_max, NWAN_MAX)

    E_DEN     = zeros(ncalc, NWAN_MAX)
    H1     = zeros(ncalc, NWAN_MAX, NWAN_MAX)
    DQ     = zeros(ncalc, NAT_MAX)

    OCCS     = zeros(ncalc, nk_max, NWAN_MAX)
    WEIGHTS     = zeros(ncalc, nk_max, NWAN_MAX)
    ENERGIES = zeros(ncalc)


    
    Ys = X_Snew_BIG * cs

    NCOLS = size(X_Hnew_BIG)[2]

    println("NCOLS $NCOLS")

    function get_electron_density(tbc, kpoints, kweights, vects, occ, S)

        nk = size(kpoints)[1]
        nw = size(S)[3]
        TEMP = zeros(Complex{Float64}, nw, nw)
        denmat = zeros(Float64, nw, nw)
        for k in 1:nk
            for a = 1:nw
                for i = 1:nw
                    for j = 1:nw
                        TEMP[i,j] = vects[k,i,a]' * S[k,i,j] * vects[k,j,a]
                    end
                end
                TEMP = TEMP + conj(TEMP)
                denmat += 0.5 * occ[k,a] * real.(TEMP) * kweights[k]
            end
        end
        electron_den = sum(denmat, dims=1) / sum(kweights)

#        println("size ", size(electron_den))
        h1, dq = get_h1(tbc, electron_den[:])
#        println("electron_den $electron_den")
#        println("dq ", dq)
#        h1a, dqa = get_h1(tbc, tbc.eden)
#        println("dqa ", dqa)
        
        return electron_den, h1, dq
        
    end

    #PREPARE REFERENCE ENERGIES / EIGENVALUES
#    println("prepare reference eigs")
    c=0
    @time for (tbc, kpoints, kweights) in zip(list_of_tbcs, KPOINTS, KWEIGHTS)
        c+=1
        nw = ind_BIG[c, 3]
        nk = size(kpoints)[1]

        row1, rowN, nw = ind_BIG[c, 1:3]

        vmat     = zeros(Complex{Float64}, nk, nw, nw)
        smat     = zeros(Complex{Float64}, nk, nw, nw)

        for k in 1:nk
            vects, vals, hk, sk, vals0 = Hk(tbc.tb, kpoints[k,:])  #reference
            VALS[c,k,1:nw] = vals                           #reference
            VALS0[c,k,1:nw] = vals0                          #reference
#            VECTS_MIX[c,k, 1:nw, 1:nw] = vects
            vmat[k, :,:] = vects
            smat[k, :,:] = sk

            
        end

        

        energy_tmp,  occs = band_energy(VALS[c,1:nk,1:nw], kweights, tbc.nelec, 0.01, returnocc=true) 

        eden, h1, dq = get_electron_density(tbc, kpoints, kweights, vmat, occs, smat)        
        E_DEN[c,1:nw] = eden

        H1[c,1:nw, 1:nw] = tbc.tb.h1
        DQ[c,1:tbc.crys.nat] = get_dq(tbc)
        
#        H1[c,1:nw, 1:nw] = h1
#        DQ[c,1:tbc.crys.nat] = dq

        #        energy_band, occs = band_energy(VALS0[c,1:nk,1:nw], kweights, tbc.nelec, 0.01, returnocc=true)

        s1 = sum(occs .* VALS0[c,1:nk,1:nw], dims=2)
        energy_band = sum(s1 .* kweights)
        if scf
            energy_charge, pot = ewald_energy(tbc, dq)
        else
            energy_charge = 0.0
        end
        etypes = types_energy(tbc)

        ENERGIES[c] = etypes + energy_charge + energy_band
        #ENERGIES[c] = tbc.dftenergy

        #        println("en $energy_band $energy_charge $etypes")
        
        OCCS[c,1:nk,1:nw] = occs

        etmp, occs = band_energy(VALS[c,1:nk,1:nw], kweights, tbc.nelec+.05, 0.05, returnocc=true)
        WEIGHTS[c,1:nk,1:nw] = occs

    end

    
#        ENERGIES[c], occs = band_energy(VALS[c,1:nk,1:nw], kweights, tbc.nelec, 0.01, returnocc=true)
#        OCCS[c,1:nk,1:nw] = occs

#        etmp, occs = band_energy(VALS[c,1:nk,1:nw], kweights, tbc.nelec+.05, 0.05, returnocc=true)
#        WEIGHTS[c,1:nk,1:nw] = occs#

#    end

#    return ENERGIES

    println("EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE")
    println("REFERENCE ENERGIES ")

    for c = 1:ncalc
        println(ENERGIES[c], "  $c   ", DQ[c,:])
    end
    println("EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE")

        
    
    VALS_working = zeros(size(VALS))
    ENERGIES_working = zeros(size(ENERGIES))
    OCCS_working = zeros(size(OCCS))

    WEIGHTS = WEIGHTS .+ 0.20

    verbose=0

    function construct_fitted(ch, solve_self_consistently = false)

        Xc = X_Hnew_BIG * ch


        VECTS_FITTED     = zeros(Complex{Float64}, ncalc, nk_max, NWAN_MAX, NWAN_MAX)
        VALS_FITTED     = zeros(ncalc, nk_max, NWAN_MAX)
        VALS0_FITTED     = zeros(ncalc, nk_max, NWAN_MAX)
        OCCS_FITTED     = zeros(ncalc, nk_max, NWAN_MAX)
        ENERGIES_FITTED = zeros(ncalc)
        c=0

        if solve_self_consistently == true
            println("SCF SOLUTIONS")
            niter_scf = 150
        else
            niter_scf = 0
        end
        
        for (tbc, kpoints, kweights) in zip(list_of_tbcs, KPOINTS, KWEIGHTS)
            c+=1

            etypes = types_energy(tbc)

            nw = ind_BIG[c, 3]
            nk = size(kpoints)[1]

            row1, rowN, nw = ind_BIG[c, 1:3]

            H0 = zeros(Complex{Float64}, nw, nw)
            H = zeros(Complex{Float64}, nw, nw)
            S = zeros(Complex{Float64}, nw, nw)

            Smat = zeros(Complex{Float64}, nk, nw, nw)
            H0mat = zeros(Complex{Float64}, nk, nw, nw)


            for k in 1:nk 
                
                #fitted eigenvectors / vals
                for i = 1:nw
                    for j = 1:nw
                        H0[i,j] = Xc[row1-1 + (k-1)*nw*nw + (i-1)*nw + j] + im*Xc[row1-1 + (k-1)*nw*nw + (i-1)*nw + j + nk*nw*nw]  + h_on[c][i, j]
                        S[ i,j] = Ys[row1-1 + (k-1)*nw*nw + (i-1)*nw + j] + im*Ys[row1-1 + (k-1)*nw*nw + (i-1)*nw + j + nk*nw*nw]
                    end
                    S[ i,i] += 1.0 #onsite
                end
                H0 = (H0+H0')/2.0
                S = (S+S')/2.0
                Smat[k,:,:] = S
                H0mat[k,:,:] = H0
            end

            if scf
                h1 = deepcopy(H1[c,1:nw,1:nw])
                dq = deepcopy(DQ[c,1:tbc.crys.nat])
            else
                h1 = zeros(Float64, nw, nw)
                dq = zeros(tbc.crys.nat)
            end
#            println("STARTING DQ")
#            println(dq)
            
            function get_eigen(h1_in)
                for k in 1:nk 
                    
                    H0 = H0mat[k,:,:]
                    S  = Smat[k,:,:]
                    if scf
                        H = H0 + h1_in .* S
                    else
                        H[:,:] = H0[:,:]
                    end

                    
                    vals, vects = eigen(H, S)
                    VECTS_FITTED[c,k,1:nw,1:nw] = vects
                    VALS_FITTED[c,k,1:nw] = real(vals)

                    VALS0_FITTED[c,k,1:nw] =  real.(diag(vects'*H0*vects))
                    
                end #kpoints loop
            end
                
            
            energy_old = 1000.0
            conv = false
            for c_scf = 1:niter_scf
                
                get_eigen(h1)

                if solve_self_consistently == true

                    mix = 0.7 * 0.92^c_scf  #start aggressive, reduce mixing slowly if we need most iterations

                    
                    energy_tmp,  occs = band_energy(VALS_FITTED[c,1:nk,1:nw], kweights, tbc.nelec, 0.01, returnocc=true) 
                    eden, h1_new, dq_new = get_electron_density(tbc, kpoints, kweights, VECTS_FITTED[c,:,1:nw,1:nw], occs, Smat)         #updated h1

                    s1 = sum(occs .* VALS0_FITTED[c,1:nk,1:nw], dims=2)
                    energy_band = sum(s1 .* kweights)

                    if maximum(abs.(dq - dq_new)) > 0.1
                        mix = 0.01
                    end

                    h1 = h1*(1-mix) + h1_new * mix
                    dq = dq*(1-mix) + dq_new * mix

                    
                    energy_charge, pot = ewald_energy(tbc, dq)
                    
                    energy_new = energy_charge + energy_band

                    if abs(energy_new  - energy_old) < 1e-5
                        println("scf converged $c    $dq ", energy_new+etypes )
                        conv = true
                        break
                    end
                    energy_old = energy_new
                    
                end
                
            end #scf loop

            if scf && conv
#                h1 = (h1 + H1[c,1:nw,1:nw]) / 2.0   #mixing
#                dq = (dq + DQ[c,1:tbc.crys.nat]) / 2.0

                H1[c,1:nw,1:nw] =  h1 
                DQ[c,1:tbc.crys.nat] = dq

            end

            get_eigen(h1)
            
            energy_tmp, occs_fitted = band_energy(VALS_FITTED[c,1:nk,1:nw], kweights, tbc.nelec, 0.01, returnocc=true)
            OCCS_FITTED[c,1:nk,1:nw] = occs_fitted
            
            
#            if scf
#                energy_charge, pot = ewald_energy(tbc, dq)
#            else
#                energy_charge = 0.0
            #            end
#            
#            etypes = types_energy(tbc)

            s1 = sum(occs_fitted .* VALS0_FITTED[c,1:nk,1:nw], dims=2)
            energy_band = sum(s1 .* kweights)

            if scf
                energy_charge, pot = ewald_energy(tbc, dq)
            else
                energy_charge = 0.0
            end


            
            ENERGIES_FITTED[c] = etypes + energy_charge + energy_band

        end

        return ENERGIES_FITTED, VECTS_FITTED, VALS_FITTED, OCCS_FITTED, VALS0_FITTED

    end



    
    function construct_newXY(ch, VECTS_FITTED, OCCS_FITTED)

        
        NEWX = zeros(ncalc*nk_max*NWAN_MAX + ncalc, NCOLS)
        NEWY = zeros(ncalc*nk_max*NWAN_MAX + ncalc)


        counter = 0

        for calc = 1:ncalc
            row1, rowN, nw = ind_BIG[calc, 1:3]
            vals = ones(nw) * 100.0

            H_cols = zeros(Complex{Float64}, nw, nw, NCOLS)

#            H_cols = H_COLS[calc]

            VECTS = zeros(Complex{Float64}, nw, nw)
#            S = zeros(Complex{Float64}, nw, nw)
            nk = size(KPOINTS[calc])[1]

            X_TOTEN = zeros(NCOLS)
            Y_TOTEN = ENERGIES[calc]

            if scf
                nat = list_of_tbcs[calc].crys.nat
                energy_charge, pot = ewald_energy(list_of_tbcs[calc], DQ[calc,1:nat])
            else
                energy_charge = 0.0
            end
            etypes = types_energy(list_of_tbcs[calc])
            
            Y_TOTEN -= energy_charge + etypes
            
            VECTS = zeros(Complex{Float64}, nw, nw)
            VECTS_p = zeros(Complex{Float64}, nw, nw)

            vals_test_other = zeros(nw, NCOLS)
            vals_test_on = zeros(nw)
            
            for k = 1:nk


                for i = 1:nw
                    for j = 1:nw
                        H_cols[i,j,:] = X_Hnew_BIG[row1-1 + (k-1)*nw*nw + (i-1)*nw + j,:] + im*X_Hnew_BIG[row1-1 + (k-1)*nw*nw + (i-1)*nw + j + nk*nw*nw,:]  
                    end
                end

#                H = (H+H')/2.0
                VECTS[:,:] = VECTS_FITTED[calc,k,1:nw,1:nw]
                VECTS_p[:,:] = VECTS'
                #vals_test = real(diag(VECTS' * H * VECTS))

                vals_test_on[:] = real(diag(VECTS' * h_on[calc] * VECTS)) 

                vals_test_other[:,:] .= 0.0

                for i = 1:nw
                    for j = 1:nw
                        for kk = 1:nw
                            for ii = 1:NCOLS
                                vals_test_other[i,ii] += real(VECTS_p[i,j] .* H_cols[ j,kk,ii]  .* VECTS[kk,i])
                            end
                        end
                    end
                end


                
                for i = 1:nw
                    counter += 1


                    NEWX[counter, :] = vals_test_other[i,:] .* WEIGHTS[calc, k, i]
                    X_TOTEN[:] +=   vals_test_other[i,:] .* (KWEIGHTS[calc][k] * OCCS_FITTED[calc,k,i])

                    NEWY[counter] =  (VALS0[calc,k,i] - vals_test_on[i]) .* WEIGHTS[calc, k, i]
                    Y_TOTEN += -1.0 * vals_test_on[i] * (KWEIGHTS[calc][k] * OCCS_FITTED[calc,k,i])

                end
                
                
            end
            counter += 1
            NEWX[counter, :] = X_TOTEN[:] * energy_weight
            NEWY[counter] = Y_TOTEN * energy_weight
            
        end
        
        return NEWX, NEWY

    end

    solve_scf_mode = false
    
    for iters = 1:50 #inner loop

        if scf
            if iters == 1 println("TURNING ON SCF SOLVE!!!!!!!!!!!!!!!!!!!!!!! ") end
            println()
            solve_scf_mode = true
        end

        println("DOING ITER $iters -------------------------------------------------------------")

#        println("construct_fitted")
        @time ENERGIES_working, VECTS_FITTED, VALS_FITTED, OCCS_FITTED, VALS0_FITTED = construct_fitted(ch, solve_scf_mode)

        
#, VALS0_FITTED #, solve_scf_mode
        println("energies_working")
        println(ENERGIES_working)

#        println("construct_newXY")

        @time NEWX, NEWY = construct_newXY(ch, VECTS_FITTED, OCCS_FITTED)

        
        if rs_weight > 1e-5
            TOTX = [X_H*rs_weight;NEWX]
            TOTY = [Y_H*rs_weight;NEWY]
        else
            TOTX = NEWX
            TOTY = NEWY
        end            
        error_old_rs  = sum((X_H * ch .- Y_H).^2)
        error_old_energy  = sum((NEWX * ch .- NEWY).^2)
        
        error_old = error_old_rs + error_old_energy
        
        ch_old = deepcopy(ch)
        println("lsq")
        @time ch_new = TOTX \ TOTY

        mix = 0.05
        ch = (ch_old * (1-mix) + ch_new * (mix) )
        
        error_new_rs  = sum((X_H * ch .- Y_H).^2)
        error_new_energy  = sum((NEWX * ch .- NEWY).^2)
        
        error_new = error_new_rs + error_new_energy

        println("errors rs     new $error_new_rs old $error_old_rs")
        println("errors energy new $error_new_energy old $error_old_energy")
        println("errors tot    new $error_new old $error_old")
        println()
    end

    database = make_database(ch, cs,  KEYS, HIND, SIND, scf=list_of_tbcs[1].scf)
    
    return database
end
#----------------------------------------------------------------------------------------------------------------------------------------------
=#



##############################
#=
function do_fitting_recursive_nonscf(list_of_tbcs; dft_list=missing,X_cv = missing, kpoints = [0 0 0; 0 0 0.5; 0 0.5 0.5; 0.5 0.5 0.5],  atoms_to_fit=missing, fit_threebody=true, fit_threebody_onsite=true, do_plot = false, energy_weight = missing, rs_weight=missing)

    if ismissing(energy_weight)
        energy_weight = 100.0
    end
    if ismissing(rs_weight)
        rs_weight = 0.0
    end

    if ismissing(dft_list)
        println("using entered kpoints instead of DFT list!!!!!!!!!!!")
        KPOINTS = []
        KWEIGHTS = []
        nk_max = size(kpoints)[1]
        nk = size(kpoints)[1]
        kweights = ones(Float64, nk)/nk * 2.0
        for n = 1:length(list_of_tbcs)
            push!(KPOINTS, kpoints)
            push!(KWEIGHTS, kweights)

        end
    else
        KPOINTS = []
        KWEIGHTS = []
        nk_max = 1
        for n = 1:length(list_of_tbcs)

            kpts = dft_list[n].bandstruct.kpts
            wghts = dft_list[n].bandstruct.kweights

#randomly downselect kpoints of number kpoints > 150            
            if size(kpts)[1] > 150
                println("limit kpoints to 150, from ",  size(kpts)[1])
                N = randperm(size(kpts)[1])
                kpts = kpts[N[1:150],:]
                wghts = wghts[N[1:150]]
                sw = sum(wghts)
                wghts = wghts * (2.0/sw)
            end

            push!(KPOINTS, kpts)
            push!(KWEIGHTS, wghts)
            
#            push!(KPOINTS, dft_list[n].bandstruct.kpts)
#            push!(KWEIGHTS, dft_list[n].bandstruct.kweights)
            nk_max = max(size(dft_list[n].bandstruct.kpts)[1], nk_max)

        end
    end        


    println("DO LINEAR FITTING")

    database, ch, cs, X_Hnew_BIG, Y_Hnew_BIG, X_H, X_Snew_BIG, Y_H, h_on, ind_BIG, KEYS, HIND, SIND = do_fitting_linear(list_of_tbcs; kpoints = KPOINTS,  atoms_to_fit=atoms_to_fit, fit_threebody=fit_threebody, fit_threebody_onsite=fit_threebody_onsite, do_plot = false)

    println("NOW, DO RECURSIVE FITTING")
    
    NWAN_MAX = maximum(ind_BIG[:,3])


#    nk = size(kpoints)[1]
    ncalc = length(list_of_tbcs)

    VALS     = zeros(ncalc, nk_max, NWAN_MAX)
    OCCS     = zeros(ncalc, nk_max, NWAN_MAX)
    WEIGHTS     = zeros(ncalc, nk_max, NWAN_MAX)
    ENERGIES = zeros(ncalc)


    
    Ys = X_Snew_BIG * cs

    NCOLS = size(X_Hnew_BIG)[2]


    #PREPARE REFERENCE ENERGIES / EIGENVALUES
    println("prepare reference eigs")
    c=0
    @time for (tbc, kpoints, kweights) in zip(list_of_tbcs, KPOINTS, KWEIGHTS)
        c+=1
        nw = ind_BIG[c, 3]
        nk = size(kpoints)[1]

        row1, rowN, nw = ind_BIG[c, 1:3]

        for k in 1:nk
            vects, vals, hk, sk = Hk(tbc.tb, kpoints[k,:])  #reference
            VALS[c,k,1:nw] = vals                           #reference

        end

        ENERGIES[c], occs = band_energy(VALS[c,1:nk,1:nw], kweights, tbc.nelec, 0.01, returnocc=true)
        OCCS[c,1:nk,1:nw] = occs

        etmp, occs = band_energy(VALS[c,1:nk,1:nw], kweights, tbc.nelec+.05, 0.05, returnocc=true)
        WEIGHTS[c,1:nk,1:nw] = occs

    end


    VALS_working = zeros(size(VALS))
    ENERGIES_working = zeros(size(ENERGIES))
    OCCS_working = zeros(size(OCCS))

    WEIGHTS = WEIGHTS .+ 0.20

    verbose=0

    function construct_fitted(ch)

        Xc = X_Hnew_BIG * ch


        VECTS_FITTED     = zeros(Complex{Float64}, ncalc, nk_max, NWAN_MAX, NWAN_MAX)
        VALS_FITTED     = zeros(ncalc, nk_max, NWAN_MAX)
        OCCS_FITTED     = zeros(ncalc, nk_max, NWAN_MAX)
        ENERGIES_FITTED = zeros(ncalc)
        c=0
        for (tbc, kpoints, kweights) in zip(list_of_tbcs, KPOINTS, KWEIGHTS)
            c+=1
            nw = ind_BIG[c, 3]
            nk = size(kpoints)[1]

            row1, rowN, nw = ind_BIG[c, 1:3]

            H = zeros(Complex{Float64}, nw, nw)
            S = zeros(Complex{Float64}, nw, nw)

            for k in 1:nk

                #fitted eigenvectors / vals
                for i = 1:nw
                    for j = 1:nw
                        H[i,j] = Xc[row1-1 + (k-1)*nw*nw + (i-1)*nw + j] + im*Xc[row1-1 + (k-1)*nw*nw + (i-1)*nw + j + nk*nw*nw]  + h_on[c][i, j]
                        S[i,j] = Ys[row1-1 + (k-1)*nw*nw + (i-1)*nw + j] + im*Ys[row1-1 + (k-1)*nw*nw + (i-1)*nw + j + nk*nw*nw]
                    end
                    S[i,i] += 1.0 #onsite
                end
                H = (H+H')/2.0
                S = (S+S')/2.0

                vals, vects = eigen(H, S)
                VECTS_FITTED[c,k,1:nw,1:nw] = vects
                VALS_FITTED[c,k,1:nw] = real(vals)
                

            end

            ENERGIES_FITTED[c], occs_fitted = band_energy(VALS_FITTED[c,1:nk,1:nw], kweights, tbc.nelec, 0.01, returnocc=true)
            OCCS_FITTED[c,1:nk,1:nw] = occs_fitted

        end

        return ENERGIES_FITTED, VECTS_FITTED, VALS_FITTED, OCCS_FITTED

    end

#=        
    function get_hcol()
        
        H_COLS = []
        
        for calc = 1:ncalc
            row1, rowN, nw = ind_BIG[calc, 1:3]
            nk = size(KPOINTS[calc])[1]
            H_cols = zeros(Complex{Float64}, nk, nw, nw, NCOLS)
            for k = 1:nk
                for i = 1:nw
                    for j = 1:nw
                        H_cols[k,i,j,:] = X_Hnew_BIG[row1-1 + (k-1)*nw*nw + (i-1)*nw + j,:] + im*X_Hnew_BIG[row1-1 + (k-1)*nw*nw + (i-1)*nw + j + nk*nw*nw,:]  
                    end
                end
            end
            push!(H_COLS, H_cols)
        end
        return H_COLS
    end    
    
    println("get hcol")
    @time H_COLS = get_hcol()
=#    
    
    function construct_newXY(ch, VECTS_FITTED, OCCS_FITTED)

        NEWX = zeros(ncalc*nk_max*NWAN_MAX + ncalc, NCOLS)
        NEWY = zeros(ncalc*nk_max*NWAN_MAX + ncalc)

        counter = 0
        for calc = 1:ncalc
            row1, rowN, nw = ind_BIG[calc, 1:3]
            vals = ones(nw) * 100.0
#            H = zeros(Complex{Float64}, nw, nw, NCOLS)
#            H = zeros(Complex{Float64}, nw, nw)
            H_cols = zeros(Complex{Float64}, nw, nw, NCOLS)

#            H_cols = H_COLS[calc]

            VECTS = zeros(Complex{Float64}, nw, nw)
#            S = zeros(Complex{Float64}, nw, nw)
            nk = size(KPOINTS[calc])[1]

            X_TOTEN = zeros(NCOLS)
            Y_TOTEN = ENERGIES[calc]

            VECTS = zeros(Complex{Float64}, nw, nw)
            VECTS_p = zeros(Complex{Float64}, nw, nw)

            vals_test_other = zeros(nw, NCOLS)
            vals_test_on = zeros(nw)
            

            for k = 1:nk
#                for ii = 1:NCOLS
#                    for j = 1:nw
#                        for i = 1:nw
 #                           H_cols[i,j,ii] = X_Hnew_BIG[row1-1 + (k-1)*nw*nw + (i-1)*nw + j,ii] + im*X_Hnew_BIG[row1-1 + (k-1)*nw*nw + (i-1)*nw + j + nk*nw*nw,ii]  
 #                       end
 #                   end
 #               end

                for i = 1:nw
                    for j = 1:nw
#                        H[i,j] = Xc[row1-1 + (k-1)*nw*nw + (i-1)*nw + j] + im*Xc[row1-1 + (k-1)*nw*nw + (i-1)*nw + j + nk*nw*nw]  + h_on[c][i, j]

#                        for ii = 1:NCOLS
#                            H_cols[i,j,ii] = X_Hnew_BIG[row1-1 + (k-1)*nw*nw + (i-1)*nw + j,ii] + im*X_Hnew_BIG[row1-1 + (k-1)*nw*nw + (i-1)*nw + j + nk*nw*nw,ii]  
#                        end

                        H_cols[i,j,:] = X_Hnew_BIG[row1-1 + (k-1)*nw*nw + (i-1)*nw + j,:] + im*X_Hnew_BIG[row1-1 + (k-1)*nw*nw + (i-1)*nw + j + nk*nw*nw,:]  


#                        S[i,j] = Ys[row1-1 + (k-1)*nw*nw + (i-1)*nw + j] + im*Ys[row1-1 + (k-1)*nw*nw + (i-1)*nw + j + nk*nw*nw]
                    end
#                    S[i,i] += 1.0 #onsite
                end

#                H = (H+H')/2.0
                VECTS[:,:] = VECTS_FITTED[calc,k,1:nw,1:nw]
                VECTS_p[:,:] = VECTS'
                #vals_test = real(diag(VECTS' * H * VECTS))
                vals_test_on[:] = real(diag(VECTS' * h_on[calc] * VECTS))

                vals_test_other[:,:] .= 0.0

                
                for i = 1:nw
                    for j = 1:nw
                        for kk = 1:nw
                            for ii = 1:NCOLS
                                vals_test_other[i,ii] += real(VECTS_p[i,j] .* H_cols[ j,kk,ii] .* VECTS[kk,i])
                            end
                        end
                    end
                end

                for i = 1:nw
                    counter += 1

#                    for ii = 1:NCOLS
#                        NEWX[counter, ii] = vals_test_other[i,ii] .* WEIGHTS[calc, k, i]
#                        X_TOTEN[ii] +=   vals_test_other[i,ii] .* (KWEIGHTS[calc][k] * OCCS_FITTED[calc,k,i])
#                    end

                    NEWX[counter, :] = vals_test_other[i,:] .* WEIGHTS[calc, k, i]
                    X_TOTEN[:] +=   vals_test_other[i,:] .* (KWEIGHTS[calc][k] * OCCS_FITTED[calc,k,i])

                    NEWY[counter] =  (VALS0[calc,k,i] - vals_test_on[i]) .* WEIGHTS[calc, k, i]
                    Y_TOTEN += -1.0 * vals_test_on[i] * (KWEIGHTS[calc][k] * OCCS_FITTED[calc,k,i])

                       ###println("$calc $k $i : ",  vals_test[i], "\t" , VALS_FITTED[calc,k,i],"\t", vals_test_on[i] + vals_test_other[i,:]'*ch)
                end
                
                
            end
            counter += 1
            NEWX[counter, :] = X_TOTEN[:] * energy_weight
            NEWY[counter] = Y_TOTEN * energy_weight
            
        end
        
        return NEWX, NEWY

    end
    
    for iters = 1:15
        println("doing iteration $iters")

        println("construct_fitted")
        @time ENERGIES_working, VECTS_FITTED, VALS_FITTED, OCCS_FITTED, VALS0_FITTED = construct_fitted(ch)
        println("energies_working")
        println(ENERGIES_working)

        println("construct_newXY")

        @time NEWX, NEWY = construct_newXY(ch, VECTS_FITTED, OCCS_FITTED)

        if rs_weight > 1e-5
            TOTX = [X_H*rs_weight;NEWX]
            TOTY = [Y_H*rs_weight;NEWY]
        else
            TOTX = NEWX
            TOTY = NEWY
        end            
        error_old_rs  = sum((X_H * ch .- Y_H).^2)
        error_old_energy  = sum((NEWX * ch .- NEWY).^2)
        
        error_old = error_old_rs + error_old_energy
        
        ch_old = deepcopy(ch)
        println("lsq")
        @time ch_new = TOTX \ TOTY

        ch = (ch_old * 0.5 + ch_new * (1.0 - 0.5) )
        
        error_new_rs  = sum((X_H * ch .- Y_H).^2)
        error_new_energy  = sum((NEWX * ch .- NEWY).^2)
        
        error_new = error_new_rs + error_new_energy

        println("errors rs     new $error_new_rs old $error_old_rs")
        println("errors energy new $error_new_energy old $error_old_energy")
        println("errors tot    new $error_new old $error_old")
        println()
    end

    database = make_database(ch, cs,  KEYS, HIND, SIND, scf=list_of_tbcs[1].scf)
    
    return database
end


##############################

function do_fitting_recursive_cv(list_of_tbcs, X_cv; dft_list=missing, kpoints = [0 0 0; 0 0 0.5; 0 0.5 0.5; 0.5 0.5 0.5],  atoms_to_fit=missing, fit_threebody=true, fit_threebody_onsite=true, do_plot = false, energy_weight = missing, rs_weight=missing)

    if ismissing(energy_weight)
        energy_weight = 100.0
    end
    if ismissing(rs_weight)
        rs_weight = 0.0
    end

    if ismissing(dft_list)
        println("using entered kpoints instead of DFT list!!!!!!!!!!!")
        KPOINTS = []
        KWEIGHTS = []
        nk_max = size(kpoints)[1]
        nk = size(kpoints)[1]
        kweights = ones(Float64, nk)/nk * 2.0
        for n = 1:length(list_of_tbcs)
            push!(KPOINTS, kpoints)
            push!(KWEIGHTS, kweights)

        end
    else
        KPOINTS = []
        KWEIGHTS = []
        nk_max = 1
        for n = 1:length(list_of_tbcs)

            kpts = dft_list[n].bandstruct.kpts
            wghts = dft_list[n].bandstruct.kweights

#randomly downselect kpoints of number kpoints > 150            
            if size(kpts)[1] > 150
                println("limit kpoints to 150, from ",  size(kpts)[1])
                N = randperm(size(kpts)[1])
                kpts = kpts[N[1:150],:]
                wghts = wghts[N[1:150]]
                sw = sum(wghts)
                wghts = wghts * (2.0/sw)
            end

            push!(KPOINTS, kpts)
            push!(KWEIGHTS, wghts)
            
#            push!(KPOINTS, dft_list[n].bandstruct.kpts)
#            push!(KWEIGHTS, dft_list[n].bandstruct.kweights)
            nk_max = max(size(dft_list[n].bandstruct.kpts)[1], nk_max)

        end
    end        


    println("DO LINEAR FITTING")

    database, ch, cs, X_Hnew_BIG, Y_Hnew_BIG, X_H, X_Snew_BIG, Y_H, h_on, ind_BIG, KEYS, HIND, SIND = do_fitting_linear(list_of_tbcs; kpoints = KPOINTS,  atoms_to_fit=atoms_to_fit, fit_threebody=fit_threebody, fit_threebody_onsite=fit_threebody_onsite, do_plot = false)
    ch_lin = deepcopy(ch)

    println("NOW, DO RECURSIVE FITTING")
    
    NWAN_MAX = maximum(ind_BIG[:,3])


#    nk = size(kpoints)[1]
    ncalc = length(list_of_tbcs)

    VALS     = zeros(ncalc, nk_max, NWAN_MAX)
    VALS0     = zeros(ncalc, nk_max, NWAN_MAX)
    OCCS     = zeros(ncalc, nk_max, NWAN_MAX)
    WEIGHTS     = zeros(ncalc, nk_max, NWAN_MAX)
    ENERGIES = zeros(ncalc)


    
    Ys = X_Snew_BIG * cs

    NCOLS = size(X_Hnew_BIG)[2]


    #PREPARE REFERENCE ENERGIES / EIGENVALUES
    println("prepare reference eigs")
    c=0
    @time for (tbc, kpoints, kweights) in zip(list_of_tbcs, KPOINTS, KWEIGHTS)
        c+=1
        nw = ind_BIG[c, 3]
        nk = size(kpoints)[1]

        row1, rowN, nw = ind_BIG[c, 1:3]

        for k in 1:nk
            vects, vals, hk, sk, vals0 = Hk(tbc.tb, kpoints[k,:])  #reference
            VALS[c,k,1:nw] = vals                           #reference
            VALS0[c,k,1:nw] = vals0                          #reference

        end

        energy_tmp,  occs = band_energy(VALS[c,1:nk,1:nw], kweights, tbc.nelec, 0.01, returnocc=true) 
#        energy_band, occs = band_energy(VALS0[c,1:nk,1:nw], kweights, tbc.nelec, 0.01, returnocc=true)

        energy_band = sum(sum(occs .* VALS0[c,:,:], dim=2) .* kweights)
        if scf
            energy_charge = ewald_energy(tbc)
        else
            energy_charge = 0.0
        end
        etypes = types_energy(tbc)

        ENERGIES[c] = etypes + energy_charge + energy_band
        
        OCCS[c,1:nk,1:nw] = occs

        etmp, occs = band_energy(VALS[c,1:nk,1:nw], kweights, tbc.nelec+.05, 0.05, returnocc=true)
        WEIGHTS[c,1:nk,1:nw] = occs

    end

    return ENERGIES
    
    VALS_working = zeros(size(VALS))
    ENERGIES_working = zeros(size(ENERGIES))
    OCCS_working = zeros(size(OCCS))

    WEIGHTS = WEIGHTS .+ 0.20

    verbose=0

    function construct_fitted(ch, ind)

        Xc = X_Hnew_BIG * ch


        VECTS_FITTED     = zeros(Complex{Float64}, ncalc, nk_max, NWAN_MAX, NWAN_MAX)
        VALS_FITTED     = zeros(ncalc, nk_max, NWAN_MAX)
        OCCS_FITTED     = zeros(ncalc, nk_max, NWAN_MAX)
        ENERGIES_FITTED = zeros(ncalc)

        for (c, tbc, kpoints, kweights) in zip(ind, list_of_tbcs[ind], KPOINTS[ind], KWEIGHTS[ind])

            nw = ind_BIG[c, 3]
            nk = size(kpoints)[1]

            row1, rowN, nw = ind_BIG[c, 1:3]

            H = zeros(Complex{Float64}, nw, nw)
            S = zeros(Complex{Float64}, nw, nw)

            for k in 1:nk

                #fitted eigenvectors / vals
                for i = 1:nw
                    for j = 1:nw
                        H[i,j] = Xc[row1-1 + (k-1)*nw*nw + (i-1)*nw + j] + im*Xc[row1-1 + (k-1)*nw*nw + (i-1)*nw + j + nk*nw*nw]  + h_on[c][i, j]
                        S[i,j] = Ys[row1-1 + (k-1)*nw*nw + (i-1)*nw + j] + im*Ys[row1-1 + (k-1)*nw*nw + (i-1)*nw + j + nk*nw*nw]
                    end
                    S[i,i] += 1.0 #onsite
                end
                H = (H+H')/2.0
                S = (S+S')/2.0

                vals, vects = eigen(H, S)
                VECTS_FITTED[c,k,1:nw,1:nw] = vects
                VALS_FITTED[c,k,1:nw] = real(vals)
                

            end

            ENERGIES_FITTED[c], occs_fitted = band_energy(VALS_FITTED[c,1:nk,1:nw], kweights, tbc.nelec, 0.01, returnocc=true)
            OCCS_FITTED[c,1:nk,1:nw] = occs_fitted

        end

        return ENERGIES_FITTED, VECTS_FITTED, VALS_FITTED, OCCS_FITTED

    end

#=        
    function get_hcol()
        
        H_COLS = []
        
        for calc = 1:ncalc
            row1, rowN, nw = ind_BIG[calc, 1:3]
            nk = size(KPOINTS[calc])[1]
            H_cols = zeros(Complex{Float64}, nk, nw, nw, NCOLS)
            for k = 1:nk
                for i = 1:nw
                    for j = 1:nw
                        H_cols[k,i,j,:] = X_Hnew_BIG[row1-1 + (k-1)*nw*nw + (i-1)*nw + j,:] + im*X_Hnew_BIG[row1-1 + (k-1)*nw*nw + (i-1)*nw + j + nk*nw*nw,:]  
                    end
                end
            end
            push!(H_COLS, H_cols)
        end
        return H_COLS
    end    
    
    println("get hcol")
    @time H_COLS = get_hcol()
=#    
    
    function construct_newXY(ch, VECTS_FITTED, OCCS_FITTED, ind)

        NEWX = zeros(ncalc*nk_max*NWAN_MAX + ncalc, NCOLS)
        NEWY = zeros(ncalc*nk_max*NWAN_MAX + ncalc)

        counter = 0
        for calc = ind
            row1, rowN, nw = ind_BIG[calc, 1:3]
            vals = ones(nw) * 100.0
#            H = zeros(Complex{Float64}, nw, nw, NCOLS)
#            H = zeros(Complex{Float64}, nw, nw)
            H_cols = zeros(Complex{Float64}, nw, nw, NCOLS)

#            H_cols = H_COLS[calc]

            VECTS = zeros(Complex{Float64}, nw, nw)
#            S = zeros(Complex{Float64}, nw, nw)
            nk = size(KPOINTS[calc])[1]

            X_TOTEN = zeros(NCOLS)
            Y_TOTEN = ENERGIES[calc]

            VECTS = zeros(Complex{Float64}, nw, nw)
            VECTS_p = zeros(Complex{Float64}, nw, nw)

            vals_test_other = zeros(nw, NCOLS)
            vals_test_on = zeros(nw)
            

            for k = 1:nk
#                for ii = 1:NCOLS
#                    for j = 1:nw
#                        for i = 1:nw
 #                           H_cols[i,j,ii] = X_Hnew_BIG[row1-1 + (k-1)*nw*nw + (i-1)*nw + j,ii] + im*X_Hnew_BIG[row1-1 + (k-1)*nw*nw + (i-1)*nw + j + nk*nw*nw,ii]  
 #                       end
 #                   end
 #               end

                for i = 1:nw
                    for j = 1:nw
#                        H[i,j] = Xc[row1-1 + (k-1)*nw*nw + (i-1)*nw + j] + im*Xc[row1-1 + (k-1)*nw*nw + (i-1)*nw + j + nk*nw*nw]  + h_on[c][i, j]

#                        for ii = 1:NCOLS
#                            H_cols[i,j,ii] = X_Hnew_BIG[row1-1 + (k-1)*nw*nw + (i-1)*nw + j,ii] + im*X_Hnew_BIG[row1-1 + (k-1)*nw*nw + (i-1)*nw + j + nk*nw*nw,ii]  
#                        end

                        H_cols[i,j,:] = X_Hnew_BIG[row1-1 + (k-1)*nw*nw + (i-1)*nw + j,:] + im*X_Hnew_BIG[row1-1 + (k-1)*nw*nw + (i-1)*nw + j + nk*nw*nw,:]  


#                        S[i,j] = Ys[row1-1 + (k-1)*nw*nw + (i-1)*nw + j] + im*Ys[row1-1 + (k-1)*nw*nw + (i-1)*nw + j + nk*nw*nw]
                    end
#                    S[i,i] += 1.0 #onsite
                end

#                H = (H+H')/2.0
                VECTS[:,:] = VECTS_FITTED[calc,k,1:nw,1:nw]
                VECTS_p[:,:] = VECTS'
                #vals_test = real(diag(VECTS' * H * VECTS))
                vals_test_on[:] = real(diag(VECTS' * h_on[calc] * VECTS))

                vals_test_other[:,:] .= 0.0

                
                for i = 1:nw
                    for j = 1:nw
                        for kk = 1:nw
                            for ii = 1:NCOLS
                                vals_test_other[i,ii] += real(VECTS_p[i,j] .* H_cols[ j,kk,ii] .* VECTS[kk,i])
                            end
                        end
                    end
                end

                for i = 1:nw
                    counter += 1

#                    for ii = 1:NCOLS
#                        NEWX[counter, ii] = vals_test_other[i,ii] .* WEIGHTS[calc, k, i]
#                        X_TOTEN[ii] +=   vals_test_other[i,ii] .* (KWEIGHTS[calc][k] * OCCS_FITTED[calc,k,i])
#                    end

                    NEWX[counter, :] = vals_test_other[i,:] .* WEIGHTS[calc, k, i]
                    X_TOTEN[:] +=   vals_test_other[i,:] .* (KWEIGHTS[calc][k] * OCCS_FITTED[calc,k,i])

                    NEWY[counter] =  (VALS[calc,k,i] - vals_test_on[i]) .* WEIGHTS[calc, k, i]
                    Y_TOTEN += -1.0 * vals_test_on[i] * (KWEIGHTS[calc][k] * OCCS_FITTED[calc,k,i])

                       ###println("$calc $k $i : ",  vals_test[i], "\t" , VALS_FITTED[calc,k,i],"\t", vals_test_on[i] + vals_test_other[i,:]'*ch)
                end
                
                
            end
            counter += 1
            NEWX[counter, :] = X_TOTEN[:] * energy_weight
            NEWY[counter] = Y_TOTEN * energy_weight
            
        end
        
        return NEWX, NEWY

    end
    

    energy_error = zeros(Float64, 0,5)
    database_arr = []
    c_cv = 0
    for x_cv in X_cv
        c_cv += 1

        ch = deepcopy(ch_lin)
        X2 = []
        ind = Int64[]
        for xp = X_cv
            if x_cv != xp
                for xx in xp
                    push!(ind,xx)
                end
            end
        end
    
        for iters = 1:10
            println("doing iteration $iters")

            #println("construct_fitted")
            ENERGIES_working, VECTS_FITTED, VALS_FITTED, OCCS_FITTED = construct_fitted(ch, ind)
            #println("energies_working")
            #println(ENERGIES_working)
            
            #println("construct_newXY")

            NEWX, NEWY = construct_newXY(ch, VECTS_FITTED, OCCS_FITTED, ind)

            if rs_weight > 1e-5
                TOTX = [X_H*rs_weight;NEWX]
                TOTY = [Y_H*rs_weight;NEWY]
            else
                TOTX = NEWX
                TOTY = NEWY
            end            
            error_old_rs  = sum((X_H * ch .- Y_H).^2)
            error_old_energy  = sum((NEWX * ch .- NEWY).^2)
        
            error_old = error_old_rs + error_old_energy
        
            ch_old = deepcopy(ch)
#            println("lsq")
            ch_new = TOTX \ TOTY

            ch = (ch_old * 0.6 + ch_new * (1.0 - 0.6) )
        
            error_new_rs  = sum((X_H * ch .- Y_H).^2)
            error_new_energy  = sum((NEWX * ch .- NEWY).^2)
        
            error_new = error_new_rs + error_new_energy

#            println("errors rs     new $error_new_rs old $error_old_rs")
#            println("errors energy new $error_new_energy old $error_old_energy")
#            println("errors tot    new $error_new old $error_old")
 #           println()
        end
        
        database = make_database(ch, cs,  KEYS, HIND, SIND, scf=list_of_tbcs[1].scf)
        push!(database_arr,database)
        for x_ind in x_cv
            tbc = list_of_tbcs[x_ind]
            tbc_calc = calc_tb_fast(tbc.crys, database)

            energy_orig = calc_energy_fft(tbc, grid=[12 12 12], smearing=0.01)
            energy_calc = calc_energy_fft(tbc_calc, grid=[12 12 12], smearing=0.01)

            energy_error = [energy_error; Float64(c_cv) Float64(x_ind) energy_orig energy_calc energy_orig-energy_calc]
        end
        println("energy_error")
        println(energy_error)
    end
    
    return database_arr, energy_error
end
=#


end
