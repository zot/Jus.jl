using Mustache

# viewdef generation

get_path(cmd::VarCommand, var::Var) = get_path(VarCommand{:get, ()}(cmd; var))

@kwdef mutable struct ListEditor
    #var::Var
    id = 1
    name = ""
    list
    selection = nothing
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
function selection_index(ed::ListEditor, index::Number)
    println("SELECTING $index")
    show_person(app, 1 <= index <= length(app.people) ? app.people[index] : nothing)
end

show(cmd::VarCommand, ed::ListEditor) = foreach(e-> show(cmd, e), ed.fields)

function generate_viewdef(cmd::VarCommand)
    var = cmd.var
    (var.internal_value === nothing || !haskey(var.metadata, :genview)) && return
    println("GENERATING VIEWDEF:\n", generate_v(typeof(var.internal_value), var.metadata[:genview]))
    set_metadata(cmd, :viewdef, generate_v(typeof(var.internal_value), var.metadata[:genview]))
end

"""
    generate_v(item, namespace)

generate a viewdef for item
namespace indicates what type of view to generate (default is editor, could
be list, link, etc.)
"""
generate_v(ed::ListEditor, _ns) = Mustache.render(GEN_LIST, tmpldata(ed))
function generate_v(::Type{T}, _ns) where T
    !isstructtype(T) && return GEN_SHOW
    render(GEN_FIELDS, (; fields = [generate_field(T, field, i == 1)
                                     for (i, field) in enumerate(fieldnames(T))]))
end

generate_field(owner::Type, field::AbstractString, first) = generate_field(owner, Symbol(field), first)

generate_field(owner::Type, field::Symbol, first) =
    generate_field(owner, fieldtype(owner, field), field, first)

generate_field(owner::Type, ::Type{<: Vector}, field, first) =
    render(GEN_LIST_FIELD, (; gen_introspect(owner, field)..., name = pretty(field), first))

generate_field(owner::Type, ::Type{<: Union{AbstractString, Number}}, field, first) =
    render(GEN_FIELD, (; gen_introspect(owner, field)..., name = pretty(field), first))

#generate_field(::Type{T <: Bool}, field, first) =
#    render(GEN_CHECK, (; field, name = pretty(field), first))

#generate_field(::Type{T <: Enum}, field, first) =
#    render(GEN_RADIO, (; field, name = pretty(field), first))

function gen_introspect(T::Type, field)
    try
        println("CHECKING METHODS FOR $(Symbol(field))")
        func = parentmodule(T).eval(Symbol(field))
        println("FUNC: $func")
        (hasmethod(func, (T,)) ||
            hasmethod(func, (VarCommand, T))) && return (; field = "$field()")
    catch err end
    (; field)
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
    str[1] * replace(str[2:end], "_"=>" ", r"(\p{Ll})(\p{Lu}+)"=>(l, u)-> "$l $(lowercase.(split(u, "")))")
end

function edit_list_field()
end

const GEN_FIELDS = """
<div>{{#fields}}
  {{{.}}}
{{/fields}}</div>
"""

const GEN_SHOW = """
<div data-text='repr()'></div>
"""

const GEN_FIELD = """
<div class='flex flex-col w-80'>
  <fast-text-field{{#first}}
    autofocus{{/first}}
    appearance='filled'
    data-value='{{field}}'>{{name}}</fast-text-field>
</div>
"""

const GEN_LIST_FIELD = """
<div class='flex flex-col w-80'>
  <fast-button data-click='{{field}} edit_list_field()'>{{name}}</div>
</div>
"""

const GEN_LIST = """
<div class='flex flex-row items-center w-100'>
  <div class="grow relative px-6 pt-10 pb-8 bg-slate-500 shadow-xl ring-1 ring-gray-900/5 sm:max-w-lg sm:mx-auto sm:rounded-lg sm:px-10 self-stretch w-80">
    <div class="max-w-md mx-auto">
      <label id='list-{{id}}' class='font-bold'>{{label}}</label>
      <br/>
      <div data-tooltip='new_person_tooltip' style='display: inline-block'>
        <fast-button
          appearance='primary'
          data-click='create_item()'
          data-enabled='create_item_enabled'>Add</fast-button>
      </div>
      <div style='display: inline-block'>
        <fast-button appearance='primary' data-click='change_person()' data-enabled='editing_enabled'>Change</fast-button>
      </div>
      <div style='display: inline-block'>
        <fast-button appearance='primary' data-click='delete_person()' data-enabled='editing_enabled'>Delete</fast-button>
      </div>
      <fast-listbox
        data-attr-aria-labeledby='list-{{id}}'
        data-list='list'
        data-on-selected='selection_index():defaults,get=selectedIndex,set=selectedIndex,adjustIndex'
        data-namespace='ex2-list'></fast-listbox>
    </div>
  </div>
  <div class='grow self-stretch' data-class-toggle='hide_editor:class=hidden'>
    {{fields}}
  </div>
</div>
"""
