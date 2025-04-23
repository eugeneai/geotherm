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
        # T, C -> Z, km
        optTtoZ = linear_interpolation(resoptgt.T, resoptgt.z)
        # Z, km -> T,C
        optZtoT = linear_interpolation(resoptgt.z, resoptgt.T)
    end
    # add conversion functions
    function GPatokm(p) # GPa -> km
        p .* 30.4 .+ 6.3
    end

    function kmtoGPa(d) # km -> GPa
        (d .- 6.3) ./ 30.4
    end

    nothing
end

# ╔═╡ 03664f5c-d45c-11ea-0113-91cd647a07aa
md"## Use interpolation functions for **individual** values

Calculate depth in km by temperature.
"

# ╔═╡ e80986c6-d509-11ea-0113-f79a54b5ab31
Di = optTtoZ(1000)

# ╔═╡ 03664f5c-d45c-11ea-0114-91cd647a07aa
md"Calculate temperature, when depth in km is given."

# ╔═╡ e80986c6-d509-11ea-0114-f79a54b5ab31
Ti = optZtoT(Di)

# ╔═╡ 03664f5c-d45c-11ea-0513-91cd647a07aa
md"## Use interpolation functions for **vector** values

Calculate a vector of depths in km by a temperature vector.
"

# ╔═╡ e80986c6-d509-11ea-0513-f79a54b5ab31
Dv = begin
    # the vector of temperatures
    Tv = [200, 700, 1000, 1300]
    optTtoZ(Tv)
end

# ╔═╡ 03664f5c-d45c-11ea-0514-91cd647a07aa
md"Calculate the temperature vector by previously calculated depth vector,
each value in km. "

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

# ╔═╡ 311f9300-22de-40b3-9f74-c471518a5597
md"## Loading data from file on Your wonderful computer
Now we try import data from csv file and process it."

# ╔═╡ f5299cac-898a-4cee-8021-a8710d311533
@bind csvfile PlutoUI.FilePicker([MIME("text/csv")])

# ╔═╡ dcd06e6a-a2b7-4cb8-9346-5995c4f0332d
csvfile

# ╔═╡ 5568793d-fd84-413f-8ce7-c84b5cc55a08
newdf_ =
    if ! isnothing(csvfile)
        input = IOBuffer(csvfile["data"])
        # Adjust input format with parameter values
        CSV.read(input, DataFrame, delim=';', decimal=',')
    else
        # No input data chosen, take user data as example
        df_ = DataFrame(t=termdf.T_C)
        # filter values out of extrapolation interval
        filter(row -> row.t <= 1000, df_)
    end


# ╔═╡ 6a3eb029-7d30-4d28-9c9a-492337b0b3cd
md"Now, let's apply model data interpolation to a DataFrame *t* column and save it to a variable. "

# ╔═╡ ac587e76-db9b-4c72-9b37-7bc32a6ec1e3
outD = optTtoZ(newdf_.t)

# ╔═╡ 7803fa55-408d-4058-a877-a2d09ecf99e9
md"Add new column with calculated depts in km to the newly input DataFrame"

# ╔═╡ 50f8a692-5a59-4140-8ede-17b4f65f3f86
begin
    newdf = copy(newdf_)
    newdf.D_km = outD
    newdf
end

# ╔═╡ 16bcc669-c7db-47e9-88a5-612833014159
md"And, finally, save result in a CSV-file."

# ╔═╡ 266919ec-87f8-4b02-9f88-89af19184eb5
begin
    newOutputFileName = "new.csv"
    DownloadButton(sprint(CSV.write, newdf), newOutputFileName)
end

# ╔═╡ 16bcc669-c7db-47e9-0001-612833014159
md"In addition, Let's show calculated dots on plot, if possible."

# ╔═╡ 266919ec-87f8-4b02-0001-89af19184eb5
if "optimize" in modeloptions
    if "misfits" in modeloptions
        pmf = plotMisfit(; data=false)
    else
        pmf = plotOptimal(; data=false)
    end
    pmf.plot(x=newdf.t, y=newdf.D_km, type="scatter",
             mode="markers", name="model")
else
    nothing
end



# ╔═╡ 03664f5c-d45c-11e0-0200-91cd647a07aa
md"# Appendix A: Set up necessary packages

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

# ╔═╡ 266919ec-87f8-4b02-0000-89af19184eb5
begin
    DownloadButton(sprint(CSV.write, termdf), "initial-data.csv")
end

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

        if data
            p.plot(x=d.T_C, y=d.D_km, type="scatter", mode="markers", name="measured")
        end

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
    function plotSeries(; data=true)::PL.Plot
        answer = result["series"]
        p = plotGTerms(answer; series=true, data=data)
        p.layout.title.text = "Geotherms of each q0 value"
        p
    end
    function plotOptimal(; data=true)::PL.Plot
        answer = result["optimize"]
        p = plotGTerms(answer; optimal=true, data=data)
        p.layout.title.text = "Geotherm for optimal q0 value"
        p
    end
    function plotMisfit(; data=true)::PL.Plot
        answer = result["misfits"]
        p = plotGTerms(answer; series=true, data=data)
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
# ╠═03664f5c-d45c-11ea-0516-91cd647a07aa
# ╠═e80986c6-d509-11ea-0516-f79a54b5ab31
# ╟─311f9300-22de-40b3-9f74-c471518a5597
# ╠═f5299cac-898a-4cee-8021-a8710d311533
# ╟─dcd06e6a-a2b7-4cb8-9346-5995c4f0332d
# ╠═5568793d-fd84-413f-8ce7-c84b5cc55a08
# ╟─6a3eb029-7d30-4d28-9c9a-492337b0b3cd
# ╠═ac587e76-db9b-4c72-9b37-7bc32a6ec1e3
# ╟─7803fa55-408d-4058-a877-a2d09ecf99e9
# ╠═50f8a692-5a59-4140-8ede-17b4f65f3f86
# ╟─16bcc669-c7db-47e9-88a5-612833014159
# ╠═266919ec-87f8-4b02-9f88-89af19184eb5
# ╟─16bcc669-c7db-47e9-0001-612833014159
# ╠═266919ec-87f8-4b02-0001-89af19184eb5
# ╟─03664f5c-d45c-11e0-0200-91cd647a07aa
# ╟─e80986c6-d509-11e9-00ff-f79a54b5ab31
# ╟─e80986c6-d509-11e9-00fe-f79a54b5ab31
# ╟─e80986c6-d509-11ea-0001-f79a54b5ab31
# ╟─266919ec-87f8-4b02-0000-89af19184eb5
# ╟─03664f5c-d45c-11e0-0004-91cd647a07aa
# ╟─e80986c6-d509-11ea-0111-f79a54b5ab31
# ╟─e80986c6-d509-11ea-0301-f79a54b5ab31
# ╟─03664f5c-d45c-11e0-0210-91cd647a07aa
# ╟─e80986c6-d509-11ea-1300-f79a54b5ab31
# ╟─e80986c6-d509-11ea-0302-f79a54b5ab31
