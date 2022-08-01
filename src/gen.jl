# viewdef generation

using Mustache

const VIEW_DIR = "viewdefs"

const GEN_FIELDS = """
<div>{{#fields}}
  {{{.}}}
{{/fields}}</div>
"""

const GEN_TUPLE = """
<div data-var='{{field}}'>{{#fields}}
  {{{.}}}
{{/fields}}</div>
"""

const GEN_SHOW = """
<div data-text='repr()'></div>
"""

get_path(cmd::VarCommand, var::Var) = get_path(VarCommand{:get, ()}(cmd; var))

@kwdef mutable struct Field{ownertype, ns, field, field_type}
    first::Bool = false
    getter::Union{Function,Nothing} = nothing
    setter::Union{Function,Nothing} = nothing
    settervar::Bool = false # whether setter takes a var argument
    gettervar::Bool = false # whether getter takes a var argument
    readable::Bool = getter !== nothing || setter === nothing
    writable::Bool = struct_is_mutable(ownertype) && (setter !== nothing || getter === nothing)
end

ownertype(::Field{O}) where {O} = O
ns(::Field{O, namespace}) where {O, namespace} = namespace
field(::Field{O, ns, fieldname}) where {O, ns, fieldname} = fieldname
field_type(::Field{O, ns, field, jus_field_type}) where {O, ns, field, jus_field_type} = jus_field_type

function struct_is_mutable(t::Type)
    VERSION >= v"1.7" && return ismutable(t)
    while t isa UnionAll
        t = t.body
    end
    t.mutable
end

@kwdef mutable struct ListEditor{Namespace}
    id = 1
    name = ""
    list
    selection = nothing
    label = "Items"
    #add_enabled::Function = (; fields...)-> true
    #check_enabled::Function
    #add_tooltip::AbstractString = ""
end

function ListEditor(con, list::T; args...) where T
    if !haskey(args, :id)
        args = (; args..., id = "list-$(con === nothing ? 1 : con.sequence += 1)")
    end
    ListEditor(; list, args...)
end

# used for creation
list_type(::T) where T = base_list_type(T)
list_type(::Type{T}) where T = base_list_type(T)
list_type(ed::ListEditor) = base_list_type(typeof(ed.list))

function base_list_type(::Type{T}) where T
    et = eltype(T)
    et == T ? nothing : et
end

#add_item(ed::ListEditor) =

add_enabled(ed::ListEditor) = list_type(ed) !== nothing && ed.add_enabled()

edit_enabled(ed::ListEditor) = ed.selection !== nothing

selection_index(ed::ListEditor) = something(findfirst(x-> x == ed.selection, ed.list), 0)
selection_index(ed::ListEditor, index::Number) =
    selection(ed, get(ed.list, index, nothing))

selection(ed::ListEditor, item) = ed.selection = item

show(cmd::VarCommand, ed::ListEditor) = foreach(e-> show(cmd, e), ed.fields)

function generate_viewdef(cmd::VarCommand)
    var = cmd.var
    (var.internal_value === nothing || !haskey(var.metadata, :genview)) && return
    namespace = var.metadata[:genview]
    viewdef = generate_viewdef(cmd, typeof(var.internal_value), Symbol(namespace))
    #println("GENERATED VIEWDEF:\n", viewdef)
    set_metadata(cmd, :viewdef, viewdef)
    if cmd.config.output_dir != ""
        filebase = "$(typename(cmd.var.internal_value))"
        namespace != "" && (filebase *= "-$namespace")
       open(joinpath(cmd.config.output_dir, "$filebase.html"); write=true) do io write(io,  viewdef) end
    end
end

"""
    generate_viewdef(item, namespace)

generate a viewdef for item
namespace indicates what type of view to generate (default is editor, could
be list, link, etc.)
"""
function generate_viewdef(cmd::VarCommand, ::Type{T}, ns::Symbol = Symbol("")) where T
    !isstructtype(T) && return GEN_SHOW
    render(GEN_FIELDS, (; fields = [gen_field(cmd, field)
                                    for field in getfields(T, ns)]))
end

#fields
#
#function fieldsfor(T::Type)
#    m = parentmodule(T)
#    (func in (getfield(m, name) for name in names(m))
#        if func isa Function && isgetter
#        end

typefields = Dict{Type,Vector{Field}}()

getfields(T::Type, ns::Astr) = getfields(T, Symbol(ns))

function getfields(T::Type, ns::Symbol)
    global typefields
    haskey(typefields, T) && return typefields[T]
    fields = Dict{Symbol, Field}()
    field = nothing
    first = true
    result = Field[]
    for name in fieldnames(T)
        fields[name] = Field{T, ns, name, fieldtype(T, name)}(; first)
        first = false
        push!(result, fields[name])
    end
    m = parentmodule(T)
    for name in names(m)
        item = getfield(m, name)
        !(item isa Function) && continue
        if startswith(string(name), "get_")
            for sig in [(T, Var), (T)]
                meths = methods(item, sig)
                length(meths) != 1 && continue
                rets = Base.return_types(item, sig)
                length(rets) != 1 && continue
                haskey(fields, name) && fields[name].setter !== nothing &&
                    field_type(fields[name]) != rets[1] &&
                    error("Getter $name type $(rets[1]) is different from setter type $(field_type(fields[name]))")
                field = Field{T, ns, name, rets[1]}(
                    ;
                    first = get(fields, name, false),
                    getter = item,
                    gettervar = length(sig) == 2,
                    readable = true,
                )
                push!(result, field)
            end
        end
        if startswith(string(name), "set_")
            !struct_is_mutable(T) && continue
            for sig in [(T, Any, Var), (T, Any)]
                meths = methods(item, sig)
                length(meths) != 1 && continue
                meth = first(meths)
                type = (meth.sig isa UnionAll ? meth.sig.body : meth.sig).types[2]
                type isa TypeVar && continue
                haskey(fields, name) && fields[name].getter !== nothing &&
                    field_type(fields[name]) != type &&
                    error("Getter $name type $type is different from setter type $(field_type(fields[name]))")
                field = Field{T, ns, name, type}(
                    ;
                    first = get(fields, name, false),
                    setter = item,
                    settervar = length(sig) == 3,
                    writable = true,
                )
                push!(result, field)
            end
        end
    end
    typefields[T] = result
end

jus_fieldtype(T::Type, fieldname) = fieldtype(T, fieldname)

function template(cmd::VarCommand, template, namespace)
    k = (Symbol(template), Symbol(namespace))
    if !haskey(cmd.config.templates, k)
        name = string(namespace) == "" ? template : "$template-$namespace"
        cmd.config.templates[k] = read(joinpath(cmd.config.templates_dir, "$name.html"), String)
    end
    cmd.config.templates[k]
end

function all_presentable(t::Type)
####### HERE    
end

#generate_viewdef(cmd::VarCommand, ed::ListEditor; ns) =
#    Mustache.render(template(cmd, :list, ns), tmpldata(ed))

"""
    gen_field(cmd, owner_type, Field{owner, namespace, field, field_type, first})

Generate a field; override this to customize a particular field or type of field.

Generated field types: Vector, Enum, AbstractString, Number
"""
# radio button
function gen_field(cmd::VarCommand, fld::Field{owner, ns, field, field_type}) where {
    owner, ns, field, field_type <: Enum
}
    #println("FIELD TYPE: $(field_type)")
    render(template(cmd, :radio, ns),
           (;
            introspect(fld)...,
            type = typename(field_type),
            id = cmd.connection.sequence += 1,
            values = [(;name = pretty(e), value = string(e)) for e in instances(field_type)]))
end

# text field
gen_field(cmd::VarCommand, fld::Field{owner, ns, field, field_type}) where {
    owner, ns, field, field_type <: Union{AbstractString, Number}
} =
    render(template(cmd, :textfield, ns), introspect(fld))

# checkbox
gen_field(cmd::VarCommand, fld::Field{owner, ns, field, field_type}) where {
    owner, ns, field, field_type <: Bool
} =
    render(template(cmd, :checkbox, ns),
           (;
            introspect(fld)...,
            type = typename(field_type)))

#gen_field(cmd::VarCommand, fld::Field{owner, ns, field, field_type}) where {
#    owner, ns, field, field_type <: Tuple
#} =
#    render(GEN_FIELDS,
#           field,
#           fields


#list
#gen_field(cmd::VarCommand, fld::Field{owner, ns, field, field_type}) where {
#    ns, owner, field, field_type <: Vector
#} =
#    render(template(cmd, :list_field, ns),
#           (; gen_introspect(fld)...,
#            name = pretty(field),
#            first))

"""
    introspect(fld::Type{Field})

computes PATH, PRETTY_NAME, and FIRST for fld
returns (; field = PATH, name = PRETTY_NAME, first = FIRST)
"""
function introspect(f::Field{owner, _ns, field, ft}) where {owner, _ns, field, ft}
    name = pretty(field)
    try
        #println("CHECKING METHODS FOR $field")
        func = parentmodule(owner).eval(field)
        #println("FUNC: $func$((hasmethod(func, (owner,)) ||
        #    hasmethod(func, (VarCommand, owner))) ? " [getter]" : "")")
        (hasmethod(func, (owner,)) ||
            hasmethod(func, (VarCommand, owner))) && return (; field = "$field()", name, f.first)
    catch
    end
    #println("INTROSPECT $f: ", (; field, name, f.first))
    (; field, name, f.first)
end

tmpldata(ed::ListEditor) = to_dict((;
    id = ed.id,
    name = ed.name,
    fields = [(;
               first = i == 1,
               name = pretty(field),
               field = field,
               ) for (i, field) in enumerate(fieldnames(list_type(ed)))]))

render(tmpl, value) = Mustache.render(tmpl, to_dicts(value))

to_dicts(val) = val
to_dicts(val::Array) = map(to_dicts, val)
to_dicts(tup::NamedTuple) = Dict((string(k)=>to_dicts(v) for (k, v) in pairs(tup))...)

# capitalize first letter, use spaces instead of underbars and camelcase transitions
function pretty(val)
    str = string(val)
    str[1] * replace(str[2:end],
                     r"_|(\p{Ll})(\p{Lu}+)"=>(s)->
                         s == "_" ? " " :
                         "$(s[1]) $(lowercase.(split(s[2:end], "")))")
end

function edit_list_field()
end
