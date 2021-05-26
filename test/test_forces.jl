using Test
using ThreeBodyTB
using Suppressor

#include("../includes_laguerre.jl")
#include("../Ewald.jl")

TESTDIR=ThreeBodyTB.TESTDIR

function loaddata(dirs; scf=true)
    tbc_list  = []
    dft_list = []

    for t in dirs
        #                println(t*"/qe.save")
        tfull = "$TESTDIR/"*t
        dft = ThreeBodyTB.QE.loadXML(tfull*"/qe.save")
        tbc = []
        tbc_scf = []
        try
            if scf
                tbc = ThreeBodyTB.TB.read_tb_crys("projham.xml.gz", directory=tfull)
                tbc_scf = ThreeBodyTB.SCF.remove_scf_from_tbc(tbc)
            else
                tbc_scf = ThreeBodyTB.TB.read_tb_crys("projham.xml.gz", directory=tfull)
            end
        catch
            tbc = ThreeBodyTB.AtomicProj.projwfx_workf(dft, directory=tfull, writefile="projham.xml", skip_og=true, skip_proj=true, freeze=true, localized_factor = 0.15)
            if scf
                tbc_scf = ThreeBodyTB.SCF.remove_scf_from_tbc(tbc)
                ThreeBodyTB.TB.write_tb_crys(t*"/projham_scf.xml.gz", tbc_scf)
            else
                tbc_scf = tbc
            end
            
        end
        
        push!(dft_list, dft)
        push!(tbc_list, tbc_scf)
    end
    return     tbc_list, dft_list
end


function test_force()

    @testset "testing force dimer" begin

        if true
#        @suppress begin
            ft = open("$TESTDIR/data_forces/fil_MgS_dimer", "r"); 
            dirst = readlines(ft); 
            close(ft); 

            #        println(dirst)


#            for scf = [false true]
            f_cart = zeros(2,3)
            f_cartFD = 0.0
            
            for scf = [false, true]
                @suppress begin
                tbc_list, dft_list = loaddata(dirst, scf=scf);
                     database_rec = ThreeBodyTB.FitTB.do_fitting_recursive(tbc_list,dft_list = dft_list,  fit_threebody=false, fit_threebody_onsite=false);


                x = 4;
                smearing = 0.01;  

                    #en, tbc_x, flag = scf_energy(tbc_list[x].crys, database = database_rec)
                    #en, f_cart,stress = ThreeBodyTB.Force_Stress.get_energy_force_stress(tbc_x, database_rec,   smearing = smearing);
                    
                    en, f_cart,stress = ThreeBodyTB.Force_Stress.get_energy_force_stress(tbc_list[x].crys, database_rec,   smearing = smearing);

                enFD, f_cartFD = ThreeBodyTB.Force_Stress.finite_diff(tbc_list[x].crys, database_rec,1, 3,   smearing = smearing);
                end

#                println(scf, " xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx  ", f_cartFD, "  ", f_cart[1,3])
                
                @test abs(f_cartFD - f_cart[1,3]) < 1e-3
#                @test abs(f_cartFD - f_cart_fft[1,3]) < 1e-3
                #            println("SCF $scf TEST1 finite diff: ", f_cartFD , " autodiff:   ", f_cart[1,3], " xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx")
                #            println("TEST1 dft ref ", dft_list[x].forces[1,3])

            end
            #        x = 3;
            #        smearing = 0.01;  
            #        en, f_cart,stress = Force_Stress.get_energy_force_stress(tbc_list[x].crys, database_rec,   smearing = smearing);
            #        enFD, f_cartFD = Force_Stress.finite_diff(tbc_list[x].crys, database_rec,1, 3,   smearing = smearing);

            #        @test abs(f_cartFD - f_cart[1,3]) < 1e-3
            #        println("TEST3 finite diff: ", f_cartFD , " autodiff:   ", f_cart[1,3], " xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx")
            #        println("TEST3 dft ref ", dft_list[x].forces[1,3])

        end
    end
end

function test_stress()

    @testset "testing force znse" begin
        @suppress begin
        
            ft = open("$TESTDIR/data_forces/fil_MgS_znse", "r"); 
            dirst = readlines(ft); 
            close(ft); 

            #        println(dirst)


            tbc_list, dft_list = loaddata(dirst, scf=false);

            database = ThreeBodyTB.FitTB.do_fitting(tbc_list, fit_threebody=false, fit_threebody_onsite=false, do_plot=false);
            #        database = FitTB.do_fitting_recursive(tbc_list,dft_list = dft_list,  fit_threebody=true, fit_threebody_onsite=false);

            x = 1;
            smearing = 0.01;  
            en, f_cart, stress = ThreeBodyTB.Force_Stress.get_energy_force_stress(tbc_list[x].crys, database,   smearing = smearing);

            enFD, f_cartFD = ThreeBodyTB.Force_Stress.finite_diff(tbc_list[x].crys, database,1, 3,   smearing = smearing);

            #        println("TEST force finite diff: ", f_cartFD , " autodiff:   ", f_cart[1,3], " xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx")
            #        println("TEST dft ref ", dft_list[x].forces[1,3])
            @test abs(f_cartFD - f_cart[1,3]) < 1e-4


            x=1
            enFD, stressFD = ThreeBodyTB.Force_Stress.finite_diff(tbc_list[x].crys, database,1, 1, stress_mode=true,  smearing = smearing);

            #        println("TEST stress11 finite diff: ", stressFD , " autodiff:   ", stress[1,1], " xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx")
            #        println("TEST dft ref ", dft_list[x].stress[1,1])
            @test abs(stressFD - stress[1,1]) < 1e-5


            x=1
            enFD, stressFD = ThreeBodyTB.Force_Stress.finite_diff(tbc_list[x].crys, database,1, 2, stress_mode=true,  smearing = smearing);

            #        println("TEST stress12 finite diff: ", stressFD , " autodiff:   ", stress[1,2], " xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx")
            #        println("TEST dft ref ", dft_list[x].stress[1,2])
            @test abs(stressFD - stress[1,2]) < 1e-5

            #        println("done")
        end
    end
end


test_force()

#println("sleep ")
#sleep(3)

test_stress()
