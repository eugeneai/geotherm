# import Mongoc
import KyotoCabinet as KC
import SHA
using UUIDs
using Genie, Genie.Requests
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
import Logging
using BSON
import Base
using HCGeoTherm
using HCGeoThermGraphics

# Sending JSON converts UUID into hex string,
# see JS.lower
# Receiving JSON does not convert into UUID!
# But the receiving is performed much less frequently!


debug_logger = Logging.ConsoleLogger(stderr, Logging.Debug)
info_logger = Logging.ConsoleLogger(stderr, Logging.Info)
default_logger = Logging.global_logger(info_logger)

include("fileLoaders.jl")

@enum ResultLevel::Int8 begin
    OK = 0
    CACHED = 1
    INFO = 2
    DEBUG = 3
    ERROR = 10
    NOTFOUND = 11
    FATAL = 20
end

# Checking OK - if foo.level < ERROR then ... OK....

struct Result
    value::Any
    level::ResultLevel
    description::String
end

SU = Union{String, UUIDs.UUID}
DataDict = Dict{SU, Any}
sessionCache = Dict{SU, Result}()

mutable struct Config
    debug::Bool
    salt::String
    systemUUID::UUID
    dbLocation::String # A directory with data
    dbName::String
    indexType::String # KyotoCabinet file extension type, e.g., kch.
    db::Any
    noreply::String
    server::String
    defaultModelUUID::UUID
    demoDataUUID::UUID
end

mutable struct DD  # A database KyotoCabinet Dictionary
    name::String
    index::String
    db::Any
end

mutable struct Database
    id :: DD        # UUID -> Struct, Each struct MUST have "uuid":UUID(....) field
    alias :: DD     # String (User or project Alias) -> UUID
end

dbId = DD("ids", "kch", nothing)
dbAlias = DD("aliases", "kch", nothing)

config::Config = Config( false # Debug
                         , "salt9078563412"
                         , UUID("7a2b81c9-f1fa-41de-880d-9635f4741511") # systemUUID
                         , "./storage"
                         , "geotherm"
                         , "kch"
                         , nothing  # db
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

JS.lower(x::UUIDs.UUID) = x |> string

function cache!(f::Function, uuid::UUID)::Result
    Logging.with_logger(debug_logger) do
        obj = get(sessionCache, uuid, nothing)
        if isnothing(obj)
            result = f()
            if result.level < ERROR
                sessionCache[uuid] = result
            end
            return result
        else
            @debug "Getting from the cache"
            descr = obj.description
            nobj = Result(obj.value, CACHED, descr * "(cached)")
            return nobj
        end
    end
end

function Base.convert(t::Type{KC.Bytes}, uuid::UUID)::KC.Bytes
    reinterpret(UInt8, [uuid.value]) |> KC.Bytes
end

function Base.convert(t::Type{UUID}, v::KC.Bytes)::UUID
    vs = reinterpret(UInt128, v) |> Vector
    UUID(vs[0])
end

function Base.convert(t::Type{KC.Bytes}, d::DataDict)::KC.Bytes
    io = IOBuffer()
    BSON.bson(io, d)
    take!(io)
end

function Base.convert(t::Type{DataDict}, v::KC.Bytes)::DataDict
    io = IOBuffer(v)
    BSON.load(io)::t
end

function _connDb(f::Function, dd::DD)
    db = f(DD)
    try
        dbFullPath = config.dbLocation * "/" * config.dbName * "-" * DD.name * "." * DD.indexType
        KC.open(db, dbFullPath
                  , KC.KCOWRITER | KC.KCOCREATE)
        @info ("Database mapping '" * dbFullPath * "' opened!")
    catch
        @error ("Cannot connect KyotoCabinet database mapping! Name:" * dbFullPath)
        exit()
    end
    dd.db=db
    return db
end

function connectDb()
    Logging.with_logger(debug_logger) do
        _connDb(dbId) do dd
            db=KC.Db{UUID, DataDict}()
            @debug "Created id database"
            if !haskey(db, config.defaultModelUUID)
                @info "Add default model!"
            end
            db
        end
        _connDb(dbAlias) do dd
            KC.Db{String, UUID}()
            @debug "Created alias database"
        end
        config.db = Database(dbId, dbAlias)
        return config.db
    end
end

UN = Union{UUID,Nothing}

function ids()
    config.db.id
end

function aliases()
    config.db.alias
end

function getData(okf::Function, uuid::UUID)::Result
    Logging.with_logger(debug_logger) do
        db = ids()
        try
            obj = db[uuid]
            okf(obj)
            @debug "Object loaded" uuid=uuid
            return Result(obj, OK, "found")
        catch
            answer = DataDict()
            answer["uuid"]=uuid
            @error "Object not found" uuid=uuid
            return Result(answer, NOTFOUND, "object not found")
        end
    end
end

function putData(obj::DataDict)
    Logging.with_logger(debug_logger) do
        db = ids()
        if !haskey(obj, "uuid")
            @error "object has no uuid" obj=obj
            error("object has no uuid")
        end
        uuid = obj["uuid"]::UUID
        db[uuid]=obj
        @debug "Object stored" uuid=uuid
    end
end

function deleteData(uuid::UUID)
    Logging.with_logger(debug_logger) do
        if !haskey(ids(), uuid)
            @warn "Object not found" uuid=uuid
        else
            delete!(ids(), uuid)
            @debug "Removed object by uuid" uuid=uuid
        end
    end
end

function deleteData(obj::DataDict)
    Logging.with_logger(debug_logger) do
        if !haskey(obj["uuid"])
            @error "object has no uuid" obj=obj
            error("object has no uuid")
        end
        uuid = obj["uuid"]::UUID
        deleteData(uuid)
        @debug "Removed object" uuid=uuid
    end
end


function getUserData(uuid::UUID, removePassword::Bool=true)::Result
    Logging.with_logger(debug_logger) do
        cache!(uuid) do
            getData(uuid) do v
                if removePassword
                    v["password"]="******"
                end
            end
            @debug "Loaded user data from KyotoCabinet"
        end
    end
end

function getProjectData(uuid::UUID)::Result
    getData(uuid) do prj
        if !haskey(prj, "model")
            prj["model"] = config.defaultModelUUID
        end
    end
end

function getModelData(uuid::UUID)::Result
    if uuid == config.defaultModelUUID
        getDefaultModel()
    else
        rc = getData(uuid) do mdl end
        if rc.level >= ERROR
            rc = getDefaultModel()
            Result(rc.value, rc.level,
                   rc.description * "(model has lost somewhere, reset to the default one)")
        else
            rc
        end
    end
end

function getDefaultModel()
    mdl = DataDict()
    mdl["q0"] = "30:1:40"
    mdl["D"] = "16"
    mdl["Zbot"] = "[16,23,39,300]"
    mdl["Zmax"] = "255"
    mdl["Dz"] = "0.1"
    mdl["P"] = "0.74"
    mdl["H"] = "[0,0.4,0.4,0.02]"
    mdl["iref"] = "3"
    mdl["optimize"] = "false"
    mdl["uuid"] = config.defaultModelUUID
    return Result(mdl, OK, "Default model")
end

function sendEmailApproval(user::DataDict)
    opt = SendOptions(
        isSSL = true,
        username = "noreply@irnok.net",
        passwd = config.noreply)
    #Provide the message body as RFC5322 within an IO

    confurl=config.server * API * "user/$(user["uuid"])/emailConfirm"

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
    @info ("Email RC:", resp)
end

function encryptPassword(password::String)::String
    SHA.sha256(config.salt * password) |> bytes2hex
end

function addUser(alias::String, name::String, org::String,
                 password::String, email::String) :: Result
    Logging.with_logger(debug_logger) do
        alias = aliases()

        key="USER-" * alias

        if haskey(alias, key)
            uuid = alias[key]
            @warn "User not found" alias=alias
            return Result(
                DataDict("uuid" => uuid) ,
                ERROR, "User with this account name exists. Choose another one.")
        end

        user = DataDict()
        user["alias"] = alias
        user["name"] = name
        user["org"] = org
        user["password"] = password |> encryptPassword
        user["email"] = email
        user["emailChecked"] = false
        uuid = uuid1()
        user["uuid"] = uuid
        putData(user)
        alias[key]=uuid
        sendEmailApproval(user)
        rc = Result(user, OK, "user added")
        sessionCache[uuid] = rc
        return rc
    end
end

function logoutUser(uuid::UUID)::Result
    Logging.with_logger(debug_logger) do
        if haskey(sessionCache, uuid)
            for (k,v) in pairs(sessionCache)
                v = v.value
                if haskey(v, "user") && v["user"] == uuid # TODO: Check UUID or it's a String
                    @debug "Removing user owned object from sessionCache" k=k
                    delete!(sessionCache, k)
                end
            end
            @debug "Removing user sessionCache" uuid=uuid
            delete!(sessionCache, uuid)
            Result(DataDict("uuid"=>uuid), OK, "user is logged out")
        else
            Result(DataDict("uuid"=>uuid), ERROR, "user was not logged out")
        end
    end
end

function storeDataFrame(df, userData, projectName, uuid::UN=nothing)::UN
    Logging.with_logger(debug_logger) do
        useruuid = userData["uuid"]

        key = "PROJECT-" * projectName

        alias = aliases()

        if !haskey(alias, key)
            @debug "No frame name found" key=key
            if isnothing(uuid)
                uuid = uuid1()
            end
            r=DataDict()
            r["uuid"]=uuid
            r["name"]=projectName
            r["user"]=useruuid
            r["data"]=df# JS.json(df)
            r["model"] = config.defaultModelUUID
            putData(r)
            @debug "Stored new project" uuid=uuid key=key
            alias[key] = uuid
            uuid
        else
            nothing
        end
    end
end

function storeDataFrames(dfs, userData, projectName)::Vector{UUID}
    Logging.with_logger(debug_logger) do
        uuids = Vector{UUID}()
        for i in eachindex(dfs)
            (dfname, df) = dfs[i]
            uuid = storeDataFrame(df, userData, dfname)
            if !isnothing(uuid)
                @debug "Added project" uuid=uuid name=dfname
                push!(uuids, uuid)
            end
        end
        uuids
    end
end

function rj(answer::Result)
    Logging.with_logger(debug_logger) do
        l = answer.level
        v = answer.value
        m = answer.description

        d = DataDict([("description", m)])
        d["value"] = v
        d["level"] = convert(UInt8, l)
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
        @debug "INFO:RETURNING:" json=json(d) l=l
        if l>= ERROR
            @warn "ERROR:RETURNING:" json=json(d) l=l
        end
        json(d)
    end
end

API="/api/1.0/"

route(API*"user/:uuid/data", method=POST) do
    Logging.with_logger(debug_logger) do
        uuid=UUID(payload(:uuid))
        rc = getUserData(uuid)
        @debug "user/..../data" uuid=uuid rc=rc
        rj(rc)
    end
end

route(API*"user/:uuid/project/upload", method=POST) do
    Logging.with_logger(debug_logger) do
        uuid=UUID(payload(:uuid))
        userData = getUserData(uuid)
        if userData.level >= ERROR
            return rj(userData)
        end
        userData = userData.value
        if infilespayload(:file)
            httpFile = filespayload(:file)
            name = httpFile |> filename
            mime = httpFile.mime
            data = httpFile.data
            @debug "A file received" name=name mime=mime
            projectName,_ext = FS.splitext(name)
            # dfs = (Project-name, DataFrame)
            if mime == "text/csv"
                dfs = loadCsv(httpFile, projectName)
                @debug "Loaded CSV" name=projectName
            elseif mime == "text/tsv"
                dfs = loadTsv(httpFile, projectName)
                @debug "Loaded TSV" name=projectName
            elseif mime ==
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
                dfs = loadXlsx(httpFile, projectName)
                @debug "Loaded XLSX" name=projectName
            else
                dfs = nothing
            end

            if isnothing(dfs) || isempty(dfs)
                @warn "Did not load anything" mime=mime
                rc = Result(mime, ERROR, "File type " * mime * " cannot be loaded!")
            else
                uuids = storeDataFrames(dfs, userData, projectName)
                if length(uuids) > 0
                    rc = Result(DataDict("uuids"=>uuids),
                                OK, "File data has successfully uploaded! "
                                * format("Added {} record(s).", length(uuids)))
                else
                    @debug "No new data found"
                    rc = Result(uuids, INFO, "No new data added! It seems You're already done that.")
                end
            end
        else
            @warn "Incorrect format of upload data"
            rc = Result("", ERROR, "The uploads had incorrect format! Contact developers!")
        end
        rj(rc)
    end
end

route(API*"user/:uuid/logout", method=POST) do
    Logging.with_logger(debug_logger) do
        uuid=UUID(payload(:uuid))
        rc = logoutUser(uuid)
        rj(rc)
    end
end

route(API*"user/:uuid/update", method=POST) do
    Logging.with_logger(debug_logger) do
        uuid=UUID(payload(:uuid))
        userData=postpayload(:JSON_PAYLOAD)

        userr = getUserData(uuid, false)
        if userr.level >= ERROR
            return rj(Result(userr.value, ERROR, "Cannot find user! " * userr.description))
        end

        user = userr.value;

        tryPassword = userData["activePassword"]
        tryPassword = tryPassword |> strip
        passwordChange = false
        if ! isempty(tryPassword)
            tryPassword = tryPassword |> encryptPassword
            if tryPassword != user["password"]
                return rj(Result(IdDict("uuid" => suuid), ERROR, "Wrong current password!"))
            end
            passwordChange = true
            @debug "Possibly password change"
        end

        if passwordChange
            userData["password"] = userData["password"] |> encryptPassword
        else
            userData["password"] = user["password"]
        end
        delete!(userData, "activePassword")
        if user["email"] != userData["email"]
            userData["emailChecked"] = false
        end

        # userData["uuid"]=uuid
        merge!(user, userData)  # we have to conserve, e.g., tags
        putData(userData)
        delete!(sessionCache, uuid)
        rj(Result(DataDict("uuid" => uuid), OK, "User profile has updated!"))
    end
end

route(API*"user/register", method=POST) do
    Logging.with_logger(debug_logger) do
        user=postpayload(:JSON_PAYLOAD)
        alias=get(user, "alias", nothing)
        name=get(user, "name", nothing)
        org=get(user, "org", "")
        password=get(user, "password", nothing)
        email=get(user, "email", nothing)
        @info "Try to add user" alias=alias email=email
        rc = addUser(alias, name, org, password, email)
        rj(rc)
    end
end

route(API*"user/authenticate", method=POST) do
    Logging.with_logger(debug_logger) do
        creds = postpayload(:JSON_PAYLOAD)
        alias = get(creds, "alias") do
            return rj(Result("", ERROR, "No user name supplied."))
        end

        password = get(creds, "password", "")
        password = password |> encryptPassword

        aliasDb = aliases()

        alias = strip(alias)
        key = "USER-" * alias
        if length(alias) == 0
            answer = DataDict()
            answer["alias"]=alias
            rc = Result(answer, ERROR, "Empty user name !")
        elseif !haskey(aliasDb, key)
            answer = DataDict()
            answer["alias"]=alias
            @debug "Authentication: User not found" alias=alias
            rc = Result(answer, ERROR, "User not found!")
        else
            uuid = aliasDb[key]
            ud = getUserData(uuid)
            if ud.level<ERROR
                @debug "Successful login" alias=alias
                rc = Result(uuid, OK, "Login into the account is successful!")
            else
                rc = ud
            end
        end
        rj(rc)
    end
end

route(API*"user/:uuid/projects", method=POST) do
    Logging.with_logger(debug_logger) do
        uuid=UUIDs.UUID(payload(:uuid))
        rc = getUserData(uuid)
        if rc.level >= ERROR
            return rj(rc)
        end

        user = rc.value;

        userProj = config.db.userProj
        if haskey(userProj, uuid)
            projs = userProj(uuid)
        else
            projs = DataDict("projects" => []::Vector{UUID})
        end

        demoFound = false
        answer :: Vector{DataDict}=[];

        function canonify(a::DataDict)::DataDict
            row = DataDict()
            if ! haskey(a, "model")
                row["model"] = config.defaultModelUUID
            else
                row["model"] = a["model"]
            end

            row["name"] = a["name"]
            row["model"] = a["model"]
            projUuid = row["uuid"] = a["uuid"]
            row["user"] = a["user"]
            uuuid = a["user"]
            tag = config.db.tag
            if haskey(tag, projUuid)
                tagD = tag[projUuid]
                projTags = tagD["tags"]
            else
                projTags = []::Vector{UUID}
            end
            row["tags"] = projTags
            row
        end

        projects = projs["projects"]

        for a in projects # must be done once
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

        # if !demoFound
        #     for a in Mongoc.find(coll, qdemo) # must be done once
        #         row = canonify(a)
        #         md = getModelData(UUID(row["model"]))
        #         if md.level >= ERROR
        #             return rj(md)
        #         end
        #         v = md.value
        #         row["modelData"] = v
        #         row["name"] = "(DEMO)"*row["name"]
        #         row["archived"] = false
        #         tags = row["tags"]
        #         push!(tags, "demo")
        #         row["tags"] = tags
        #         push!(answer, row)
        #     end
        # end

        rc = Result(answer, OK, "Project data, possibly empty.")
        rj(rc)
    end
end

route(API*"project/:uuid/dataframe", method=POST) do
    Logging.with_logger(debug_logger) do
        uuid=UUIDs.UUID(payload(:uuid))
        rc = getProjectData(uuid)
        rj(rc)
    end
end

route(API*"test", method=POST) do
    Logging.with_logger(debug_logger) do
        js = postpayload(:JSON_PAYLOAD)
        uuid=js["uuid"]
        @debug "Connection test" uuid=uuid
        rc=Result(uuid, OK, "Server functioning")
        rj(rc)
    end
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

function removeFigs!(prj::DataDict, updatePrj=true)
    Logging.with_logger(debug_logger) do

        @debug "Removing figures" prj=prj
        figures = prj["figures"]

        for (key, uuid) in figures
            deleteData(uuid)
        end

        delete!(prj, "figures")
        if updatePrj
            putData(prj)
        end
    end
end

function saveFig!(prj::DataDict, svg::String, key::String)
    Logging.with_logger(debug_logger) do
        m = prj
        obj = DataDict()
        obj["project"] = m["uuid"]
        obj["user"] = m["user"]
        figureuuid = uuid1()
        obj["uuid"] = figureuuid
        obj["figure"] = svg
        obj["key"] = key
        putData(obj)

        figures = get!(prj, "figures") do
            DataDict()
        end

        figures[key] = figureuuid
        prj["figures"] = figures
        # We do not store changes now....
    end
end

route(API*"project/:uuid/calculate", method=POST) do
    Logging.with_logger(debug_logger) do
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

        optimize =  m["optimize"]

        if typeof(optimize) == String
            optimize = optimize |> ep
        end

        @info "Optimize flag"  optimize=optimize

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
            dfnew = DataDict()
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

        @debug "Data frame" df=df

        gtRes = computeGeotherm(ini, df)

        figIO = IOBuffer()
        figChiIO = IOBuffer()
        figOptIO = IOBuffer()

        gtOptRes = plot(gtRes, "", figIO, figChiIO, figOptIO)

        fig = figIO |> take! |> String
        if optimize
            figChi = figChiIO |> take! |> String
            figOpt = figOptIO |> take! |> String
        end

        removeFigs!(prj, updatePrj=false)
        saveFig!(prj, fig, "geotherms")
        if optimize
            saveFig!(prj, figChi, "chisquare")
            saveFig!(prj, figOpt, "optimized")
        end
        # prj collects new figures, old removed, not updated
        putData(prj)  # Save changes now!

        @debug "Calculation finished"
        rc=Result("computed", OK, "Successfully computed!")
        rj(rc)
    end
end

route(API*"project/:uuid/graphs", method=POST) do
    Logging.with_logger(debug_logger) do
        uuid=UUIDs.UUID(payload(:uuid))

        pdr = getProjectData(uuid)
        if pdr.level >= ERROR
            return rj(pdr)
        end

        prj = pdr.value;

        figures = get(prj, "figures") do
            rc = Result(DataDict("uuid"=>uuid), ERROR, "not found")
            return rj(rc)
        end


        objs = []
        for (key, fuuid) in figures
            getData(fuuid) do fig
                fig["figure"] = fig["figure"] |> rmHeader
            end
            push!(objs, o)
            @debug "Added figure in the figure list" key=key uuid=fuuid
        end

        @debug "Returning figure list" len=length(objs)

        rc = Result(DataDict("figure"=>objs), OK, "found")
        rj(rc)
    end
end

route(API*"project/:uuid/figure/:key", method=GET) do
    Logging.with_logger(debug_logger) do
        uuid=UUIDs.UUID(payload(:uuid))
        key=payload(:key)

        function fnf()
            resp = GE.getresponse() # response("file not found", :text)
            GE.setbody!(resp, "file not found")
            GE.setstatus!(resp, 404)
            @debug "Figure not found" uuid=uuid key=key
            return resp
        end

        pdr = getProjectData(uuid)
        if pdr.level >= ERROR
            return fnf()
        end
        prj = pdr.value;

        figures = get(prj, "figures") do
            return fnf()
        end
        fig = get(figures, key) do
            return fnf()
        end

        figures = fr.value;

        @debug "Figure found" key=key

        resp = GE.getresponse()
        GE.setbody!(resp, obj["figure"])
        GE.setstatus!(resp, 200)
        GE.setheaders!(resp, Dict("Content-type" => "image/svg+xml"))
    end
end

function storeModelData(projectUuid::UUID, newData::DataDict)::Result
    Logging.with_logger(debug_logger) do
        @debug "storeModelData begin:" projectUuid newData=newData

        pdr = getProjectData(projectUuid)
        @debug "getProjectData" level=pdr.level
        if pdr.level >= ERROR
            return pdr
        end
        project = pdr.value;

        modeluuid = project["model"]

        modelr = getModelData(modeluuid)

        model = nothing
        if modelr.level < ERROR
            model = modelr.value
        end

        if modeluuid == (config.defaultModelUUID)
            modeluuid = uuid1()
            project["model"]=modeluuid
            putData(project)
            @debug "MODEL STORE: New record record by uuid" uuid=modelsuuid
        end

        newData["uuid"] = modeluuid
        newData["user"] = project["user"]
        putData(newData)

        @debug "MODEL STORE: Stored a record" newData=newData rc=rc uuid=modelsuuid
        return Result(newData, OK, "Model data updated successfully!")
    end
end

route(API*"project/:uuid/savemodel", method=POST) do
    Logging.with_logger(debug_logger) do
        uuid=UUIDs.UUID(payload(:uuid))
        js = postpayload(:JSON_PAYLOAD)
        rc = storeModelData(uuid, js)
        @debug "Updated model data" uuid=uuid
        rj(rc)
    end
end

route(API*"project/:uuid/setup", method=POST) do
    Logging.with_logger(debug_logger) do
        uuid=UUIDs.UUID(payload(:uuid))
        js = postpayload(:JSON_PAYLOAD)

        prjr = getProjectData(uuid)
        if prjr.level >= ERROR
            return rj(prjr)
        end

        prj = prjr.value

        colNames = js["colNames"]
        colRoles = js["colRoles"]

        trans = DataDict()
        for (k,v) in zip(colNames, colRoles)
            if (k!=v)
                trans[k] = v
            end
        end

        prj["rename"] = trans
        putData(prj)

        rc = Result(DataDict("uuid"=>uuid), OK, "Setup accepted")
        rj(rc)
    end
end

route(API*"project/:uuid/model", method=POST) do
    Logging.with_logger(debug_logger) do
        uuid=UUIDs.UUID(payload(:uuid))
        prj = getProjectData(uuid)

        if prj.level >= ERROR
            return rj(prj)
        end
        rc = getModelData(prj.value["model"])

        rj(rc)
    end
end

route(API*"projects/changetag/:op/arg/:arg", method=POST) do
    Logging.with_logger(debug_logger) do
        op=payload(:op)
        arg=payload(:arg)
        js = postpayload(:JSON_PAYLOAD)
        projects = js["projects"]
        updated = []
        @info "UPDATE request for " projects=projects op=op  tag=arg

        for suuid in projects
            uuid = suuid |> UUID

            prjr = getProjectData(uuid)
            if prjr.level >= ERROR
                return rj(prj)
            end
            prj = prjr.value
            useruuid = prj["user"]
            userr = getUserData(uuid)

            if userr.level < ERROR
                return rj(userr)
            end

            user = userr.value

            tagDict = get(user, "tags") do
                if op == "delete"
                    continue
                else
                    DataDict("projects"=>DataDict())
                end
            end

            tags = tagDict["projects"]

            # TODO

            if tagsr.level == NOTFOUND
                tags = DataDict()
                tags["uuid"] = uuid
                tags["user"] = useruuid
            else
                tags = tagsr.value
            end

            tag = config.db.tag
            if op == "add"
                if tagsr.level == NOTFOUND
                    tags["tags"] = [arg]
                else
                    ts = tags["tags"]
                    if ! (arg in ts)
                        push!(ts, arg)
                    end
                    tags["tags"]=ts
                end
            elseif op=="delete"
                ts = tags["tags"]
                filter!( t-> t!=arg, ts)
                tags["tags"] = ts
            else
                return rj(Result(op, ERROR, "Unknown operation: " * op))
            end
            tag[uuid]=tags
            push!(updated, uuid)
        end
        rj(Result(DataDict("tags" => updated),OK,"Projects tags have updated"))
    end
end

function main()
    dbs = connectDb()
    # test()
    println("Routes -----")
    for r in routes()
        @info "Route" r=r
    end
    up(8000, async=false)
end

# function test()
#     println("CFG:", config.client, "\n")
#     # u = addUser("eugeneai","Evgeny Cherkashin", "ISDCT SB RAS", "passW0rd", "eugeneai@irnok.net")
#     println(u)
#     println(getUserData(u.value))
# end

if PROGRAM_FILE != ""
    main()
end
