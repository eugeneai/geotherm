import Mongoc
import SHA
using UUIDs
using Genie, Genie.Requests
# import GenieSession
import Genie.Cookies as GC
# import GenieSession as GS
using Genie.Renderer.Json
using Genie.Renderer
import Genie.Requests as GRQ
import Genie.Responses as GE
using SMTPClient
using Base64
using Dates
using Markdown
import XLSX
import CSV
import Base.Filesystem as FS
using DataFrames
import JSON as JS
using Formatting

include("computegterm.jl")
include("fileLoaders.jl")

MB=Mongoc.BSON

mutable struct Config
    debug::Bool
    salt::String
    systemUUID::Any
    client::Any
    dbName::String
    db::Any
    noreply::String
    server::String
    defaultModelUUID::Any
    demoDataUUID::Any
end

config::Config = Config( false
                         , "salt9078563412"
                         , UUID("7a2b81c9-f1fa-41de-880d-9635f4741511")
                         , 0
                         , "geotherm"
                         , 0
                         , "UVh5Qj1lPiUyYkpyNmhUJQo=" |> base64decode |> String |> strip
                         , "https://gtherm.ru"
                         , UUID("cdda3a47-e5bb-570a-950d-f9c191e5dfbb") # Default model
                         , UUID("9413fd3d-9ad9-4e33-9869-cc4cfd884ada") # Example Data
                         )

Genie.config.run_as_server = true
Genie.config.cors_headers["Access-Control-Allow-Origin"] = "*"
# This has to be this way - you should not include ".../*"
Genie.config.cors_headers["Access-Control-Allow-Headers"] = "X-Requested-With,content-type"
Genie.config.cors_headers["Access-Control-Allow-Methods"] = "GET,POST,PUT,DELETE,OPTIONS"
Genie.config.cors_allowed_origins = ["*"]

@enum ResultLevel::Int8 begin
    OK = 0
    CACHED = 1
    INFO = 2
    DEBUG = 3
    ERROR = 10
    NOTFOUND = 11
    FATAL = 20
end

struct Result
    value::Any
    level::ResultLevel
    description::String
end

sessionCache = IdDict{String, Result}()

function cache!(f::Function, uuid::UUID)::Result
    suuid = uuid |> string
    obj = get(sessionCache, suuid, nothing)
    if isnothing(obj)
        result = f()
        if result.level < ERROR
            sessionCache[suuid] = result
        end
        return result
    else
        println("Getting from the cache")
        nobj = Result(obj.value, CACHED, "cached")
        return nobj
    end
end

function connectDb()
    mongoClient = Mongoc.Client("mongodb://localhost:27017")
    try
        println("Check connection:",Mongoc.ping(mongoClient))
    catch
        print("\nERROR: Cannot connect mongo database!\n")
        exit()
    end
    config.client = mongoClient
    return mongoClient
end

function getData(okf::Function, uuid::UUID, collection::String,
                 useruuid::Union{UUID,Nothing}=nothing)::Result
    obj = Mongoc.BSON()
    suuid = uuid |> string
    obj["uuid"] = suuid
    if ! isnothing(useruuid)
        obj["user"] = useruuid |> string
    end
    db = config.client[config.dbName]
    coll = db[collection]
    obj = Mongoc.find_one(coll, obj)
    if isnothing(obj)
        answer = MB()
        answer["uuid"]=suuid
        return Result(answer, NOTFOUND, collection * " object not found uuid=" * suuid)
    else
        # delete!(obj, "_id")
        okf(obj)
        return Result(obj, OK, "found")
    end
end

function getUserData(uuid::UUID)::Result
    cache!(uuid) do
        println("Getting from Mongo")
        getData(uuid, "users") do v
            v["password"]="******"
        end
    end
end

function getProjectData(uuid::UUID)::Result
    cache!(uuid) do
        getData(uuid, "projects") do prj
            if !haskey(prj, "model")
                prj["model"] = config.defaultModelUUID |> string
            end
        end
    end
end


function getModelData(uuid::UUID)::Result
    cache!(uuid) do
        if uuid == config.defaultModelUUID
            getDefaultModel()
        else
            rc = getData(uuid, "models") do mdl
            end
            if rc.level >= ERROR
                rc = getDefaultModel()
                Result(rc.value, rc.level,
                       rc.description * "(model lost, reset to the default)")
            else
                rc
            end
        end
    end
end

function getDefaultModel()
    mdl = MB()
    mdl["q0"] = "30:1:40"
    mdl["D"] = "16"
    mdl["Zbot"] = "[16,23,39,300]"
    mdl["Zmax"] = "255"
    mdl["Dz"] = "0.1"
    mdl["P"] = "0.74"
    mdl["H"] = "[0,0.4,0.4,0.02]"
    mdl["iref"] = "3"
    mdl["optimize"] = "false"
    mdl["uuid"] = config.defaultModelUUID |> string
    # println("---------------- HERE! ")
    # mdl["optimize"] = "true"
    # NOTE: There is no user reference!
    return Result(mdl, OK, "Default model")
end

function sendEmailApproval(user::MB)
    opt = SendOptions(
        isSSL = true,
        username = "noreply@irnok.net",
        passwd = config.noreply)
    #Provide the message body as RFC5322 within an IO

    confurl=config.server*API*"user/$(user["uuid"])/emailConfirm"

    n = Dates.now()
    ns = Dates.format(n, "e, d u Y H:M:S +0800\r\n", locale="english")
    ns = "Date: "*ns

    msg = """Dear $(user["name"])!

    Thank You for registering at our service of geotherm modeling!

    To confirm Your email, please click for the following link:

    **[Confirm email]($(confurl))**

    If You think this email was send by accident, ignore it.

    Your sincerely,
    Geotherm Developers.
    """

    md = Markdown.parse(msg)
    body = SMTPClient.get_mime_msg(md)

    body = IOBuffer(
        ns *
            "From: No Reply <noreply@irnok.net>\r\n" *
            "To: $(user["email"])\r\n" *
            "Subject: Confirm Your email in Geotherm application\r\n" *
            body
    )
    url = "smtps://smtp.gmail.com:465"
    rcpt = ["<noreply@irnok.net>"]
    from = "<$(user["email"])>"
    resp = send(url, rcpt, from, body, opt)
    println("Email RC:", resp)
end

function encryptPassword(password::String)::String
    SHA.sha256(config.salt * password) |> bytes2hex
end

function addUser(alias::String, name::String, org::String,
                 password::String, email::String) :: Result
    client = config.client
    session = client
    db = session[config.dbName]
    coll = db["users"]
    user = Mongoc.BSON()
    user["alias"] = alias
    prev = Mongoc.find_one(coll, user)
    if isnothing(prev)
        user["name"] = name
        user["org"] = org
        user["password"] = password |> encryptPassword
        user["email"] = email
        user["emailChecked"] = false
        uuid = uuid4()
        suuid = string(uuid)
        user["uuid"] = suuid
        push!(coll, user)
        sendEmailApproval(user)
        rc = Result(user, OK, "user added")
        sessionCache[suuid] = rc
        return rc
    else
        println(prev["uuid"])
        return Result(
            prev["uuid"] |> UUID ,
            ERROR, "User with this account name exists. Choose another one.")
    end
end

function logoutUser(uuid::UUID)::Result
    suuid = uuid |> string;
    # First, remove objects connected to the user
    if haskey(sessionCache, suuid)
        for (k,v) in pairs(sessionCache)
            v = v.value
            if haskey(v, "user") && v["user"] == suuid
                # println(v)  # TODO remove it
                delete!(sessionCache, k)
            end
        end
        delete!(sessionCache, suuid)
        Result(suuid, OK, "user is logged out")
    else
        Result(suuid, ERROR, "user was not logged out")
    end
end

function storeDataFrame(df, userData, projectName)::Union{UUID,Nothing}
    userSuuid = userData["uuid"]
    db = config.client[config.dbName]

    obj = Mongoc.BSON()
    obj["user"] = userSuuid
    obj["name"] = projectName
    coll = db["projects"]
    obj = Mongoc.find_one(coll, obj)

    if isnothing(obj)
        uuid = uuid4()
        suuid = uuid |> string

        r=MB()
        r["uuid"]=suuid
        r["name"]=projectName
        r["user"]=userSuuid
        r["data"]=MB(JS.json(df))
        r["model"] = config.defaultModelUUID |> string

        client = config.client
        session = client
        db = session[config.dbName]
        coll = db["projects"]
        # println(r)
        push!(coll, r)
        uuid
    else
        nothing
    end
end

function storeDataFrames(dfs, userData, projectName)::Vector{UUID}
    uuids = Vector{UUID}()
    for i in eachindex(dfs)
        (dfname, df) = dfs[i]
        uuid = storeDataFrame(df, userData, dfname)
        if ! isnothing(uuid)
            push!(uuids, uuid)
        end
    end
    uuids
end

function test()
    println("CFG:", config.client, "\n")
    u = addUser("eugeneai","Evgeny Cherkashin", "ISDCT SB RAS", "passW0rd", "eugeneai@irnok.net")
    println(u)
    println(getUserData(u.value))
end


function rj(answer::Result)
    l = answer.level
    v = answer.value
    m = answer.description
    # d = Dict{String, Any}([("value":v), ("description":d)])
    d = Dict{String, Any}([("description", m)])
    d["value"] = v
    d["level"] = UInt8(l)
    d["rcdescr"] =
        if l == OK
            "OK"
        elseif l == ERROR
            "ERROR"
        elseif l == INFO
            "INFO"
        elseif l == FATAL
            "FATAL"
        elseif l == DEBUG
            "DEBUG"
        elseif l == CACHED
            "CACHED"
        end
    if config.debug
        println("INFO:RETURNING:", json(d), l)
    end
    if l>= ERROR
        println("ERROR:RETURNING:", json(d), l)
    end
    json(d)
end

API="/api/1.0/"

route(API*"user/:uuid/data", method=POST) do
    uuid=UUID(payload(:uuid))
    rc = getUserData(uuid)
    rj(rc)
end

route(API*"user/:uuid/project/upload", method=POST) do
    uuid=UUID(payload(:uuid))
    userData = getUserData(uuid)
    if userData.level >= ERROR
        return rj(userData)
    end
    userData = userData.value
    if infilespayload(:file)
        # println("There is a file")
        httpFile = filespayload(:file)
        name = httpFile |> filename
        mime = httpFile.mime
        data = httpFile.data
        projectName,_ext = FS.splitext(name)
        # dfs = (Project-name, DataFrame)
        if mime == "text/csv"
            dfs = loadCsv(httpFile, projectName)
        elseif mime == "text/tsv"
            dfs = loadTsv(httpFile, projectName)
        elseif mime ==
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            dfs = loadXlsx(httpFile, projectName)
        else
            dfs = nothing
        end

        if isnothing(dfs) || isempty(dfs)
            rc = Result(mime, ERROR, "File type " * mime * " cannot be loaded!")
        else
            uuids = storeDataFrames(dfs, userData, projectName)
            if length(uuids) > 0
                rc = Result(uuids, OK, "File data has successfully uploaded! "
                            * format("Added {} record(s).", length(uuids)))
            else
                rc = Result(uuids, INFO, "No new data added! It seems You're already done that.")
            end
        end
    else
        rc = Result("", ERROR, "Upload had incorrect format! Contact developers!")
    end
    rj(rc)
end

route(API*"user/:uuid/logout", method=POST) do
    uuid=UUID(payload(:uuid))
    rc = logoutUser(uuid)
    rj(rc)
end

route(API*"user/register", method=POST) do
    # rc = logoutUser(uuid)
    # req=GRQ.request()
    # println(postpayload())
    user=postpayload(:JSON_PAYLOAD)
    alias=get(user, "alias", nothing)
    name=get(user, "name", nothing)
    org=get(user, "org", "")
    password=get(user, "password", nothing)
    email=get(user, "email", nothing)

    # rc=Result(alias, ERROR, "test Error")
    rc = addUser(alias, name, org, password, email)
    rj(rc)
end

route(API*"user/authenticate", method=POST) do
    println(postpayload())
    creds = postpayload(:JSON_PAYLOAD)
    alias=get(creds, "alias", "")
    password=get(creds, "password", "") |> encryptPassword
    if isnothing(alias)
        return Result("", ERROR, "No user name supplied.")
    end
    obj = Mongoc.BSON()
    obj["alias"] = alias
    db = config.client[config.dbName]
    coll = db["users"]
    # println("OBJ:", obj)
    obj = Mongoc.find_one(coll, obj)
    if isnothing(obj)
        answer = MB()
        answer["alias"]=alias
        rc = Result(answer, ERROR, "User not found!")
    else
        rc = Result(string(obj["uuid"]), OK, "Login into the account is successful!")
    end
    rj(rc)
end


route(API*"user/:uuid/projects", method=POST) do
    uuid=UUIDs.UUID(payload(:uuid))
    rc = getUserData(uuid)
    if rc.level >= ERROR
        return rj(rc)
    end

    user = rc.value;

    usersuuid = uuid |> string

    q = MB("user" => usersuuid)
    qdemo = MB("uuid" => string(config.demoDataUUID))
    lim = MB("user" => 1, "uuid" => 1, "name" => 1, "model" => 1, "data" => 0)


    client = config.client
    session = client
    db = session[config.dbName]
    coll = db["projects"]

    demoFound = false
    answer :: Vector{MB}=[];

    function canonify(a::Mongoc.BSON)::Mongoc.BSON
        row = MB()
        if ! haskey(a, "model")
            row["model"] = config.defaultModelUUID |> string
        else
            row["model"] = a["model"]
        end

        row["name"] = a["name"]
        row["model"] = a["model"]
        row["uuid"] = a["uuid"]
        row["user"] = a["user"]
        puuid = a["uuid"] |> UUID
        usuuid = a["user"]
        archivedr = getData(puuid, "tagging", UUID(usuuid)) do o
        end
        if archivedr.level == NOTFOUND
            row["tags"] = []
        else
            row["tags"] = archivedr.value["tags"]
        end
        # print(row)
        row
    end

    for a in Mongoc.find(coll, q) # must be done once
        row = canonify(a)
        if config.demoDataUUID == UUID(a["uuid"])
            demoFound = true
            tags = row["tags"]
            push!(tags, "demo")
            row["tags"] = tags
        end
        md = getModelData(UUID(row["model"]))
        if md.level >= ERROR
            return rj(md)
        end
        v = md.value
        row["modelData"] = v
        push!(answer, row)
    end

    if !demoFound
        for a in Mongoc.find(coll, qdemo) # must be done once
            row = canonify(a)
            md = getModelData(UUID(row["model"]))
            if md.level >= ERROR
                return rj(md)
            end
            v = md.value
            row["modelData"] = v
            row["name"] = "(DEMO)"*row["name"]
            row["archived"] = false
            tags = row["tags"]
            push!(tags, "demo")
            row["tags"] = tags
            push!(answer, row)
        end
    end

    rc = Result(answer, OK, "Project data, possibly empty.")
    rj(rc)
end

route(API*"project/:uuid/dataframe", method=POST) do
    uuid=UUIDs.UUID(payload(:uuid))
    rc = getProjectData(uuid)
    rj(rc)
end

route(API*"test", method=POST) do
    js = postpayload(:JSON_PAYLOAD)
    # println(js)
    uuid=js["uuid"]
    rc=Result(uuid, OK, "Server functioning")
    rj(rc)
end

function ep(s::String)::Any
    s |> Meta.parse |> eval
end

function rmHeader(svg::String)::String
    lines = split(svg, "\n")
    xmlns = lines[2]
    xmlns = replace(xmlns, r"(width|height)=\".+?\" " => s"")
    lines[2] = xmlns
    println(xmlns)
    join(lines[2:end],"\n")
end


function removeFigs(prj::Mongoc.BSON)
    m = prj
    obj = Mongoc.BSON()
    println(m)
    obj["project"] = m["uuid"]
    db = config.client[config.dbName]
    coll = db["figures"]
    obj = Mongoc.delete_many(coll, obj)
end

function saveFig(prj::Mongoc.BSON, svg::String, key::String)
    m = prj
    obj = Mongoc.BSON()
    obj["project"] = m["uuid"]
    obj["user"] = m["user"]
    obj["uuid"] = uuid4() |> string
    obj["figure"] = svg
    obj["key"] = key
    db = config.client[config.dbName]
    coll = db["figures"]
    obj = Mongoc.insert_one(coll, obj)
end

route(API*"project/:uuid/calculate", method=POST) do
    uuid=UUIDs.UUID(payload(:uuid))

    pdr = getProjectData(uuid)
    if pdr.level >= ERROR
        return rj(pdf)
    end

    prj = pdr.value

    mr = getModelData(UUID(prj["model"]))
    if mr.level >= ERROR
        return rj(mr)
    end

    m = mr.value

    # println(m)

    optimize =  m["optimize"]

    if typeof(optimize) == String
        optimize = optimize |> ep
    end

    println("Optimize:", optimize, " <- ", m["optimize"])
    # optimize = true

    ini = GTInit(m["q0"] |> ep
                 , m["D"] |> ep
                 , m["Zbot"] |> ep
                 , m["Zmax"] |> ep
                 , m["Dz"] |> ep
                 , m["P"] |> ep
                 , m["H"] |> ep
                 , m["iref"] |> ep
                 , optimize
                 )

    df = DataFrame(prj["data"])
    if haskey(prj, "rename")
        ren = prj["rename"]
        dfnew :: IdDict{String,Any} = IdDict()
        for (k,v) in ren
            if v=="ignored"
                continue
            end
            dfnew[v] = df[:, k]
        end
        df = DataFrame(dfnew)
        df = canonifyRenamedDF(df)
    else
        df = canonifyDF(df) # Try calculate as is
    end

    println(df)

    gtRes = userComputeGeotherm(ini, df)

    figIO = IOBuffer()
    figChiIO = IOBuffer()
    figOptIO = IOBuffer()

    gtOptRes = userPlot(gtRes, "", figIO, figChiIO, figOptIO)

    fig = figIO |> take! |> String
    if optimize
        figChi = figChiIO |> take! |> String
        figOpt = figOptIO |> take! |> String
    end

    # println(fig)

    removeFigs(prj)
    saveFig(prj, fig, "geotherms")
    if optimize
        saveFig(prj, figChi, "chisquare")
        saveFig(prj, figOpt, "optimized")
    end

    rc=Result("computed", OK, "Successfully computed!")
    rj(rc)
end

route(API*"project/:uuid/graphs", method=POST) do
    uuid=UUIDs.UUID(payload(:uuid))

    pdr = getProjectData(uuid)
    if pdr.level >= ERROR
        return rj(pdr)
    end
    prj = pdr.value;

    obj = Mongoc.BSON()
    obj["project"] = prj["uuid"]
    db = config.client[config.dbName]
    coll = db["figures"]
    objs = []
    for o in Mongoc.find(coll, obj)
        o["figure"] = o["figure"] |> rmHeader
        push!(objs, o)
    end
    # println(objs)
    if length(obj) == 0
        answer = MB()
        answer["uuid"]=uuid
        rc = Result(answer, ERROR, "not found")
    else
        rc = Result(objs, OK, "found")
    end

    rj(rc)
end

route(API*"project/:uuid/figure/:key", method=GET) do
    uuid=UUIDs.UUID(payload(:uuid))
    key=payload(:key)

    pdr = getProjectData(uuid)
    if pdr.level >= ERROR
        return rj(pdr)
    end
    prj = pdr.value;

    obj = Mongoc.BSON()
    obj["project"] = prj["uuid"]
    obj["key"] = key
    db = config.client[config.dbName]
    coll = db["figures"]
    obj = Mongoc.find_one(coll, obj)
    # println(objs)
    if isnothing(obj)
        resp = GE.getresponse() # response("file not found", :text)
        GE.setbody!(resp, "file not found")
        GE.setstatus!(resp, 404)
        return resp
    end
    println(obj["figure"])
    resp = GE.getresponse()
    # Content-Type: image/svg+xml
    GE.setbody!(resp, obj["figure"])
    GE.setstatus!(resp, 200)
    GE.setheaders!(resp, Dict("Content-type" => "image/svg+xml"))
end


function storeModelData(projectUuid::UUID, newData::MB)::Result
    pdr = getProjectData(projectUuid)
    if pdr.level >= ERROR
        return pdr
    end
    project = pdr.value;

    modelsuuid = project["model"]

    modelr = getModelData(UUID(modelsuuid))
    model = nothing
    if modelr.level < ERROR
        model = modelr.value
    end

    obj = Mongoc.BSON()
    db = config.client[config.dbName]
    models = db["models"]
    projects = db["projects"]

    if modelsuuid == (config.defaultModelUUID |> string)
        modelsuuid = uuid4() |> string
        obj = MB()
        obj["uuid"] = projectUuid |> string
        upd = MB()
        upd["\$set"]=MB("model" => modelsuuid)
        Mongoc.update_one(projects, obj, upd); # Set new modelUUID
        println("MODEL STORE: Created a new record")
        delete!(sessionCache, obj["uuid"]) # Invalidate project data in the session cache
    else
        obj["uuid"] = modelsuuid
        obj1 = Mongoc.delete_one(models, obj)
        println("MODEL STORE: Deleted record")
    end
    newData["uuid"] = modelsuuid
    newData["user"] = project["user"]
    Mongoc.insert_one(models,newData);
    println("MODEL STORE: Stored a record")
    sessionCache[projectUuid |> string] = Result(project, OK, "Cached project")
    sessionCache[modelsuuid ] = Result(newData, OK, "Cached Model")
    return Result(newData, OK, "Model data updated successfully!")
end

route(API*"project/:uuid/savemodel", method=POST) do
    uuid=UUIDs.UUID(payload(:uuid))
    js = postpayload(:JSON_PAYLOAD)
    #println(js)

    rc = storeModelData(uuid, MB(js))
    rj(rc)
end

route(API*"project/:uuid/setup", method=POST) do
    uuid=UUIDs.UUID(payload(:uuid))
    js = postpayload(:JSON_PAYLOAD)

    prjr = getProjectData(uuid)
    if prjr.level >= ERROR
        return rj(prjr)
    end

    prj = prjr.value

    colNames = js["colNames"]
    colRoles = js["colRoles"]

    trans :: Dict{String,String} = Dict()
    for (k,v) in zip(colNames, colRoles)
        if (k!=v)
            trans[k] = v
        end
    end

    obj = Mongoc.BSON()
    db = config.client[config.dbName]
    projects = db["projects"]
    obj = MB()
    obj["uuid"] = prj["uuid"]
    upd = MB()
    upd["\$set"]=MB("rename" => Mongoc.BSON(trans))
    Mongoc.update_one(projects, obj, upd); # Set column renaming
    delete!(sessionCache, prj["uuid"]) # Invalidate the cache data

    rc = Result(uuid |> string, OK, "Setup accepted")
    rj(rc)
end

route(API*"project/:uuid/model", method=POST) do
    uuid=UUIDs.UUID(payload(:uuid))
    prj = getProjectData(uuid)
    if prj.level >= ERROR
        return rj(prj)
    end
    rc = getModelData(UUID(prj.value["model"]))
    rj(rc)
end

route(API*"projects/changetag/:op/arg/:arg", method=POST) do
    op=payload(:op)
    arg=payload(:arg)
    js = postpayload(:JSON_PAYLOAD)
    projects = js["projects"]
    updated = []
    println("UPDATE request for ", projects, " ", op, " tag: ", arg)
    for suuid in projects
        uuid = suuid |> UUID
        prjr = getProjectData(uuid)
        if prjr.level >= ERROR
            return rj(prj)
        end
        prj = prjr.value
        delete!(sessionCache, suuid) # Invalidate the cache
        usersuuid = prj["user"]
        tagsr = getData(uuid, "tagging", UUID(usersuuid)) do o
        end
        if tagsr.level == NOTFOUND
            tags = MB()
            tags["uuid"] = suuid
            tags["user"] = usersuuid
        else
            tags = tagsr.value
        end
        update = false
        neets = []
        if op == "add"
            if tagsr.level == NOTFOUND
                tags["tags"] = [arg]
                db = config.client[config.dbName]
                coll = db["tagging"]
                Mongoc.insert_one(coll, tags)
                push!(updated, suuid)
            else
                ts = tags["tags"]
                if ! (arg in ts)
                    push!(ts, arg)
                end
                newts = ts
                update = true
            end
        elseif op=="delete"
            ts = tags["tags"]
            filter!( t-> t!=arg, ts)
            newts=ts
            update = true
        else
            return rj(Result(op, ERROR, "Unknown operation: " * op))
        end
        if update
            db = config.client[config.dbName]
            tagging = db["tagging"]
            obj=MB("uuid" => suuid, "user" => usersuuid)
            if !isempty(newts)
                upd=MB()
                upd["\$set"] = MB("tags"=>newts)
                println(obj, "\n", upd)
                Mongoc.update_one(tagging, obj, upd)
            else
                Mongoc.delete_one(tagging, obj)
            end
            push!(updated, suuid)
        end
    end
    rj(Result(updated,OK,"Projects tags have updated"))
end

function main()
    mongoClient = connectDb()
    # test()
    println("Routes -----")
    for r in routes()
        println(r)
    end
    up(8000
       , async=false)
end

if PROGRAM_FILE != ""
    main()
end
