# push!(LOAD_PATH,pwd())
using Revise
using CSV
using DataFrames
using Plots
using Debugger
using Formatting
using LaTeXStrings
using Interpolations
using Optim

includet("EmpgTherm.jl")
# using .EmpgTherm
struct GTInit
    q0   :: Any
        # StepRange{Int64, Int64} # [mW/m^2] surface heat flow
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

function defaultGTInit(q0 = 34:1:40,
                       opt::Bool = false) :: GTInit
    GTInit(q0, 16, [16,23,39,300], 225,
           0.1, 0.74, [0,0.4,0.4,0.02], 3, opt)
end

function userLoadCSV(fileName :: String) :: DataFrame
    pt = CSV.read(fileName, DataFrame, delim=';', decimal=',')
    PGPa = pt.P_GPa
    Dkm = pt.Depth_km
    TC = pt.T_C
    TK = TC .+ 273
    dataf = DataFrame(D_km=Dkm, P_mPa=Dkm, T_C=TC, T_K=TK)
    return dataf
end

function userComputeGeotherm(initParameters :: GTInit,
                             dataf :: DataFrame) :: GTResult
    ini = initParameters
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


function myInterpolate(xs, ys)
    b = minimum(xs)
    e = maximum(xs)
    dx = (e-b)/(length(xs)-1)
    ifu = interpolate(ys, BSpline(Cubic()))
    # ifu = interpolate(ys, BSpline(Quadratic()))
    function f(x)
        bb = x.-b
        v = bb./dx
        ifu(v.+1)
    end
    f
end

function chisquareGT(GT::Geotherm, D::DataFrame) :: Float64
    z = GT.z
    T = GT.T
    gti = myInterpolate(z,T)
    s = 0.0 :: Float64
    for row in eachrow(D)
        cT = (gti(row.Dkm)-row.TC)^2
        s = s + cT
    end
    s
end

function chisquare(result::GTResult) :: Any
    qs = result.ini.q0
    chis = Vector{Float64}()
    for (i, q) in enumerate(qs)
        chi = chisquareGT(result.GT[i], result.D)
        push!(chis, chi)
    end
    (qs, myInterpolate(qs, chis))
end

function optimize1(f,
                  start::Float64,
                  dx::Float64=0.1,
                  eps::Float64=0.001) :: Float64
    # Simple bitwise approximation
    x = start
    dir = 1.0
    pf = f(x-dx)
    df = dx
    while abs(df) > eps
        nf = f(x)
        if abs(nf)>abs(pf)
            dir = 0-dir
            dx = dx/2.0
        end
        x = x + dx
        df = nf-pf
        pf = nf
    end
    x
end

function run()
    # q0 = 34:1:40         # [mW/m^2] surface heat flow
    q0 = 20:10:100         # [mW/m^2] surface heat flow
    GP = defaultGTInit(q0)
    dataf = userLoadCSV("data/PTdata.csv")
    answer = userComputeGeotherm(GP, dataf)

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

    plt = plot()
    (xs, ifu) = chisquare(answer)
    nxsb = minimum(xs)
    nxse = maximum(xs)
    nxs = nxsb:((nxse-nxsb)/100):nxse
    plot!(plt, nxs, ifu(nxs), linewith=3, label=L"Cubic BSpline of $\chi^2$",)
    plot!(plt, xs, ifu(xs), seriestype=:scatter,
          label=L"$\chi^2$", markercolor = :green)
    sp = convert(Float64, nxsb + (nxse-nxsb)/2)
    function ifuo(v::Vector{Float64})
        x = v[1]
        print("Calc: ", x)
        ifu(x)
    end

    function ifu1(x::Float64)::Float64
        # print(format("Calc: {}\n", x))
        ifu(x)
    end

    res = optimize(ifu1,
                   convert(Float64, nxsb),
                   convert(Float64, nxse),
                   GoldenSection())
    miny = Optim.minimum(res)
    minx = Optim.minimizer(res)
    print("Minimum:", minx, "\n")
    plot!(plt, [minx], [miny], seriestype=:scatter,
          markercolor = :red,
          label=format(L"Appox. $\min\quad {{q_0}}={}$", minx),
          legend=:top)

    xlabel!(L"$q_0$ value")
    ylabel!(L"$\chi^2$")
    # ylims!(0, answer.ini.zmax)
    # xlims!(0, ceil(maximum(answer.T[:])/100)*100+100)
    savefig(plt, "geotherm-chisquare.svg")
    plt = undef

    print("Compiling for an optimal q0\n")



    q0 = convert(Float64, minx)         # [mW/m^2] surface heat flow

    GPopt = defaultGTInit([q0])

    answero = userComputeGeotherm(GPopt, "data/PTdata.csv")

    plt = plot()

    plot!(plt, answero.D.TC, answero.D.Dkm,
          seriestype=:scatter, label="Measurements")
    xlabel!(L"Temperature ${}^\circ$C");
    ylabel!("Depth [km]");
    ylims!(0, answero.ini.zmax)
    xlims!(0, ceil(maximum(answero.T[:])/100)*100+100)
    # function plt_gt(gt::Geotherm)
    #     plot!(plt, gt.T, gt.z, label=gt.label,
    #           linewith=3, yflip=true,
    #           legend=:bottomleft)
    # end
    foreach(plt_gt, answero.GT)
    savefig(plt, "geotherm-opt.svg")

end

function main()
end

main()
