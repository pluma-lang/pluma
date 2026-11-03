# Pluma

Pluma programs end in `.pluma`.

```
# this is a comment
let x = 42
```

## let

`let name = value` creates a variable. Using `let` on an existing name changes its value.

```
let age = 21
age = age + 1
```

## print

```
print "hello"
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
| `+` `-` `*` `/` `%` `^` | add, subtract, multiply, divide, modulo, power |
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

## function and return

```
function add with a, b
    return a + b

print add with 2, 3
```

## Lists

`list with a, b, c` creates a list. `list with null` creates an empty list.

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

## copy
`copy identifier` copies the contents of a map or list instead of a reference

```
print length "hello"
print length julia
```
