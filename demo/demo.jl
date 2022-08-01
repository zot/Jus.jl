using Jus, Jus.Shell
using Base: @kwdef

@enum Color red blue yellow green

@kwdef mutable struct Person
    name::String = ""
    address::String = ""
    favorite_color::Color = red
    working::Bool = false
end

name(p::Person) = p.name
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

working(p::Person) = p.working
function working(p::Person, value)
    println("SETTING WORKING OF $p TO $value")
    p.working = value
end

p = Person(name="Fred", address="Fred's address")
println("Person p: $p")
Shell.inspect(p)