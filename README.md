# Jus

Jus is a presentation engine for Julia to support "no-code
GUIs". Its paradigm-neutral protocol allows you to frontend it with
HTML, console UIs, or even a 3D engine like Minecraft or Unreal.

# To run the example:

```sh
cd samples/src
julia --project=. -i example2.jl
```

# The HTML frontend

HTML is currently the only implmented Jus frontend but others are quite possible (see below).

For the ultimate no-code experience, Jus can mangage your entire
front-end, inferring GUIs for your data as-needed.

A frontend can be autogenerated (for the ultimate no-code experience)
or some or all of it can be entirely custom made (in HTML and CSS --
no JS required).

# Other Frontends

Frontending Jus requires an agent for that frontend. The 

- Terminal User Interface (using somethign like [this](https://github.com/kdheepak/TerminalUserInterfaces.jl)).
- Emacs
- Unreal Engine
- Network monitoring (like SNMP)
- Desktop (Gtk, Tk, FOX, etc.)
- ...
