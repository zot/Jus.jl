# Jus
Active varibles that bind to vanilla Julia code -- no need to implement the observer pattern

Parts

- [X] setting variables
- [X] observing variables
- [X] routing commands
  - [X] parents can alter commands
  - [X] current values can alter commands
- [ ] refreshing
  - [ ] parents can transform variable values
- [ ] metadata
  - [ ] path
    - composed of fields and functions: "a b() c d"
    - each item is called with the previous one
    - functions are allowed to contain dots (for module qualifiers)
    - for a setter, the final item is
      - assigned to the value if it is a field
      - called with (data, value) if it is a setter
  - [ ] action
    - implies access = 'w'
    - only affects paths
    - last element must be a function
    - function will be called with (data) (not (data, value))
