# push!(LOAD_PATH,pwd())
using Revise
using CSV
using DataFrames
using Plots
using Debugger
using Formatting
using LaTeXStrings

includet("EmpgTherm.jl")
# using .EmpgTherm
struct GTInit
    q0   :: StepRange{Int64, Int64} # [mW/m^2] surface heat flow
    D    :: Float64                 # [km] thickness of upper crust
    zbot :: Vector{Int64}           # [km] base of lithospheric layers
    zmax :: Float64                 # [km] maximum depth of model
    dz   :: Float64                 # [km] depth step
    P    :: Float64                 # partition coefficient for upper crustal
                                    # heat production
    H    :: Vector{Float64}         # [uW/m^3] heat production of lithospheric
    iref :: Int64                   # index to reference heat flow
                                    # for elevation computation
    opt  :: Bool                    # Wether to apply optimization for q0
    TinC :: Bool                    # Is
end

struct Geotherm
    T :: Vector{Float64}
    z :: Vector{Float64}
    label :: String
end

struct GTResult
    ini :: GTInit
    GT :: Vector{Geotherm}
    D :: DataFrame
    max :: DataFrame
    T :: Any
end

function defaultGTInit(q0 :: StepRange{Int64, Int64} = 34:1:40,
                       opt::Bool = false,  TinC::Bool = true) :: GTInit
    GTInit(q0, 16, [16,23,39,300], 225,
           0.1, 0.74, [0,0.4,0.4,0.02], 3, opt, TinC)
end

function userComputeGeotherm(initParameters :: GTInit,
                             fileName :: String) :: GTResult
    ini = initParameters
    pt = CSV.read(fileName, DataFrame, delim=';', decimal=',')
    PGPa = pt.P_GPa
    Dkm = pt.Depth_km
    TC = pt.T_C
    if ini.TinC
        TK = TC .+ 273
    else
        TK = TC
    end

    dataf = DataFrame(Dkm=Dkm, TC=TC, TK=TK)
    maximumf = combine(dataf, [:Dkm, :TC, :TK] .=> maximum)
    println(maximumf)

    # println(pt)
    # println("Max Dkm:", max(Dkm), " TC:" max(TC), " TK:", max(TK))
    # println(format("Max Dkm:{} TC:{} TK:{}",
    #               maximum.(Dkm), maximum.(TC), maximum.(TK)))

    # geotherm parameters

    T = undef
    alpha_ = undef
    de=zeros(0)
    GTs = Vector{Geotherm}()
    for i = 1:length(ini.q0)
        # global T, alpha_, de, labels, plt
        # compute surface heat production
        A0 = (1 - ini.P) * ini.q0[i] / ini.D
        H = copy(ini.H)
        H[1] = A0

        # compute geotherm from emperical rather than long form
        # T[:,i],z,k,A,q,alpha_[:,i] = empgtherms(q0[i],zmax,dz,D,zbot,H)
        _T,z,k,A,q,_alpha_ = empgtherms(ini.q0[i],
                                        ini.zmax,
                                        ini.dz,
                                        ini.D,
                                        ini.zbot,
                                        H)
        label = format("{}", ini.q0[i])
        push!(GTs, Geotherm(_T, z, label))

        if T == undef
            T = _T
        else
            T = hcat(T,_T)
        end
        if alpha_ == undef
            alpha_ = _alpha_
        else
            alpha_ = hcat(alpha_,_alpha_)
        end

        # thermal elevation from paper (de) from emperical geotherms (dem)
        if length(ini.q0) > 1
            de = vcat(de, sum(T[:,i].*alpha_[:,i] - T[:,1].*alpha_[:,1])*ini.dz)
        end

        # plot results
        # plot(T(:,i),z,'k-');
        # format("q0[{}]={}", i, q0[i])
        ### label = format("q0[{}]={}", i, q0[i])
    end
    GTResult(ini, GTs, dataf, maximumf, T)
end

function main()
    q0 = 34:1:40         # [mW/m^2] surface heat flow
    GP = defaultGTInit(q0)

    answer = userComputeGeotherm(GP, "data/PTdata.csv")

    plt = plot()
    # push!(labels, label)
    # plot!(plt, _T, z, label = label,
    #       linewith=3, yflip=true,
    #       legend=:bottomleft)

    plot!(plt, answer.D.TC, answer.D.Dkm, seriestype=:scatter, label="Measurements")
    xlabel!(L"Temperature ${}^\circ$C");
    ylabel!("Depth [km]");
    ylims!(0, answer.ini.zmax)
    xlims!(0, ceil(maximum(answer.T[:])/100)*100+100)
    function plt_gt(gt::Geotherm)
        plot!(plt, gt.T, gt.z, label=gt.label,
              linewith=3, yflip=true,
              legend=:bottomleft)
    end
    foreach(plt_gt, answer.GT)
    #axis ij;
    #axis square;
    #set(gca,'Box','on');

    # if length(q0) > 1
    #     subplot(122); hold on;
    #     xlabel('Surface Heat Flow [mW/m^2]');
    #     ylabel('Elevation [km]');
    #     plot(q0,de-de(iref),'kx');
    #     axis square;
    #     set(gca,'Box','on');
    # else
    #     fprintf(' Depth [km]   Temperature [K]\n');
    #     for i = 1:length(z)
    #         fprintf('%7.2f       %7.2f\n',z(i),T(i));
    #     end
    # end
    savefig(plt, "geotherm.svg")
    plt = undef
end

main()
