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
    new_person::Function
end

function Jus.handle(value, cmd::VarCommand{:metadata, (:app,)})
    println("METADATA: ", cmd)
    PASS
end

function handle(app::PersonApp, cmd::VarCommand{:set, (:namefield,)})
    if haskey(app.people, app.namefield)
        set_metadata(cmd, :new_person, :note, "There is already a person named $(app.namefield)")
    elseif app.namefield == ""
        set_metadata(cmd, :new_person, :note, "A new person needs a name")
    elseif app.addressfield == ""
        set_metadata(cmd, :new_person, :note, "A new person needs an address")
    else
        return PASS
    end
    set_metadata(cmd, :new_person, :enabled, false)
    FAIL
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
