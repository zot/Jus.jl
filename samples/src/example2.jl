using Jus

import Base.@kwdef

@kwdef mutable struct Person
    name::String
    address::String
end

const people = Person[]

Jus.start(Person(name="Fred", address="123"))
