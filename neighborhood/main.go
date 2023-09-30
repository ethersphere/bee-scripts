package main

import (
	"encoding/binary"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"sort"

	"github.com/ethersphere/bee/pkg/swarm"
)

type Dump struct {
	Nodes []Node
}

type Node struct {
	Overlay     swarm.Address
	FullNode    bool
	Unreachable bool
}

func main() {

	var (
		depth     int
		scanner   string
		input     string
		fullNodes bool
	)

	flag.StringVar(&scanner, "scanner", "https://api.swarmscan.io/v1/network/dump", "the swarmscanner's url")
	flag.IntVar(&depth, "depth", 10, "storage radius for grouping the neighborhoods")
	flag.StringVar(&input, "i", "", "input file or stdin (leave blank to fetch the dump from the scanner)")
	flag.BoolVar(&fullNodes, "fullNodes", true, "filter by node full nodes only")

	flag.Parse()

	var r io.ReadCloser
	if input == "" {
		resp, err := http.Get(scanner)
		if err != nil {
			log.Fatal(err)
		}
		r = resp.Body
	} else if input == "-" {
		fmt.Println("..reading from stdin")
		r = os.Stdin
	} else {
		fmt.Println("..reading from file:", input)
		f, err := os.Open(input)
		if err != nil {
			log.Fatal(err)
		}
		r = f
	}

	if !fullNodes {
		fmt.Println("..including light nodes")
	}

	var d Dump
	err := json.NewDecoder(r).Decode(&d)
	if err != nil {
		log.Fatal(err)
	}

	neighs := neighborhoods(depth)

	counts := map[string]int{}

	selectable := func(n Node) bool {
		if fullNodes {
			if n.FullNode && !n.Unreachable {
				return true
			}
		} else {
			return true
		}
		return false
	}

	for _, n := range neighs {
		counts[n] = 0
	}

	findNodesByNeigh := func(neigh string) (addrs []swarm.Address) {
		for _, n := range d.Nodes {
			if neigh == bitStr(n.Overlay.Bytes(), depth) && selectable(n) {
				addrs = append(addrs, n.Overlay)
			}
		}
		return
	}

	for _, n := range d.Nodes {
		neigh := bitStr(n.Overlay.Bytes(), depth)
		if selectable(n) {
			counts[neigh]++
		}
	}

	// Create slice of key-value pairs
	pairs := make([][2]interface{}, 0, len(counts))
	for k, v := range counts {
		pairs = append(pairs, [2]interface{}{k, v})
	}

	// Sort slice based on values
	sort.Slice(pairs, func(i, j int) bool {
		return pairs[i][1].(int) < pairs[j][1].(int)
	})

	// Extract sorted keys
	keys := make([]string, len(pairs))
	for i, p := range pairs {
		keys[i] = p[0].(string)
	}

	totalCount := 0
	// Print sorted map
	for _, k := range keys {
		count := counts[k]
		fmt.Printf("%s: %d\n", k, count)
		if count > 0 && count < 4 {
			for _, addr := range findNodesByNeigh(k) {
				fmt.Println(addr)
			}
		}
		totalCount += count
	}

	fmt.Printf("----------------------\ntotal count %d, full node & reachable only: %v\n", totalCount, fullNodes)
}

func firstNBits(b []byte, bits int) swarm.Address {

	bytes := bits / 8
	leftover := bits % 8
	if leftover > 0 {
		bytes++
	}

	ret := make([]byte, bytes)
	copy(ret, b)

	// clear all bits to right of the rightmost leftover bits
	// ex: 1111 0000, leftover 2 = 1100 0000
	if leftover > 0 {
		ret[bytes-1] >>= (8 - leftover)
		ret[bytes-1] <<= (8 - leftover)
	}

	return bitToAddr(ret)
}

func neighborhoods(bits int) []string {

	max := 1 << bits
	leftover := bits % 8

	ret := make([]string, 0, max)

	for i := 0; i < max; i++ {
		buf := make([]byte, 4)
		binary.LittleEndian.PutUint32(buf, uint32(i))

		var addr []byte

		if bits <= 8 {
			addr = []byte{buf[0]}
		} else if bits <= 16 {
			addr = []byte{buf[0], buf[1]}
		} else if bits <= 24 {
			addr = []byte{buf[0], buf[1], buf[2]}
		} else if bits <= 32 {
			addr = []byte{buf[0], buf[1], buf[2], buf[3]}
		}

		if leftover > 0 {
			addr[len(addr)-1] <<= (8 - leftover)
		}

		ret = append(ret, bitStr(addr, bits))
	}

	return ret
}

func bitToAddr(b []byte) swarm.Address {
	addr := make([]byte, swarm.HashSize)
	copy(addr, b)
	return swarm.NewAddress(addr)
}

func bitStr(src []byte, bits int) string {

	ret := ""

	for _, b := range src {
		for i := 7; i >= 0; i-- {
			if b&(1<<i) > 0 {
				ret += "1"
			} else {
				ret += "0"
			}
			bits--
			if bits == 0 {
				return ret
			}
		}
	}

	return ret
}
