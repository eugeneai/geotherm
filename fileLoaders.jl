
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
    xf = XLSX.readxlsx(buf)
    println(xf)
end
