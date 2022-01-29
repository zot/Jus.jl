using Jus

import Base.@kwdef

@enum Color red blue yellow green

@kwdef mutable struct Person
    name::String
    address::String
    favorite_color::Color
end

const people = Person[]

function name(p::Person)
    println("GETTING NAME OF $p")
    p.name
end

function name(p::Person, value)
    println("SETTING NAME OF $p TO $value")
    p.name = string(value)
    p.address = "$(p.name)'s address"
end

favorite_color(p::Person) = p.favorite_color
function favorite_color(p::Person, color)
    println("SETTING FAVORITE COLOR OF $p TO $color")
    p.favorite_color = color
end

Jus.start(
    Person(
        name="Fred",
        address="123",
        favorite_color=blue); create_output="/tmp/gen")
