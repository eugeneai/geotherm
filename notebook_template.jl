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
md"# Pluto Notebook for calculation and using model results
## Loading initial model DataSet (```DataFrame```) to fit

We load Your data, converted so as GeoTherm model can use it.
Note: This notebook will work very slowly for the first time
as it will install environment.
"

# ╔═╡ e80986c6-d509-11e9-00fd-f79a54b5ab31
using DataFrames, CSV, PlotlyLight, HCGeoTherm, HCGeoThermGraphics

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

# ╔═╡ 03664f5c-d45c-11e0-0004-91cd647a07aa
md"## Calculate our model again

Thanks to the Julia language outstanding execution speed, we can
recalculate models on-line whenever a major parameter has changed."

# ╔═╡ e80986c6-d509-11ea-0111-f79a54b5ab31
result = computeGeotherm(ini, termdf)




# ╔═╡ 03664f5c-d45c-11e0-0200-91cd647a07aa
md"## Appendix A Set up necessary packages

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
end

# ╔═╡ e80986c6-d509-11ea-0001-f79a54b5ab31
termdf = begin
    df_csv = raw"{{ df_csv }}"
    csv_io = IOBuffer(df_csv)
    CSV.read(csv_io, DataFrame)
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
# ╟─03664f5c-d45c-11e0-0004-91cd647a07aa
# ╟─e80986c6-d509-11ea-0111-f79a54b5ab31
# ╟─03664f5c-d45c-11e0-0200-91cd647a07aa
# ╟─e80986c6-d509-11e9-00ff-f79a54b5ab31
# ╟─e80986c6-d509-11e9-00fe-f79a54b5ab31
# ╟─e80986c6-d509-11ea-0001-f79a54b5ab31
