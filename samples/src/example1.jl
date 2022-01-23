import Base.@kwdef

@kwdef mutable struct Person
    name::AbstractString
    id::Number
    address::AbstractString
    friends::Dict{AbstractString, Person} = Dict()
end

@kwdef mutable struct PersonApp
    people::Vector{Person} = Person[]
    namefield = ""
    addressfield = ""
    selected_person::Union{Nothing, Person} = nothing
    next_id::Number = 1
    new_person_tooltip = "A new person needs a name"
    new_person_enabled = false
    editing_enabled = false
end

sort_people(app::PersonApp) = app.people = sort!(app.people, by = p-> lowercase(p.name))

person_index(app::PersonApp) = something(findfirst(x-> x == app.selected_person, app.people), 0)
function person_index(app::PersonApp, index::Number)
    println("SELECTING PERSON $index")
    show_person(app, 1 <= index <= length(app.people) ? app.people[index] : nothing)
end

function clear_person(app::PersonApp)
    app.selected_person = nothing
    app.namefield = ""
    app.addressfield = ""
    check_fields(app)
end

show_person(app::PersonApp, index::Number) = show_person(app, app.sorted_people[index])
function show_person(app::PersonApp, p::Person)
    app.selected_person = p
    app.namefield = something(p.name, "")
    app.addressfield = something(p.address, "")
    check_fields(app)
    println("###\n### SHOWING $(p === nothing ? "nothing" : p.name * ", ID: " * string(p.id))")
    println("###\n### INDEX: $(person_index(app))")
end

addressfield(app::PersonApp) = app.addressfield
function addressfield(app::PersonApp, value)
    app.addressfield = value
    check_fields(app)
end

namefield(app::PersonApp) = app.namefield
function namefield(app::PersonApp, value)
    app.namefield = value
    check_fields(app)
end

function check_fields(app::PersonApp)
    println("CHECKING FIELDS OF $app")
    app.new_person_enabled = false
    app.editing_enabled = app.selected_person !== nothing
    app.new_person_tooltip = ""
    if app.namefield == ""
        app.new_person_tooltip = "A new person needs a name"
    elseif app.addressfield == ""
        app.new_person_tooltip = "A new person needs an address"
    elseif findfirst(p-> p.name == app.namefield, app.people) !== nothing
        app.new_person_tooltip = "There is already a person named $(app.namefield)"
    else
        app.new_person_enabled = true
    end
end

function new_person(app::PersonApp)
    p = Person(
        id = app.next_id,
        name = app.namefield,
        address = app.addressfield)
    app.next_id += 1
    push!(app.people, p)
    sort_people(app)
    show_person(app, p)
    println("Created a person")
end

function change_person(app::PersonApp)
    p = app.selected_person
    p.name = app.namefield
    p.address = app.addressfield
    sort_people(app)
end

function delete_person(app::PersonApp, p::Person)
    println("###\n### DELETE $(p)")
    p === nothing && return
    splice!(app.people, person_index(app))
end
