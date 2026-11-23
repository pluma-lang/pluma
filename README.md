# Pluma

Pluma programs end in `.pluma`.

```
# this is a comment
let x = 42
```

## let

`let name = value` creates a variable.
also `let name be value` creates a variable.

```
let age = 21
age = age + 1
```

## print

```
print "hello"
print 'how are you?'
print 1 + 2
```

## input

```
let name = input "Your name? "
print "Hi " + name
```

## Operators

| Operators | Meaning |
|---|---|
| `+` `-` `*` `/` `//` `%` `^` | add, subtract, multiply, divide, integer division, modulo, power |
| `>` `<` `>=` `<=` `==` `!=` | comparisons |
| `and` `or` `not` | logic |
| `-x` | negative number |

## if / else

```
if age >= 18 then
    print "adult"
else
    print "minor"
```

## while

```
let i = 0
while i < 3 then
    print i
    i = i + 1
```

## foreach

```
foreach n in numbers then
    print n
```

### range
```
foreach n in range from 0 to 10 then
    print n
```

## Break/Continue

`continue` skips the rest of the loop code and continues to the next iteration
`break` interrupts a loop entirely

## function and return

```
function add with a, b
    return a + b

print add with 2, 3
```

## Lists

`list with a, b, c` creates a list. `list with null` creates an empty list.

### Slices

```
let numbers = list with 0,1,2,3,4,5

print slice numbers from 1 to 4
```

### Appending
```
let l = list with nothing

append 10 to l

print l
```

### Matrices
```
let matrix = list with
    (list with 1, 2, 3),
    (list with 4, 5, 6)
```

## Maps

```
let julia = map with
    "name": "Julia"
    "age": 21

let point = map with "x": 1, "y": 2
```

## from

`index from collection` reads one element.

Reading a key that does not exist, or a position outside the list, is an error.

```
print 0 from numbers
print "name" from julia
print 1 from (2 from matrix)
```

## length

`length value` gives the number of elements in a list, entries in a map, or characters in a string.

```
print length "hello"
print length julia
```

## copy
`copy identifier` copies the contents of a map or list instead of a reference

```
let Person = map with "name": "Julia", "age": 21
let addressing = Person # This variable is pointing to Person
let copying = copy Person # This variable is copying the contents of Person
```
