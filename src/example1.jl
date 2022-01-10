using .Jus

import Base.@kwdef

@kwdef mutable struct Person
    name::AbstractString
    id::Number
    address::AbstractString
    friends::Dict{AbstractString, Person} = Dict()
end

@kwdef mutable struct PersonApp
    people::Dict{AbstractString, Person} = Dict()
    sorted_people::Vector{Person} = []
    namefield = ""
    addressfield = ""
    selected_person::Number = 0
    next_id::Number = 1
    new_person_tooltip = "A new person needs a name"
    new_person_enabled = false
    editing_enabled = false
end

people(app::PersonApp) = app.sorted_people

sort_people(app::PersonApp) = app.sorted_people = sort([values(app.people)...], by = p-> lowercase(p.name))

function Jus.handle(app::PersonApp, cmd::VarCommand{:create})
    println("@@@ EXAMPLE PERSON APP CREATED")
    ## initialize app here
end

function selected_person(app::PersonApp)
    app.sorted_people[findfirst(p-> p.id == app.selected_person, app.sorted_people)]
end

function person_index(app::PersonApp)
    i = findfirst(p-> app.selected_person == p.id, app.sorted_people)
    return i === nothing ? -1 : i - 1
end
person_index(app::PersonApp, new_index::AbstractString) = person_index(app, parse(Number, new_index))
function person_index(cmd::VarCommand, app::PersonApp, new_index::Number)
    new_index += 1
    if 0 < new_index <= length(app.sorted_people)
        show_person(app, new_index)
    else
        clear_person(app)
    end
end

function clear_person(app::PersonApp)
    app.selected_person = 0
    app.namefield = ""
    app.addressfield = ""
    check_fields(app)
end

show_person(app::PersonApp, index::Number) = show_person(app, app.sorted_people[index])
function show_person(app::PersonApp, p::Person)
    app.selected_person = p.id
    app.namefield = p.name
    app.addressfield = p.address
    check_fields(app)
end

addressfield(app::PersonApp) = app.addressfield
function addressfield(cmd::VarCommand, app::PersonApp, value)
    app.addressfield = value
    check_fields(app)
end

namefield(app::PersonApp) = app.namefield
function namefield(cmd::VarCommand, app::PersonApp, value)
    app.namefield = value
    check_fields(app)
end

function check_fields(app::PersonApp)
    app.new_person_enabled = false
    app.editing_enabled = app.selected_person != 0
    app.new_person_tooltip = ""
    if app.namefield == ""
        app.new_person_tooltip = "A new person needs a name"
    elseif app.addressfield == ""
        app.new_person_tooltip = "A new person needs an address"
    elseif haskey(app.people, app.namefield)
        app.new_person_tooltip = "There is already a person named $(app.namefield)"
    else
        app.new_person_enabled = true
    end
end

function Jus.handle_child(parent::Var, parent_value, app::PersonApp, cmd::VarCommand{:set})
    println("SETTING CHILD $(parent_value).$(cmd.var.name), META = $(cmd.var.metadata)")
end

function new_person(app::PersonApp)
    p = Person(
        id = app.next_id,
        name = app.namefield,
        address = app.addressfield)
    app.next_id += 1
    app.people[app.namefield] = p
    sort_people(app)
    show_person(app, p)
    println("Created a person")
end

function change_person(app::PersonApp)
    p = selected_person(app)
    p.name = app.namefield
    p.address = app.addressfield
    sort_people(app)
end

function delete_person(app::PersonApp)
    println("Delete person")
end
