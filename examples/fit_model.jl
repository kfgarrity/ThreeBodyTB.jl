using ThreeBodyTB


function example_run_dft()

    # In this example, we fit a simple model. A robust TB model would require much more data.
    

    #First, it is necessary to run the DFT calculations, for example, we could define
    #a crystal as 
    
    A = [5.33955  5.33955  0.0;5.33955  0.0      5.33955;0.0      5.33955  5.33955] * 0.529177
    pos = [0 0 0; 0.25 0.25 0.25]
    names = ["Mg", "S"]

    c = makecrys(A, pos, names)

    # To run the dft calculation, first we have to tell the code where QE (quantum espresso) is.
    
    ThreeBodyTB.set_bin_dirs(qe="/home/kfg/codes/qe-6.6/bin/") # you must give the code your own QE !!!!
    
    # You may also want to include an MPI command like
    
    ThreeBodyTB.set_bin_dirs(mpi="mpirun -np ")
    
    # Lets create an output directory
    
    mkpath("dft_out")

    dft = missing
    
    try
        
        # Then we could run a job like
        
        dft = ThreeBodyTB.DFT.runSCF(c, directory="dft_out", tmpdir="dft_out")
        
        # if you add a variable nprocs = 8, it will run in parallel on 8 processors. This will take a minute or two on modern computers.
        
        # This returns a dft output object, which you could also load later with :
        
        dft2 = ThreeBodyTB.QE.loadXML("dft_out/qe.save/")
        
    catch
        
        # if you don't have QE installed, this won't work obviously. However, I already ran this calculation for you, we can load the results
        
        dft = ThreeBodyTB.QE.loadXML(ThreeBodyTB.TESTDIR * "/data_forces/znse.in_vnscf_vol_2/qe.save")
        
    end

    # To calculate the tight-binding k-space object, we can use
    tbck=missing

    try
        
        workd = "dft_out/"
        tbc, tbck, proj_warn = ThreeBodyTB.AtomicProj.projwfx_workf(dft, directory=workd, writefile="projham_K.xml", only_kspace = true)
        #this will take a minute or two as well, and can be run in parallel
        
    catch

        # using precalculated data
        
        workd = ThreeBodyTB.TESTDIR * "/data_forces/znse.in_vnscf_vol_2/"
        tbc, tbck, proj_warn = ThreeBodyTB.AtomicProj.projwfx_workf(dft, directory=workd, writefile="projham_K.xml", only_kspace = true)

    end    

    #remove self-consistent terms from tbck, so we get the corrent answer back when we solve self-consistently
    tbck_scf = ThreeBodyTB.SCF.remove_scf_from_tbc(tbck)

    return dft
end


function do_fitting(dft_ref)

    ##########################
    
    # Now that we have seen how to prepare one dft calculation, lets load all the data we need
    # which is precalculated.
    
    
    TESTDIR = ThreeBodyTB.TESTDIR
    
    ft = open("$TESTDIR/data_forces/fil_MgS_znse", "r"); #the list of files we need.
    dirst = readlines(ft);
    close(ft);
    
    tbc_list = []
    dft_list = []

    #here we load the data
    for t in dirst
        tfull = "$TESTDIR/"*t
        try #try to load from xml files


            dft = ThreeBodyTB.QE.loadXML(tfull*"/qe.save")

            tbck = ThreeBodyTB.TB.read_tb_crys_kspace("projham_K.xml.gz", directory=tfull)
            
            tbck_scf = ThreeBodyTB.SCF.remove_scf_from_tbc(tbck)
            
            push!(dft_list, dft)
            push!(tbc_list, tbck_scf)
            
        catch
            println("missing data $tfull")
        end
        
    end

    # We only want to fit the Mg-S interactions, not the Mg-Mg or S-S. So we will give those to the fitting algorithm as the starting data, which is fixed.

    ThreeBodyTB.ManageDatabase.clear_database() #make sure nothing is pre-cached
    ThreeBodyTB.ManageDatabase.prepare_database(["Mg"])
    ThreeBodyTB.ManageDatabase.prepare_database(["S"])
    database_start = deepcopy(ThreeBodyTB.ManageDatabase.database_cached)
    ThreeBodyTB.ManageDatabase.clear_database() #make sure nothing is pre-cached
    
    #now we do the new fitting.
    
    database_new = ThreeBodyTB.FitTB.do_fitting_recursive(tbc_list, dft_list = dft_list, starting_database = database_start)
    
    #now we run an example calculation with the new database
    
    energy_tot, tbc, conv_flag = scf_energy(dft_ref.crys, database=database_new)
    
    println("We can compare our model energy $energy_tot with the DFT atomization energy ", dft_ref.atomize_energy)

    #println("note that this model is badly overfit and needs more data")

end


dft = example_run_dft()
do_fitting(dft)

 

