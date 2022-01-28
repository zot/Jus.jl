using Jus

import Base.@kwdef

@kwdef mutable struct Person
    name::String
    address::String
end

const people = Person[]

function name(p::Person)
    println("GETTING NAME OF $p")
    p.name
end

function name(p::Person, value)
    println("SETTING NAME OF $p TO $value")
    p.name = string(value)
end

Jus.start(Person(name="Fred", address="123"))
