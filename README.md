# Pluma

## Comments
```
# this is a comment
```

## I/O
```
print "Hello World!"
```
```
input "prompt"
```

## Variables
```
let x = 10
let y be 20

x is x + 1
x = x * 2
print x
```

## Random
```
random from 0 to 10 # return a value from 0 to 10
```

## Type conversion

`number` converts a certain value to a number (either float or integer).\
`string` converts a value to a string instead

## Lists

```
let numbers be list with 1, 2, 3, 4, 5
```

### Append
```
append 6 to numbers
```

### Maximum / Minimum
```
print maximum of numbers
print minimum of numbers
```

### Slice
```
print slice numbers from 1 to 3
```

### Sort
```
sort numbers # this will sort the list using quick sort
```

## Maps
```
let a_map be map with "one": 1, "two": 2

# or alternatively

let a_map be map with
  "one": 1
  "two": 2
```

## Nothing
```
let empty_list be list with nothing
# nothing is a value that rapresents no data at all
```

## Copy
```
let Person be map with
  "name": nothing
  "age": nothing

let personCp be copy Person
```

## Loops

### While
```
while condition then
  # code
```

### Foreach
```
foreach it in iterable then
  # code
```

## If/else
```
if condition then
  # code
else
  # other code
```

## Range

```
print range from 0 to 10 # with 10 excluded
```

## Functions and return
```
function function_name with [optional arguments]
  # code
  return expression # returning is optional

function_name with [optional arguments]
```
