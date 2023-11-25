# using Revise
using CSV
using DataFrames
using Plots
import Plots
using Debugger
using Formatting
using LaTeXStrings
using Interpolations
using Optim

include("EmpgTherm.jl")

appRoot="/var/tmp"

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
    q0:: Float64
    az:: Float64
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

function depth(p) # GPa -> km
    p .* 30.4 .+ 6.3
end

function pressure(d) # km -> GPa
    (d .- 6.3) ./ 30.4
end

function canonifyDF(pt::DataFrame)::DataFrame
    pt_n = names(pt)
    println(pt_n)
    TC = pt.t
    TK = TC .+ 273
    if !("d" in pt_n)
        if ("p" in pt_n)
            PGPa = pt.p
        elseif ("pm" in pt_n)
            PGPa = pt.pm
        elseif ("pk" in pt_n)
            PGPa = pt.pk / 10.0
        end
        Dkm=depth(PGPa)
    else
        Dkm = pt.d
        PGPa = pt.d |> pressure
    end
    DataFrame(D_km=Dkm, P_GPa=PGPa, T_C=TC, T_K=TK)
end

function canonifyRenamedDF(pt::DataFrame)::DataFrame
    pt_n = names(pt)
    println(pt_n)
    if "T_C" in pt_n
        TC = pt.T_C
        TK = TC .+ 273
    elseif "T_K" in pt_n
        TK = pt.T_K
        TC = TK .- 273
    end
    if "D_km" in pt_n
        Dkm = pt.D_km
        PGPa = Dkm |> pressure
    elseif "D_m" in pt_n
        Dkm = pt.D_m ./ 1000
        PGPa = Dkm |> pressure
    elseif "P_GPa" in pt_n
        PGPa = pt.P_GPa
        Dkm = PGPa |> depth
    elseif "P_kbar" in pt_n
        PGPa = pt.P_kbar ./ 10.0
        Dkm = PGPa |> depth
    end
    DataFrame(D_km=Dkm, P_GPa=PGPa, T_C=TC, T_K=TK)
end


function userLoadCSV(fileName :: String) :: DataFrame
    pt = CSV.read(fileName, DataFrame, delim=';', decimal=',')
    pt |> canonifyDF
end

function userComputeGeotherm(initParameters :: GTInit,
                             dataf :: DataFrame) :: GTResult
    ini = initParameters
    println("Initial parameters:")
    println(ini)
    maximumf = combine(dataf, [:D_km, :T_C, :T_K] .=> maximum)
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
        # println("P: ", ini.P)
        # println("D: ", ini.D)
        # println("i: ", i)
        # println("q0: ", ini.q0)
        # println("q0[i]: ", ini.q0[i])
        # println("A0: ", A0)
        H = copy(ini.H)
        H[1] = A0

        # compute geotherm from emperical rather than long form
        # T[:,i],z,k,A,q,alpha_[:,i],az = empgtherms(q0[i],zmax,dz,D,zbot,H)
        _T,z,k,A,q,_alpha_,az = empgtherms(ini.q0[i],
                                        ini.zmax,
                                        ini.dz,
                                        ini.D,
                                        ini.zbot,
                                        H)
        if az>0.0
            label = format("{} ({})", ini.q0[i], az)
        else
            label = format("{}", ini.q0[i])
        end
        push!(GTs, Geotherm(_T, z, label,ini.q0[i],az))

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
    ifu = interpolate(ys, BSpline(Cubic(Throw(OnGrid()))))
    #ifu = interpolate(ys, BSpline(Quadratic()))
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
        cT = (gti(row.D_km)-row.T_C)^2
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
    q0 = 33:0.2:40         # [mW/m^2] surface heat flow
    # q0 = 20:10:100         # [mW/m^2] surface heat flow
    GP = defaultGTInit(q0, true)
    dataf = userLoadCSV("./data/PT Ybileynaya_Gtherm.csv")
    answer = userComputeGeotherm(GP, dataf)
    userPlot(answer, appRoot,
             "geotherm.svg",
             "geotherm-chisquare.svg",
             "geotherm-opt.svg")
end

function userPlot(answer::GTResult,
                  appRoot::String,
                  geothermfig::Any,
                  geothermChiSquarefig::Any,
                  geothermOptfig::Any
                  )::Union{GTResult,Nothing}
    plt = plot()

    plot!(plt, answer.D.T_C, answer.D.D_km, seriestype=:scatter, label="Measurements")
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

    function _savefig(plt, pathName)
        println("SaveFig into " * pathName )
        savefig(plt, pathName)
    end

    if typeof(geothermfig) == String
        _savefig(plt, appRoot * "/" * geothermfig)
    else
        Plots.svg(plt, geothermfig)
    end

    if answer.ini.opt
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
            # print("Calc: ", x)
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
        # print("Minimum:", minx, "\n")
        plot!(plt, [minx], [miny], seriestype=:scatter,
              markercolor = :red,
              label=format(L"Appox. $\min\quad {{q_0}}={}$", minx),
              legend=:top)

        xlabel!(L"$q_0$ value")
        ylabel!(L"$\chi^2$")
        # ylims!(0, answer.ini.zmax)
        # xlims!(0, ceil(maximum(answer.T[:])/100)*100+100)

        if typeof(geothermChiSquarefig) == String
            _savefig(plt, appRoot * "/" * geothermChiSquarefig)
        else
            Plots.svg(plt, geothermChiSquarefig)
        end

        plt = undef

        # print("Compiling for an optimal q0\n")

        q0 = convert(Float64, minx)         # [mW/m^2] surface heat flow

        ai = answer.ini

        gpOpt = GTInit([q0], ai.D, ai.zbot, ai.zmax, ai.dz, ai.P, ai.H, ai.iref, false)

        answero = userComputeGeotherm(gpOpt, answer.D)

        plt = plot()

        plot!(plt, answero.D.T_C, answero.D.D_km,
              seriestype=:scatter, label="Measurements")
        xlabel!(L"Temperature ${}^\circ$C");
        ylabel!("Depth [km]");
        ylims!(0, answero.ini.zmax)
        xlims!(0, ceil(maximum(answero.T[:])/100)*100+100)

        foreach(plt_gt, answero.GT)
        # print(answero.GT)
        if typeof(geothermOptfig) == String
            _savefig(plt, appRoot * "/" * geothermOptfig)
            print("Saved " * appRoot * "/" * geothermOptfig)
        else
            Plots.svg(plt, geothermOptfig)
        end
        answero
    else
        nothing
    end
end

# function main()
#     run()
# end

# main()

# GTInit(33.0:0.2:40.0, 16.0, [16, 23, 39, 300], 225.0, 0.1, 0.74, [0.0, 0.4, 0.4, 0.02], 3, true)
# GTInit(30:1:40,       16.0, [16, 23, 39, 300], 255.0, 0.1, 0.74, [0.0, 0.4, 0.4, 0.2], 3, false)
