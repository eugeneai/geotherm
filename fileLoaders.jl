
using DataFrames
import XLSX
using Formatting

DataFrameArrayOrNothing = Union{Array{DataFrame},Nothing}

function loadTsv(httpFile)::DataFrameArrayOrNothing
end

function loadCsv(httpFile)::DataFrameArrayOrNothing
    (name, ext) = FS.splitext(httpFile.name)
    pt = CSV.read(httpFile.data, DataFrame, delim=';', decimal=',')
    [pt]
    # [pt |> canonifyDF]
    #println(df)
    #Result(df, OK, "Read")
end


function loadXlsx(httpFile)::DataFrameArrayOrNothing
    buf = IOBuffer(httpFile.data)
    tables = recognizeXlsx(buf)
    rc = DataFrame(tables)
    println(rc)
    rc
end

function recognizeXlsx(buf)::Dict{String,Any}
    xf = XLSX.readxlsx(buf)
    maxwidth = 10
    maxheight = 1000
    maxvskip = 20
    maxhskip = 20
    rc::Array{DataFrame} = []
    tables = Dict()
    for sname in XLSX.sheetnames(xf)
        println("Sheet " * sname)
        tbl = Dict()
        sh = xf[sname]
        rs = maxhskip + maxheight
        cc = maxvskip + maxwidth
        found = false
        for r in 1:maxvskip
            for c in 1:maxhskip
                cell = sh[r,c]
                # println(r, "-", c, "=", cell)
                if typeof(cell) in [Float64, String]
                    cc = min(cc,c)
                    rs = min(rs,r)
                    found = true
                end
            end
        end
        if ! found
            continue
        else
            println("top-left:",cc,":",rs)
        end
        for c in cc:cc+maxwidth
            col::Array{Union{String,Float64,Missing}} = []
            stop = false
            found = false
            lastNotMissingRow = nothing
            for r in rs:rs+maxheight
                cell = sh[r,c]
                # println(r, " ", c," ", cell)
                push!(col, cell)
                if typeof(cell) in [Float64, String]
                    found = true
                    lastNotMissingRow = r-rs+1
                end
            end
            if found
                col = col[1:lastNotMissingRow]
                # println(col)
                if typeof(col[1]) == Missing
                    name = format("V_{}", c-cc+1)
                else
                    name = format("{}", col[1])
                end
                if length(col) > 2
                    tbl[name] = col[2:end]
                end
            end
        end
        if ! isempty(tbl)
            tables[sname] = tbl
        end
    end
    # println(tables)
    tables
end


function localMain()::Dict{String, Any}
    buf = open("data/test.xlsx", "r")
    recognizeXlsx(buf)
end

if PROGRAM_FILE != ""
    localMain()
end
