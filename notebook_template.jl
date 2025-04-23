### A Pluto.jl notebook ###
# v0.20.6

using Markdown
using InteractiveUtils

# This Pluto notebook uses @bind for interactivity. When running this notebook outside of Pluto, the following 'mock version' of @bind gives bound variables a default value (instead of an error).
macro bind(def, element)
    #! format: off
    return quote
        local iv = try Base.loaded_modules[Base.PkgId(Base.UUID("6e696c72-6542-2067-7265-42206c756150"), "AbstractPlutoDingetjes")].Bonds.initial_value catch; b -> missing; end
        local el = $(esc(element))
        global $(esc(def)) = Core.applicable(Base.get, el) ? Base.get(el) : iv(el)
        el
    end
    #! format: on
end



# ╔═╡ 03664f5c-d45c-11e0-0000-91cd647a07aa
md"# Calculation and using model results

This page, so called \"*notebook*\", is an interactive tool for
GeoTerm model computation and a further result usage. This notebook
recalculates your model with data supplied again and again whenever a value is changed. Its usage requires knowledge of programming [Julia](https://julialang.org/learning/tutorials/) and [Pluto](https://computationalthinking.mit.edu/Spring21/installation/).

**Note:** *As of today, we cannot save the notebook on server, but You can save it (*export*) to your computer, and run it [locally](https://computationalthinking.mit.edu/Spring21/installation/), or on a [Binder cloud](https://mybinder.org/v2/gh/fonsp/pluto-on-binder/HEAD?urlpath=pluto/) (not really, I could not find a way yet), theoretically. If you press \"Pluto\" menu bar or reload this page the notebook will be regenerated, and You loose your work. So, please, process your data, save results (see a button below) before end your work.*

## Loading initial model DataSet (```DataFrame```) to fit

We load Your data, converted so as GeoTherm model can use it.
Note: This notebook will work **very slowly** (**really very slowly**)
for the first time
as it will install its model computation environment.
"

# ╔═╡ e80986c6-d509-11e9-00fd-f79a54b5ab31
begin
    using DataFrames, CSV
    using HCGeoTherm, HCGeoThermGraphics
    import PlotlyLight as PL
    using Interpolations, PlutoUI
end

# ╔═╡ e80986c6-d509-11e9-00f0-f79a54b5ab31
termdf

# ╔═╡ 03664f5c-d45c-11e0-0001-91cd647a07aa
md"## Set up initial conditions

Here we set up initial conditions, for example *q0* as
a value (```38```), a list of values (```[32,35,37]```) or a slice (```32:2:42```).
"

# ╔═╡ e80986c6-d509-11ea-0004-f79a54b5ab31
modeldata = {{{ model }}}

# ╔═╡ 03664f5c-d45c-11e0-0002-91cd647a07aa
md"## Set up major model options

Here we set define will we perform optimization stage: *\"optimize\"*,
and will we show MisFit borders on the final scatter plot: *\"misfits\"*."

# ╔═╡ e80986c6-d509-11ea-0005-f79a54b5ab31
modeloptions = {{{ opts }}}

# ╔═╡ 03664f5c-d45c-11e0-0003-91cd647a07aa
md"Essentially, we can place major options directly here, and do not
copy them from the ```modeldata``` and ```modeloptions``` variables."

# ╔═╡ e80986c6-d509-11ea-0110-f79a54b5ab31
ini = GTInit(modeldata["q0"]
             , modeldata["D"]
             , modeldata["Zbot"]
             , modeldata["Zmax"]
             , modeldata["Dz"]
             , modeldata["P"]
             , modeldata["H"]
             , modeldata["iref"]
             , modeloptions
             )

# ╔═╡ 03664f5c-d45c-11e0-0140-91cd647a07aa
md"## Main model result as a plot"

# ╔═╡ e80986c6-d509-11ea-0140-f79a54b5ab31

if "optimize" in modeloptions
    if "misfits" in modeloptions
        plotMisfit()
    else
        plotOptimal()
    end
else
    plotSeries()
end

# ╔═╡ 03664f5c-d45c-11e0-0004-91cd647a07aa
md"## Calculate our model again

Thanks to the Julia language outstanding execution speed, we can
recalculate models on-line whenever a major parameter has changed."

# ╔═╡ e80986c6-d509-11ea-0111-f79a54b5ab31
result = computeGeotherm(ini, termdf)

# ╔═╡ 03664f5c-d45c-11ea-0112-91cd647a07aa
md"## Implement interpolation functions for main result"

# ╔═╡ e80986c6-d509-11ea-0112-f79a54b5ab31
begin
    resultkeys = keys(result)
    if "optimize" in resultkeys
        resoptgt = result["optimize"].GT_opt
        # T, C -> Z, meters
        optTtoZ = linear_interpolation(resoptgt.T, resoptgt.z)
        # Z, meters -> T,C
        optZtoT = linear_interpolation(resoptgt.z, resoptgt.T)
    end
    # add conversion functions
    function GPatoKm(p) # GPa -> km
        p .* 30.4 .+ 6.3
    end

    function GPatom(p) # GPa -> m
        (p .* 30.4 .+ 6.3) .* 1000
    end

    function KmtoGPa(d) # km -> GPa
        (d .- 6.3) ./ 30.4
    end

    function mtoGPa(d) # m -> GPa
        ((d ./ 1000) .- 6.3) ./ 30.4
    end
    nothing
end

# ╔═╡ 03664f5c-d45c-11ea-0113-91cd647a07aa
md"## Use interpolation functions for **individual** values

Calculate depth in meters by temperature.
"

# ╔═╡ e80986c6-d509-11ea-0113-f79a54b5ab31
Di = optTtoZ(1000)

# ╔═╡ 03664f5c-d45c-11ea-0114-91cd647a07aa
md"Calculate temperature given depth in meters is given."

# ╔═╡ e80986c6-d509-11ea-0114-f79a54b5ab31
Ti = optZtoT(Di)

# ╔═╡ 03664f5c-d45c-11ea-0513-91cd647a07aa
md"## Use interpolation functions for **vector** values

Calculate a vector of depths in meters by a temperature vector.
"

# ╔═╡ e80986c6-d509-11ea-0513-f79a54b5ab31
Dv = begin
    # the vector of temperatures
    Tv = [200, 700, 1000, 1300]
    optTtoZ(Tv)
end

# ╔═╡ 03664f5c-d45c-11ea-0514-91cd647a07aa
md"Calculate the temperature vector by previously calculated pressure vector,
each value in meters. "

# ╔═╡ e80986c6-d509-11ea-0514-f79a54b5ab31
Tv1 = optZtoT(Dv)

# ╔═╡ 03664f5c-d45c-11ea-0515-91cd647a07aa
md"## Join values into a resulting DataFrame

DataFrame is table, consisting of columns,
each column has a name."

# ╔═╡ e80986c6-d509-11ea-0515-f79a54b5ab31
TtoDdf = DataFrame(D_m=Dv, T_C=Tv)

# ╔═╡ 03664f5c-d45c-11ea-0516-91cd647a07aa
md"DataFrames can be
saved (*exported*) in CVS and XLSX format.
Both can be easily loaded with Excel or
Libreoffice Calc applications."

# ╔═╡ e80986c6-d509-11ea-0516-f79a54b5ab31
begin
    outputFileName = "TtoD.csv"
    DownloadButton(sprint(CSV.write, TtoDdf), outputFileName)
end

# ╔═╡ 03664f5c-d45c-11e0-0200-91cd647a07aa
md"# Appendix A Set up necessary packages

These cells run before all other to setup
the environment. Runs slowly for the first time.
"

# ╔═╡ e80986c6-d509-11e9-00ff-f79a54b5ab31
using Pkg

# ╔═╡ e80986c6-d509-11e9-00fe-f79a54b5ab31
begin
    gh = "https://github.com/eugeneai/"
    Pkg.add(url=(gh * "HCGeoTherm.jl"))
    Pkg.add(url=(gh * "HCGeoThermGraphics.jl"))
    Pkg.add("DataFrames")
    Pkg.add("CSV")
    Pkg.add("PlotlyLight")
    Pkg.add("Interpolations")
    Pkg.add("PlutoUI")
end

# ╔═╡ e80986c6-d509-11ea-0001-f79a54b5ab31
termdf = begin
    df_csv = raw"{{ df_csv }}"
    csv_io = IOBuffer(df_csv)
    CSV.read(csv_io, DataFrame)
end

# ╔═╡ e80986c6-d509-11ea-0301-f79a54b5ab31
#function plt_gt(gt::Geotherm)
#    P.plot!(plt, gt.T, gt.z, label=gt.label,
#            linewith=3, yflip=true,
#            legend=:bottomleft)
#end


# ╔═╡ 03664f5c-d45c-11e0-0210-91cd647a07aa
md"### Set up view of graphics
Presets (white, black, grids, etc) are
[here](https://github.com/JuliaComputing/PlotlyLight.jl/blob/master/docs/src/templates.md)
"

# ╔═╡ e80986c6-d509-11ea-1300-f79a54b5ab31
begin
    function plotGTerms(res::GTResult,
                        p::Union{PL.Plot,Nothing}=nothing;
                        data::Bool=true,
                        series::Bool=false,
                        optimal::Bool=false)::PL.Plot
        d = res.D


        if isnothing(p)
            p = PL.plot()
        end

        p.plot(x=d.T_C, y=d.D_km, type="scatter", mode="markers", name="measured")

        maxFirst = maximum(first(res.GT).T)
        maxLast = maximum(last(res.GT).T)
        maxFL = maximum([maxFirst, maxLast])

        #    xlims=[0, ceil(maxFL/100)*100+100] # add 100 centegrees
        #    ylims=[0, res.ini.zmax+100] # add 100 m of depth

        function plt_gt(gt)
            p.plot(x=gt.T, y=gt.z, type="scatter", mode="lines", name=gt.label)
        end

        if series
            foreach(plt_gt, res.GT)
        end

        if optimal
            ogt = res.GT_opt
            p.plot(x=ogt.T, y=ogt.z,
                   type="scatter", mode="lines", name=(ogt.label * "-opt"))
        end

        ya = p.layout.yaxis
        xa = p.layout.xaxis
        ya.autorange="reversed"
        #    ya.range=ylims
        ya.title.text="D, km"
        xa.title.text="T, C"
        #    xa.range=xlims
        p
    end
    function plotSeries()::PL.Plot
        answer = result["series"]
        p = plotGTerms(answer; series=true)
        p.layout.title.text = "Geotherms of each q0 value"
        p
    end
    function plotOptimal()::PL.Plot
        answer = result["optimize"]
        p = plotGTerms(answer; optimal=true)
        p.layout.title.text = "Geotherm for optimal q0 value"
        p
    end
    function plotMisfit()::PL.Plot
        answer = result["misfits"]
        p = plotGTerms(answer; series=true)
        p.layout.title.text = "Geotherms for optimal q0 value with MisFit"
        p
    end
    nothing
end

# ╔═╡ e80986c6-d509-11ea-0302-f79a54b5ab31
begin
    plotSeries()
end

# ╔═╡ Cell order:
# ╟─03664f5c-d45c-11e0-0000-91cd647a07aa
# ╟─e80986c6-d509-11ea-0000-f79a54b5ab31
# ╟─e80986c6-d509-11e9-00fd-f79a54b5ab31
# ╠═e80986c6-d509-11e9-00f0-f79a54b5ab31
# ╟─03664f5c-d45c-11e0-0001-91cd647a07aa
# ╟─e80986c6-d509-11ea-0004-f79a54b5ab31
# ╟─03664f5c-d45c-11e0-0002-91cd647a07aa
# ╟─e80986c6-d509-11ea-0005-f79a54b5ab31
# ╟─03664f5c-d45c-11e0-0003-91cd647a07aa
# ╠═e80986c6-d509-11ea-0110-f79a54b5ab31
# ╟─03664f5c-d45c-11e0-0140-91cd647a07aa
# ╟─e80986c6-d509-11ea-0140-f79a54b5ab31
# ╟─03664f5c-d45c-11ea-0112-91cd647a07aa
# ╠═e80986c6-d509-11ea-0112-f79a54b5ab31
# ╟─03664f5c-d45c-11ea-0113-91cd647a07aa
# ╠═e80986c6-d509-11ea-0113-f79a54b5ab31
# ╟─03664f5c-d45c-11ea-0114-91cd647a07aa
# ╠═e80986c6-d509-11ea-0114-f79a54b5ab31
# ╟─03664f5c-d45c-11ea-0513-91cd647a07aa
# ╠═e80986c6-d509-11ea-0513-f79a54b5ab31
# ╟─03664f5c-d45c-11ea-0514-91cd647a07aa
# ╠═e80986c6-d509-11ea-0514-f79a54b5ab31
# ╟─03664f5c-d45c-11ea-0515-91cd647a07aa
# ╠═e80986c6-d509-11ea-0515-f79a54b5ab31
# ╟─03664f5c-d45c-11ea-0516-91cd647a07aa
# ╠═e80986c6-d509-11ea-0516-f79a54b5ab31
# ╟─03664f5c-d45c-11e0-0200-91cd647a07aa
# ╟─e80986c6-d509-11e9-00ff-f79a54b5ab31
# ╟─e80986c6-d509-11e9-00fe-f79a54b5ab31
# ╟─e80986c6-d509-11ea-0001-f79a54b5ab31
# ╟─03664f5c-d45c-11e0-0004-91cd647a07aa
# ╟─e80986c6-d509-11ea-0111-f79a54b5ab31
# ╟─e80986c6-d509-11ea-0301-f79a54b5ab31
# ╟─03664f5c-d45c-11e0-0210-91cd647a07aa
# ╟─e80986c6-d509-11ea-1300-f79a54b5ab31
# ╟─e80986c6-d509-11ea-0302-f79a54b5ab31
