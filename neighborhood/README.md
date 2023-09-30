# Swarm Neighborhood Population Checker

Calculates neighborhood sizes and prints the sizes in sorted order.

`go run main.go --depth=10`

```
  -depth int
        storage radius for grouping the neighborhoods (default 10)
  -fullNodes
        filter by node full nodes only (default true)
  -i string
        input file or stdin (leave blank to fetch the dump from the scanner)
  -scanner string
        the swarmscanner's url (default "https://api.swarmscan.io/v1/network/dump")
```