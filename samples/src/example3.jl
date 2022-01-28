import Base.@kwdef

@kwdef mutable struct Person
    name::String
    address::String
end

const people = Person[]

Jus.present(people;
            Person = (;
                      # specify what to gen
            ))
