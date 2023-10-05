import Mongoc
import SHA
import UUIDs
using Genie, Genie.Requests
# import GenieSession
import Genie.Cookies as GC
# import GenieSession as GS
using Genie.Renderer.Json
import Genie.Requests as GR
import Genie.Responses as GE
using SMTPClient
using Base64
using Dates
using Markdown

MB=Mongoc.BSON

mutable struct Config
    salt::String
    systemUUID::Any
    client::Any
    dbName::String
    db::Any
    noreply::String
    server::String
end

config::Config = Config("salt9078563412",
                        UUIDs.UUID("7a2b81c9-f1fa-41de-880d-9635f4741511"),
                        0,
                        "geotherm",
                        0,
                        "UVh5Qj1lPiUyYkpyNmhUJQo=" |> base64decode |> String |> strip,
                        "https://gtherm.ru"
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
    FATAL = 20
end

struct Result
    value::Any
    level::ResultLevel
    description::String
end


sessionCache = IdDict{String, Result}()

function cache!(f::Function, uuid::UUIDs.UUID)::Result
    suuid = uuid |> string
    obj = get(sessionCache, suuid, nothing)
    if isnothing(obj)
        result = f()
        if result.level < ERROR
            sessionCache[suuid] = result
        end
        return result
    else
        println("Getting from the casche")
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


function getData(okf::Function, uuid::UUIDs.UUID, collection::String)::Result
    obj = Mongoc.BSON()
    obj["uuid"] = string(uuid)
    db = config.client[config.dbName]
    coll = db[collection]
    obj = Mongoc.find_one(coll, obj)
    if isnothing(obj)
        answer = MB()
        answer["uuid"]=uuid
        return Result(answer, ERROR, "not found")
    else
        okf(obj)
        return Result(obj, OK, "found")
    end
end

function getUserData(uuid::UUIDs.UUID)::Result
    cache!(uuid) do
        println("Getting from Mongo")
        getData(uuid, "users") do v
            v["password"]="******"
        end
    end
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
        user["password"] = SHA.sha256(config.salt * password) |> bytes2hex
        user["email"] = email
        user["emailChecked"] = false
        uuid = UUIDs.uuid5(config.systemUUID, "geotherm-user")
        suuid = string(uuid)
        user["uuid"] = suuid
        push!(coll, user)
        sendEmailApproval(user)
        rc = Result(uuid, OK, "user added")
        sessionCache[suuid] = rc
        return rc
    else
        println(prev["uuid"])
        return Result(
            prev["uuid"] |> UUIDs.UUID ,
            ERROR, "user exists")
    end
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
    # if l == OK
    #     d["level"] = "OK"
    # elseif l == ERROR
    #     d["level"] = "ERROR"
    # elseif l == INFO
    #     d["level"] = "INFO"
    # elseif l == FATAL
    #     d["level"] = "FATAL"
    # elseif l == DEBUG
    #     d["level"] = "DEBUG"
    # elseif l == CACHED
    #     d["level"] = "OK"
    # end
    println(json(d), l)
    json(d)
end

API="/api/1.0/"

route(API*"user/:uuid/data", method=POST) do
    uuid=UUIDs.UUID(payload(:uuid))
    # req=GR.request()
    # res=GE.getresponse()
    # cookie = GC.get(req,"test")
    # println("Req:", req)
    # println("Cookie:", cookie)
    # GC.set!(res,:userSession,string(uuid))
    # println("Resp:", res)
    # println(req,res)
    # sess=GS.start(req)
    rc = getUserData(uuid)
    rj(rc)
end

function main()
    mongoClient = connectDb()
    # test()
    print(routes())
    up(8000,
       async=false)
end

if PROGRAM_FILE != ""
    main()
end
