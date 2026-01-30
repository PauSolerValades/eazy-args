# Help String Desings

`tally help`

```
Usage: tally [options] [commands]

Options:
  -v, --verbose       Print more

Commands:
  entry               Manage time entries
    start             Starts an entry
    stop              Stops an active entry
    status            Shows if an entry is active
  project             Manage projects
    create            Creates a new project
    delete            Deletes an existing project
```


`tally entry` or `tally entry -h`

```
Usage: tally entry [options] [commands]

Commands:
  start             Starts an entry
  stop              Stops an active entry
  status            Shows if an entry is active
```


`tally entry start` (or with the help)

```
Usage: tally entry [options] <description>

Options:
  -p,--projectid      Project under which the id should be created

Arguments:
  description         What are you doing?
```
