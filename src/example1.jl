using .Jus

import Base.@kwdef

@kwdef mutable struct Person
    name::AbstractString
    address::AbstractString
    friends::Dict{AbstractString, Person} = Dict()
end

@kwdef mutable struct PersonApp
    people = Dict()
    namefield = ""
    addressfield = ""
end

function Jus.handle(app::PersonApp, cmd::VarCommand{:create})
    println("@@@ EXAMPLE PERSON APP CREATED")
    ## initialize app here
end

namefield(app::PersonApp) = app.namefield
function namefield(cmd::VarCommand, app::PersonApp, value)
    #println("PERSON APP HANDLE: ", cmd)
    #println("PERSON APP cmd var = $(cmd.var)")
    #println("PERSON APP cmd parent = $(Jus.parent(cmd).var)")
    p = Jus.parent(cmd)
    if haskey(app.people, app.namefield)
        set_metadata(p, :new_person, :note, "There is already a person named $(app.namefield)")
    elseif value == ""
        set_metadata(p, :new_person, :note, "A new person needs a name")
    elseif app.addressfield == ""
        set_metadata(p, :new_person, :note, "A new person needs an address")
    else
        return
    end
    set_metadata(p, :new_person, :enabled, "false")
    cmd.cancel = true
end

function Jus.handle_child(parent::Var, parent_value, app::PersonApp, cmd::VarCommand{:set})
    println("SETTING CHILD $(parent_value).$(cmd.var.name), META = $(cmd.var.metadata)")
end

function new_person(app::PersonApp)
    app.people[app.namefield] = Person(name = app.namefield, address = app.addressfield)
    app.namefield = ""
    app.addressfield = ""
    app.new_person.enabled = false
    app.new_person.note = ""
end

function person_app()
    app = PersonApp()
    (; app, new_person = Action(()-> new_person(app)))
end

println("person_app: ", person_app)
