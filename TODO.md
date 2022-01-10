# Jus
Active varibles that bind to vanilla Julia code -- no need to implement the observer pattern

- [ ] floating editor mode (1 or 2 additional views for PersonApp)
- [X] use [material web components for widgets](https://github.com/material-components/material-web)
- [ ] naked objects for types that have no vewidef

Parts

- [X] setting variables
- [X] observing variables
- [X] routing commands
  - [X] parents can alter commands
  - [X] current values can alter commands
- [X] refreshing
  - [ ] parents can transform variable values (needs testing)
- [X] metadata
  - [X] path
    - [X] composed of fields and functions: "a b() c d"
    - [X] each item is called with the previous one
    - functions are allowed to contain dots (for module qualifiers)
    - [X] for a setter, the final item is
      - [X] assigned to the value if it is a symbol
      - [X] called with (data, value) if it is a function
    - [X] actions
      - access=action
      - like a setter but called with no args
      - last element must be a function
      - function will be called with (data), like a getter (not (data, value))
